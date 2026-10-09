//  CoreLedger.swift
//  Rent charges, payment allocation and balances.
//  Every total is worked out from the stored records each time it is needed,
//  never kept as a separate status field. Foundation only.

import Foundation

// MARK: - Charges

/// One amount a tenant owes: a billing period's rent, a recurring extra,
/// a one-off charge or older dues. Charges are generated from the tenancy
/// terms, and each has a fixed key, so a month can never be billed twice.
struct Charge: Identifiable, Hashable {
    enum Kind: Int, Hashable {
        case opening = 0, rent = 1, recurring = 2, extra = 3, refundExcess = 4
    }

    var key: String
    var kind: Kind
    var title: String
    var periodStart: Date?
    var periodEnd: Date?
    var dueDate: Date
    var baseAmount: Int
    var adjustment = 0
    var waived = false
    var notes: [String] = []

    var id: String { key }
    var amount: Int { waived ? 0 : max(0, baseAmount + adjustment) }
}

struct ChargeLine: Identifiable, Hashable {
    var charge: Charge
    var paid: Int

    var id: String { charge.key }
    var outstanding: Int { max(0, charge.amount - paid) }
}

struct PaymentApplication: Hashable {
    var chargeKey: String
    var title: String
    var amount: Int
}

struct PaymentLine: Identifiable, Hashable {
    var payment: Payment
    var applications: [PaymentApplication]
    var unapplied: Int
    var balanceAfter: Int

    var id: UUID { payment.id }
}

enum PayStatus: String, CaseIterable, Identifiable {
    case paid, partial, unpaid, overdue, noDues
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paid: return "Paid"
        case .partial: return "Partly paid"
        case .unpaid: return "Unpaid"
        case .overdue: return "Overdue"
        case .noDues: return "No dues yet"
        }
    }
}

/// The full rent position of one tenancy on a given day.
struct TenantLedger {
    var asOf: Date
    var graceDays: Int
    var lines: [ChargeLine]
    var payments: [PaymentLine]
    var dueLines: [ChargeLine]
    var upcomingLines: [ChargeLine]
    var unpaidLines: [ChargeLine]
    var overdueLines: [ChargeLine]
    var totalBilled: Int
    var totalPaid: Int
    var outstanding: Int
    var overdue: Int
    /// Money paid that has not been used for any month yet.
    var advanceCredit: Int
    /// Money already put towards months that are not due yet.
    var prepaid: Int
    var currentDue: Int
    var arrears: Int
    var oldestUnpaid: ChargeLine?
    var daysOverdue: Int
    var status: PayStatus
    var lastPaymentDate: Date?
    var nextRentLine: ChargeLine?
    var orphanAdjustments: Int

    var credit: Int { advanceCredit + prepaid }
    /// Positive: the tenant owes this much. Negative: they are in credit.
    var net: Int { outstanding - advanceCredit - prepaid }
}

struct DepositSummary: Hashable {
    var received = 0
    var additional = 0
    var deducted = 0
    var refunded = 0

    var totalIn: Int { received + additional }
    var held: Int { received + additional - deducted - refunded }
}

enum Ledger {
    // MARK: Rent amounts

    /// The monthly rent in force on a given day (the latest change on or before it).
    static func rent(of t: Tenant, on date: Date) -> Int {
        let day = DateMath.day(date)
        let history = t.rentHistory.sorted { $0.effectiveDate < $1.effectiveDate }
        guard var amount = history.first?.amount else { return 0 }
        for change in history where DateMath.day(change.effectiveDate) <= day {
            amount = change.amount
        }
        return amount
    }

    static func currentRent(of t: Tenant, asOf: Date = Date()) -> Int {
        rent(of: t, on: asOf)
    }

    static func chargeOrder(_ a: Charge, _ b: Charge) -> Bool {
        if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
        if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
        return a.key < b.key
    }

