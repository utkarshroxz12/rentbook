//  CoreMessages.swift
//  WhatsApp message drafts and phone links. Foundation only.

import Foundation

enum MessageKind: String, CaseIterable, Identifiable {
    case politeReminder, firmReminder, partialConfirmation, receipt, increaseNotice, renewal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .politeReminder: return "Polite reminder"
        case .firmReminder: return "Firm reminder"
        case .partialConfirmation: return "Part-payment received"
        case .receipt: return "Payment receipt"
        case .increaseNotice: return "Rent increase notice"
        case .renewal: return "Agreement renewal"
        }
    }

    var contactKind: ContactKind {
        switch self {
        case .politeReminder, .firmReminder: return .reminder
        case .partialConfirmation, .receipt: return .receipt
        case .increaseNotice: return .increase
        case .renewal: return .renewal
        }
    }
}

struct MessageContext {
    var tenant: Tenant
    var place: String
    var ledger: TenantLedger
    var deadline: Date
    var landlord: String
    var payment: PaymentLine? = nil
    var increase: IncreaseProposal? = nil
    var agreement: Agreement? = nil
}

enum Messages {
    /// "Sep 2026 (₹5,000), Oct 2026 (₹10,000)"
    static func unpaidMonths(_ ledger: TenantLedger) -> String {
        ledger.unpaidLines.map { line in
            line.charge.title.replacingOccurrences(of: "Rent · ", with: "") + " (" + Fmt.inr(line.outstanding) + ")"
        }.joined(separator: ", ")
    }

    static func compose(_ kind: MessageKind, _ c: MessageContext) -> String {
        let name = c.tenant.name
        let place = c.place.isEmpty ? "your rented place" : c.place
        let sign = c.landlord.isEmpty ? "" : "\n– " + c.landlord
        let due = Fmt.inr(max(0, c.ledger.outstanding))
        let months = unpaidMonths(c.ledger)
        let deadline = Fmt.longDate(c.deadline)

        switch kind {
        case .politeReminder:
            var text = "Hello " + name + ", this is a gentle reminder that rent of " + due + " for " + place + " is pending"
            if !months.isEmpty { text += " (" + months + ")" }
            text += ". Kindly pay by " + deadline + ". Thank you!"
            return text + sign

        case .firmReminder:
            let since = c.ledger.oldestUnpaid.map { " since " + Fmt.longDate($0.charge.dueDate) } ?? ""
            var text = "Dear " + name + ", rent of " + due + " for " + place + " has been outstanding" + since
            if c.ledger.daysOverdue > 0 { text += " (\(c.ledger.daysOverdue) days)" }
            text += "."
            if !months.isEmpty { text += "\nUnpaid: " + months + "." }
            text += "\nPlease clear the full amount by " + deadline + " without fail."
            return text + sign

        case .partialConfirmation:
            let paid = c.payment.map { Fmt.inr($0.payment.amount) } ?? "your payment"
            let when = c.payment.map { " on " + Fmt.longDate($0.payment.date) } ?? ""
            let balance = c.payment.map { max(0, $0.balanceAfter) } ?? max(0, c.ledger.net)
            var text = "Hello " + name + ", received " + paid + when + " towards rent for " + place + ". Thank you."
            if balance > 0 {
                text += " Balance pending: " + Fmt.inr(balance) + ". Kindly pay the rest by " + deadline + "."
            } else {
                text += " Nothing is pending now."
            }
            return text + sign

        case .receipt:
            guard let line = c.payment else { return "Payment receipt for " + name + "." + sign }
            let p = line.payment
            var text = "RENT RECEIPT"
            if p.receiptNumber > 0 { text += " #\(p.receiptNumber)" }
            text += "\nReceived from: " + name
            text += "\nAmount: " + Fmt.inr(p.amount)
            text += "\nDate: " + Fmt.date(p.date)
            text += "\nMode: " + p.method.label + (p.reference.isEmpty ? "" : " (Ref " + p.reference + ")")
            let covers = line.applications.map { $0.title.replacingOccurrences(of: "Rent · ", with: "Rent ") }
            if !covers.isEmpty { text += "\nFor: " + covers.joined(separator: ", ") }
            text += "\nProperty: " + place
            if line.balanceAfter > 0 {
                text += "\nBalance due: " + Fmt.inr(line.balanceAfter)
            } else if line.balanceAfter < 0 {
                text += "\nAdvance: " + Fmt.inr(-line.balanceAfter)
            } else {
                text += "\nBalance due: Nil"
            }
            return text + sign

        case .increaseNotice:
            guard let inc = c.increase else { return "Hello " + name + "." + sign }
            return "Hello " + name + ", as per our agreement, the monthly rent for " + place + " will be revised from "
                + Fmt.inr(inc.from) + " to " + Fmt.inr(inc.to) + " with effect from " + Fmt.longDate(inc.date)
                + ". Thank you for your cooperation." + sign

        case .renewal:
            let end = c.agreement?.endDate
            let endText = end.map { Fmt.longDate($0) } ?? "soon"
            return "Hello " + name + ", your rental agreement for " + place + " ends on " + endText
                + ". Please let me know if you would like to renew it so we can arrange the paperwork in time. Thank you." + sign
        }
    }

    // MARK: Amount in words

    /// Indian numbering: 1,23,456 → "One Lakh Twenty Three Thousand Four Hundred Fifty Six".
    static func rupeesInWords(_ amount: Int) -> String {
        if amount == 0 { return "Zero" }
        if amount < 0 { return "Minus " + rupeesInWords(-amount) }
        let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
                    "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
        let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

        func belowHundred(_ n: Int) -> String {
            if n < 20 { return ones[n] }
            let rest = n % 10
            return tens[n / 10] + (rest > 0 ? " " + ones[rest] : "")
        }

        func belowThousand(_ n: Int) -> String {
            var parts: [String] = []
            if n >= 100 { parts.append(ones[n / 100] + " Hundred") }
            if n % 100 > 0 { parts.append(belowHundred(n % 100)) }
            return parts.joined(separator: " ")
        }

        var parts: [String] = []
        let crore = amount / 10_000_000
        let lakh = (amount / 100_000) % 100
        let thousand = (amount / 1_000) % 100
        let rest = amount % 1_000
        if crore > 0 { parts.append(rupeesInWords(crore) + " Crore") }
        if lakh > 0 { parts.append(belowHundred(lakh) + " Lakh") }
        if thousand > 0 { parts.append(belowHundred(thousand) + " Thousand") }
        if rest > 0 { parts.append(belowThousand(rest)) }
        return parts.joined(separator: " ")
    }

    // MARK: Phone links

    /// Digits only, with India's country code added to 10-digit numbers.
    static func phoneDigits(_ phone: String) -> String {
        var digits = phone.filter { $0.isASCII && $0.isNumber }
        if digits.count == 11 && digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 10 { digits = "91" + digits }
        return digits
    }

    static func whatsappURL(phone: String, text: String) -> URL? {
        let digits = phoneDigits(phone)
        guard digits.count >= 11 else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "wa.me"
        comps.path = "/" + digits
        comps.queryItems = [URLQueryItem(name: "text", value: text)]
        if let query = comps.percentEncodedQuery {
            comps.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        return comps.url
    }

    static func callURL(phone: String) -> URL? {
        let digits = phoneDigits(phone)
        guard digits.count >= 10 else { return nil }
        return URL(string: "tel:+" + digits)
    }

    static func emailURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { return nil }
        return URL(string: "mailto:" + trimmed)
    }
}