    static func paymentOrder(_ a: Payment, _ b: Payment) -> Bool {
        let dayA = DateMath.day(a.date)
        let dayB = DateMath.day(b.date)
        if dayA != dayB { return dayA < dayB }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    // MARK: Charge generation

    /// All charges for a tenancy up to the month containing `horizon`, with
    /// discounts, waivers and corrections applied. The second value counts
    /// adjustments whose billing period no longer exists.
    static func buildCharges(for t: Tenant, horizon: Date) -> (charges: [Charge], orphans: Int) {
        var result: [Charge] = []
        let billingStart = t.billingStartDate ?? t.startDate

        if t.openingBalance > 0 {
            let due = DateMath.day(billingStart ?? t.createdAt)
            result.append(Charge(key: "opening", kind: .opening, title: "Older dues",
                                 periodStart: nil, periodEnd: nil, dueDate: due,
                                 baseAmount: t.openingBalance))
        }

        if let start = billingStart {
            result += periodCharges(for: t, billingStart: start, horizon: horizon)
        }

        for a in t.adjustments where a.kind == .extraCharge && !a.isReversed && a.amount > 0 {
            let title = a.title.isEmpty ? "Extra charge" : a.title
            let notes = a.reason.isEmpty ? [] : [a.reason]
            result.append(Charge(key: "adj-" + a.id.uuidString, kind: .extra, title: title,
                                 periodStart: nil, periodEnd: nil, dueDate: DateMath.day(a.date),
                                 baseAmount: a.amount, notes: notes))
        }

        var orphans = 0
        for a in t.adjustments where a.kind != .extraCharge && !a.isReversed {
            guard let key = a.periodKey, let i = result.firstIndex(where: { $0.key == key }) else {
                orphans += 1
                continue
            }
            let because = a.reason.isEmpty ? "" : " (\(a.reason))"
            switch a.kind {
            case .discount:
                result[i].adjustment -= abs(a.amount)
                result[i].notes.append("Discount " + Fmt.inr(abs(a.amount)) + because)
            case .waiver:
                result[i].waived = true
                result[i].notes.append("Waived" + because)
            case .correction:
                result[i].adjustment += a.amount
                let sign = a.amount >= 0 ? "+" : "-"
                result[i].notes.append("Correction " + sign + Fmt.inr(abs(a.amount)) + because)
            case .extraCharge:
                break
            }
        }

        return (result.sorted(by: chargeOrder), orphans)
    }

    static func charges(for t: Tenant, horizon: Date) -> [Charge] {
        buildCharges(for: t, horizon: horizon).charges
    }

    /// Rent and recurring charges for each billing period. Periods follow calendar
    /// months (or blocks of 3, 6 or 12 months). Rent is due on the tenant's due day
    /// in the first month of the period, or on the start date if that is later.
    private static func periodCharges(for t: Tenant, billingStart: Date, horizon: Date) -> [Charge] {
        var out: [Charge] = []
        let monthsPerPeriod = max(1, t.frequency.rawValue)
        let billingFrom = DateMath.day(billingStart)
        let occupancyStart: Date
        if let moveIn = t.startDate.map({ DateMath.day($0) }), billingFrom > moveIn {
            // Billing was switched on after the tenant moved in: bill whole months from that month.
            occupancyStart = max(DateMath.monthStart(billingFrom), moveIn)
        } else {
            occupancyStart = DateMath.day(max(billingStart, t.startDate ?? billingStart))
        }
        let occupancyEnd: Date? = t.endDate.map { DateMath.day($0) }
        let lastPeriodStart = DateMath.monthStart(horizon)
        var periodStart = DateMath.monthStart(occupancyStart)
        var safety = 0

        while periodStart <= lastPeriodStart && safety < 1200 {
            safety += 1
            if let end = occupancyEnd, periodStart > end { break }

            var rentTotal = 0
            var recurringTotals: [UUID: Int] = [:]
            var notes: [String] = []
            var firstOccupiedDay: Date? = nil

            for k in 0..<monthsPerPeriod {
                let month = DateMath.addMonths(k, to: periodStart)
                let monthEnd = DateMath.monthEnd(month)
                let from = max(month, occupancyStart)
                let to = occupancyEnd.map { min(monthEnd, $0) } ?? monthEnd
                if from > to { continue }

                let daysInMonth = DateMath.daysInMonth(month)
                let occupiedDays = DateMath.daysBetween(from, to) + 1
                let dueInMonth = max(DateMath.dueDate(inMonthOf: month, day: t.dueDay), from)
                var fraction = 1.0

                if occupiedDays < daysInMonth {
                    let isFirst = from > month
                    let isLast = to < monthEnd
                    if (isFirst && t.prorateFirst) || (isLast && t.prorateLast) {
                        fraction = Double(occupiedDays) / Double(daysInMonth)
                        notes.append(Fmt.month(month) + ": \(occupiedDays) of \(daysInMonth) days")
                    } else if isLast && dueInMonth > to {
                        // Not prorating the final month: only billed if rent fell due before moving out.
                        continue
                    }
                }

                if firstOccupiedDay == nil { firstOccupiedDay = from }
                rentTotal += Int((Double(rent(of: t, on: dueInMonth)) * fraction).rounded())

                // Like rent, a monthly extra counts for a month if it is in force on that
                // month's due date, so a change part-way through a month never bills it twice.
                let reference = min(dueInMonth, to)
                for rc in t.recurringCharges where rc.amount > 0 {
                    if let s = rc.startDate, DateMath.day(s) > reference { continue }
                    if let e = rc.endDate, DateMath.day(e) < reference { continue }
                    recurringTotals[rc.id, default: 0] += Int((Double(rc.amount) * fraction).rounded())
                }
            }

            if let firstDay = firstOccupiedDay {
                var due = DateMath.dueDate(inMonthOf: periodStart, day: t.dueDay)
                if due < firstDay { due = firstDay }
                let periodEnd = DateMath.monthEnd(DateMath.addMonths(monthsPerPeriod - 1, to: periodStart))
                let monthKey = DateMath.monthKey(periodStart)
                let label = monthsPerPeriod == 1 ? Fmt.month(periodStart) : Fmt.monthRange(periodStart, periodEnd)

                if rentTotal > 0 {
                    out.append(Charge(key: "rent-" + monthKey, kind: .rent, title: "Rent · " + label,
                                      periodStart: periodStart, periodEnd: periodEnd, dueDate: due,
                                      baseAmount: rentTotal, notes: notes))
                }
                for rc in t.recurringCharges {
                    guard let amount = recurringTotals[rc.id], amount > 0 else { continue }
                    let name = rc.title.isEmpty ? "Charge" : rc.title
                    out.append(Charge(key: "rc-" + rc.id.uuidString + "-" + monthKey, kind: .recurring,
                                      title: name + " · " + label, periodStart: periodStart,
                                      periodEnd: periodEnd, dueDate: due, baseAmount: amount))
                }
            }

            periodStart = DateMath.addMonths(monthsPerPeriod, to: periodStart)
        }
        return out
    }

    // MARK: The ledger

    /// Works out every charge, how each payment was used, and the balances.
    /// Payments with chosen months settle those first; everything else settles
    /// the oldest due charges first and then pays the coming months in order
    /// (shown as paid ahead). Money beyond the next twelve months stays as
    /// unused advance credit.
    static func ledger(for t: Tenant, asOf: Date = Date(), graceDays: Int = 0, horizonMonths: Int = 12) -> TenantLedger {
        let today = DateMath.day(asOf)
        let built = buildCharges(for: t, horizon: DateMath.addMonths(horizonMonths, to: today))
        var charges = built.charges
        let byKey = Dictionary(charges.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        let valid = t.payments
            .filter { !$0.isReversed && $0.kind == .payment && $0.amount > 0 }
            .sorted(by: paymentOrder)
        let refunds = t.payments.filter { !$0.isReversed && $0.kind == .refund && $0.amount > 0 }

        var paid: [String: Int] = [:]
        var applied: [UUID: [PaymentApplication]] = [:]
        var leftovers: [(id: UUID, amount: Int)] = []

        // 1. Months chosen by hand.
        for p in valid {
            var remaining = p.amount
            for a in p.manualAllocations ?? [] where a.amount > 0 && remaining > 0 {
                guard let ch = byKey[a.chargeKey] else { continue }
                let room = ch.amount - paid[ch.key, default: 0]
                let x = min(a.amount, room, remaining)
                guard x > 0 else { continue }
                paid[ch.key, default: 0] += x
                applied[p.id, default: []].append(PaymentApplication(chargeKey: ch.key, title: ch.title, amount: x))
                remaining -= x
            }
            leftovers.append((id: p.id, amount: remaining))
        }

        // 2. Refunds come out of unused money, newest payment first,
        var refundLeft = refunds.reduce(0) { $0 + $1.amount }
        var index = leftovers.count - 1
        while refundLeft > 0 && index >= 0 {
            let x = min(leftovers[index].amount, refundLeft)
            leftovers[index].amount -= x
            refundLeft -= x
            index -= 1
        }
        // then out of months paid ahead by choice that are not due yet, latest month first.
        for p in valid.reversed() where refundLeft > 0 {
            guard var apps = applied[p.id] else { continue }
            let order = apps.indices.sorted {
                (byKey[apps[$0].chargeKey]?.dueDate ?? .distantPast) > (byKey[apps[$1].chargeKey]?.dueDate ?? .distantPast)
            }
            for i in order where refundLeft > 0 {
                guard let ch = byKey[apps[i].chargeKey], ch.dueDate > today else { continue }
                let x = min(apps[i].amount, refundLeft)
                apps[i].amount -= x
                paid[ch.key, default: 0] -= x
                refundLeft -= x
            }
            applied[p.id] = apps.filter { $0.amount > 0 }
        }
        // Only a refund larger than all of that is owed back.
        if refundLeft > 0, let lastRefund = refunds.map({ $0.date }).max() {
            charges.append(Charge(key: "refund-excess", kind: .refundExcess, title: "Refunded beyond credit",
                                  periodStart: nil, periodEnd: nil, dueDate: DateMath.day(lastRefund),
                                  baseAmount: refundLeft))
            charges.sort(by: chargeOrder)
        }

        // 3. Everything else settles the oldest charges first: all dues, then the coming
        //    months in order, so money paid early pays the next rent before it falls due.
        let fillOrder = charges
        var cursor = 0
        var unapplied: [UUID: Int] = [:]
        for entry in leftovers {
            var remaining = entry.amount
            while remaining > 0 && cursor < fillOrder.count {
                let ch = fillOrder[cursor]
                let room = ch.amount - paid[ch.key, default: 0]
                if room <= 0 {
                    cursor += 1
                    continue
                }
                let x = min(room, remaining)
                paid[ch.key, default: 0] += x
                applied[entry.id, default: []].append(PaymentApplication(chargeKey: ch.key, title: ch.title, amount: x))
                remaining -= x
            }
            unapplied[entry.id] = remaining
        }

        // 4. Totals.
        let lines = charges.map { ChargeLine(charge: $0, paid: paid[$0.key, default: 0]) }
        let dueLines = lines.filter { $0.charge.dueDate <= today }
        let upcomingLines = lines.filter { $0.charge.dueDate > today }
        let unpaidLines = dueLines.filter { $0.outstanding > 0 }
        let overdueLines = unpaidLines.filter { DateMath.daysBetween($0.charge.dueDate, today) > graceDays }
        let outstanding = unpaidLines.reduce(0) { $0 + $1.outstanding }
        let overdue = overdueLines.reduce(0) { $0 + $1.outstanding }
        let advance = unapplied.values.reduce(0, +)
        let prepaid = upcomingLines.reduce(0) { $0 + $1.paid }
        let monthStart = DateMath.monthStart(today)
        let currentDue = unpaidLines.filter { line in
            if let start = line.charge.periodStart, let end = line.charge.periodEnd {
                return start <= today && today <= end
            }
            return line.charge.dueDate >= monthStart
        }.reduce(0) { $0 + $1.outstanding }

        let status: PayStatus
        if dueLines.isEmpty {
            status = .noDues
        } else if outstanding == 0 {
            status = .paid
        } else if overdue > 0 {
            status = .overdue
        } else if unpaidLines.contains(where: { $0.paid > 0 }) {
            status = .partial
        } else {
            status = .unpaid
        }

        // 5. Balance after each payment: charges due by that day, or whose billing period
        //    had begun, minus net money paid by then. Paying this month's rent a few days
        //    before the due date leaves a balance of nil rather than an "advance".
        let billable = charges.filter { $0.kind != .refundExcess }
        var paymentLines: [PaymentLine] = []
        var paidSoFar = 0
        for p in t.payments.sorted(by: paymentOrder) {
            if !p.isReversed {
                paidSoFar += p.kind == .payment ? p.amount : -p.amount
            }
            let day = DateMath.day(p.date)
            let billedByThen = billable
                .filter { $0.dueDate <= day || ($0.periodStart.map { $0 <= day } ?? false) }
                .reduce(0) { $0 + $1.amount }
            paymentLines.append(PaymentLine(payment: p,
                                            applications: applied[p.id] ?? [],
                                            unapplied: unapplied[p.id] ?? 0,
                                            balanceAfter: billedByThen - paidSoFar))
        }

        let totalBilled = dueLines.filter { $0.charge.kind != .refundExcess }.reduce(0) { $0 + $1.charge.amount }
        let totalPaid = valid.reduce(0) { $0 + $1.amount } - refunds.reduce(0) { $0 + $1.amount }
        let oldest = unpaidLines.first
        let daysOverdue = oldest.map { max(0, DateMath.daysBetween($0.charge.dueDate, today)) } ?? 0
        let nextRent = lines.first { $0.charge.kind == .rent && $0.charge.dueDate >= today }

        return TenantLedger(asOf: today,
                            graceDays: graceDays,
                            lines: lines,
                            payments: paymentLines,
                            dueLines: dueLines,
                            upcomingLines: upcomingLines,
                            unpaidLines: unpaidLines,
                            overdueLines: overdueLines,
                            totalBilled: totalBilled,
                            totalPaid: totalPaid,
                            outstanding: outstanding,
                            overdue: overdue,
                            advanceCredit: advance,
                            prepaid: prepaid,
                            currentDue: currentDue,
                            arrears: outstanding - currentDue,
                            oldestUnpaid: oldest,
                            daysOverdue: daysOverdue,
                            status: status,
                            lastPaymentDate: valid.map { $0.date }.max(),
                            nextRentLine: nextRent,
                            orphanAdjustments: built.orphans)
    }

    /// Fills the oldest open charges first with an amount, for the manual allocation screen.
    static func suggestAllocation(amount: Int, lines: [ChargeLine]) -> [String: Int] {
        var left = amount
        var result: [String: Int] = [:]
        for line in lines where line.outstanding > 0 && left > 0 {
            let x = min(line.outstanding, left)
            result[line.charge.key] = x
            left -= x
        }
        return result
    }

    // MARK: Security deposit

    static func deposit(of t: Tenant) -> DepositSummary {
        var s = DepositSummary()
        for e in t.deposits where !e.isReversed {
            switch e.kind {
            case .received: s.received += e.amount
            case .additional: s.additional += e.amount
            case .deduction: s.deducted += e.amount
            case .refund: s.refunded += e.amount
            }
        }
        return s
    }
}
