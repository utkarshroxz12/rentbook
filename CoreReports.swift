//  CoreReports.swift
//  Financial reports as plain tables, with CSV export and chart points.
//  Foundation only.

import Foundation

struct ChartPoint: Identifiable, Hashable {
    var label: String
    var series: String
    var value: Int
    var order: Int
    var id: String { series + "|" + label }
}

struct ReportTable {
    var title: String
    var subtitle: String
    var columns: [String]
    var rows: [[String]]
    var totals: [String]? = nil
    var chart: [ChartPoint] = []
    var note = ""

    /// Comma-separated text for spreadsheets. Rupee amounts become plain numbers.
    var csv: String {
        var lines = [columns.map(ReportTable.csvCell).joined(separator: ",")]
        for row in rows {
            lines.append(row.map(ReportTable.csvCell).joined(separator: ","))
        }
        if let totals = totals {
            lines.append(totals.map(ReportTable.csvCell).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func csvCell(_ text: String) -> String {
        var s = text
        if s.hasPrefix("₹") || s.hasPrefix("-₹") {
            s = s.replacingOccurrences(of: "₹", with: "").replacingOccurrences(of: ",", with: "")
        }
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

enum SummaryGrouping: String, CaseIterable, Identifiable, Hashable {
    case month, quarter, financialYear
    var id: String { rawValue }
    var label: String {
        switch self {
        case .month: return L("Monthly", "Har mahine")
        case .quarter: return L("Quarterly", "Har 3 mahine")
        case .financialYear: return "Financial year"
        }
    }
}

enum ReportKind: String, CaseIterable, Identifiable, Hashable {
    case monthlyCollection, annualCollection, expectedVsActual, outstanding, overdue, tenantLedger
    case paymentsList, paymentMethods, propertyIncome, expenses, netIncome
    case advanceCredit, deposits, increaseHistory, agreementExpiry
    case periodSummary, partnerSettlement, partnerAllocation, repairs, utilityUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthlyCollection: return L("Monthly collection", "Mahine ki vasooli")
        case .annualCollection: return L("Annual collection", "Saal ki vasooli")
        case .expectedVsActual: return L("Expected vs collected", "Aana tha vs mila")
        case .outstanding: return L("Outstanding rent", "Baaki rent")
        case .overdue: return "Overdue rent"
        case .tenantLedger: return "Tenant ledger"
        case .paymentsList: return "Payments"
        case .paymentMethods: return L("Payment methods", "Payment ke tarike")
        case .propertyIncome: return L("Property income", "Property ki income")
        case .expenses: return L("Expenses", "Kharche")
        case .netIncome: return L("Net rental income", "Net rent income")
        case .advanceCredit: return L("Advance and credit", "Advance aur credit")
        case .deposits: return L("Security deposits", "Security deposit")
        case .increaseHistory: return L("Rent increase history", "Rent badhotri history")
        case .agreementExpiry: return L("Agreement expiry", "Agreement khatam hone ki tareekh")
        case .periodSummary: return L("Income and expense summary", "Income aur kharcha summary")
        case .partnerSettlement: return L("Partner settlement", "Partner hisaab")
        case .partnerAllocation: return L("Expense sharing", "Kharcha batwara")
        case .repairs: return L("Repairs", "Repair")
        case .utilityUsage: return L("Electricity and water", "Bijli aur paani")
        }
    }

    var detail: String {
        switch self {
        case .monthlyCollection: return L("Expected and collected rent for each month, with a trend chart", "Har mahine aane wala aur mila rent, chart ke saath")
        case .annualCollection: return L("Totals for each financial year (April to March)", "Har financial year ka total (April se March)")
        case .expectedVsActual: return L("Each tenant's billed rent against what they paid", "Har tenant ka bana rent aur unka diya hua")
        case .outstanding: return L("Who owes what today, and since when", "Aaj kiska kitna baaki, aur kab se")
        case .overdue: return L("Dues past the grace period", "Grace period ke baad ka baaki")
        case .tenantLedger: return L("Every charge and payment for one tenant, with running balance", "Ek tenant ka har charge aur payment, balance ke saath")
        case .paymentsList: return L("All payments received in a period", "Ek samay mein mile saare payment")
        case .paymentMethods: return L("How rent was paid: UPI, cash, bank and others", "Rent kaise mila: UPI, cash, bank aur baaki")
        case .propertyIncome: return L("Collection, expenses and net income for each property", "Har property ki vasooli, kharche aur net income")
        case .expenses: return L("Property expenses by date and category", "Property ke kharche, tareekh aur category se")
        case .netIncome: return L("Rent collected minus expenses, month by month", "Mila rent minus kharche, mahine dar mahine")
        case .advanceCredit: return L("Money paid ahead of time", "Pehle se diya gaya paisa")
        case .deposits: return L("Deposits received, deducted, refunded and held", "Deposit mila, kata, wapas diya aur jama")
        case .increaseHistory: return L("Every rent change with reasons", "Har rent badlav, kaaran ke saath")
        case .agreementExpiry: return L("Agreement end dates and status", "Agreement khatam hone ki tareekh aur status")
        case .periodSummary: return L("Rent collected, expenses and net income by month, quarter or financial year", "Mila rent, kharche aur net income: mahine, quarter ya financial year ke hisaab se")
        case .partnerSettlement: return L("Each month's rent, shared expenses, transfers and the balance with your partner", "Har mahine ka rent, shared kharche, len-den aur partner ke saath balance")
        case .partnerAllocation: return L("Who paid each expense and each partner's share", "Har kharcha kisne diya aur har partner ka hissa")
        case .repairs: return L("Repair jobs with status, cost and who paid", "Repair ke kaam: status, kharcha aur kisne diya")
        case .utilityUsage: return L("Meter readings, units used and bills", "Meter reading, kitne unit aur bill")
        }
    }

    var usesDateRange: Bool {
        switch self {
        case .outstanding, .overdue, .advanceCredit, .deposits, .agreementExpiry: return false
        default: return true
        }
    }

    var needsTenant: Bool { self == .tenantLedger }
    var usesGrouping: Bool { self == .periodSummary }
}

struct ReportFilter: Hashable {
    var from: Date
    var to: Date
    var propertyID: UUID? = nil
    var tenantID: UUID? = nil
    var grouping: SummaryGrouping = .month
}

enum Reports {
    static func build(_ kind: ReportKind, data: AppData, filter: ReportFilter, asOf: Date = Date()) -> ReportTable {
        switch kind {
        case .monthlyCollection: return monthlyCollection(data, filter, asOf: asOf)
        case .annualCollection: return annualCollection(data, filter, asOf: asOf)
        case .expectedVsActual: return expectedVsActual(data, filter, asOf: asOf)
        case .outstanding: return outstanding(data, filter, asOf: asOf, overdueOnly: false)
        case .overdue: return outstanding(data, filter, asOf: asOf, overdueOnly: true)
        case .tenantLedger: return tenantLedger(data, filter)
        case .paymentsList: return paymentsList(data, filter)
        case .paymentMethods: return paymentMethods(data, filter)
        case .propertyIncome: return propertyIncome(data, filter)
        case .expenses: return expenses(data, filter)
        case .netIncome: return netIncome(data, filter)
        case .advanceCredit: return advanceCredit(data, filter, asOf: asOf)
        case .deposits: return deposits(data, filter)
        case .increaseHistory: return increaseHistory(data, filter)
        case .agreementExpiry: return agreementExpiry(data, filter, asOf: asOf)
        case .periodSummary: return periodSummary(data, filter)
        case .partnerSettlement: return partnerSettlement(data, filter, asOf: asOf)
        case .partnerAllocation: return partnerAllocation(data, filter)
        case .repairs: return repairs(data, filter)
        case .utilityUsage: return utilityUsage(data, filter)
        }
    }

    // MARK: Helpers

    private static func scope(_ data: AppData, _ f: ReportFilter, includeArchived: Bool) -> [Tenant] {
        data.tenants.filter { t in
            (includeArchived || !t.isArchived)
                && (f.propertyID == nil || t.propertyID == f.propertyID)
                && (f.tenantID == nil || t.id == f.tenantID)
        }
    }

    static func place(_ t: Tenant, _ data: AppData) -> String {
        let p = data.properties.first { $0.id == t.propertyID }
        let unit = Portfolio.unitName(t.unitID, in: p)
        let name = p?.name ?? "—"
        return unit.isEmpty ? name : unit + ", " + name
    }

    private static func rangeText(_ f: ReportFilter) -> String {
        Fmt.date(f.from) + L(" to ", " – ") + Fmt.date(f.to)
    }

    private static func months(_ f: ReportFilter) -> [Date] {
        var list: [Date] = []
        var m = DateMath.monthStart(f.from)
        let last = DateMath.monthStart(f.to)
        while m <= last && list.count < 240 {
            list.append(m)
            m = DateMath.addMonths(1, to: m)
        }
        return list
    }

    private static func inRange(_ d: Date, _ from: Date, _ to: Date) -> Bool {
        let day = DateMath.day(d)
        return day >= DateMath.day(from) && day <= DateMath.day(to)
    }

    /// Charges due between two days, counting only those due by `asOf`, so a period
    /// that runs into the future is not shown as short of rent that isn't due yet.
    private static func billed(_ charges: [Charge], from: Date, to: Date, asOf: Date) -> Int {
        let end = min(DateMath.day(to), DateMath.day(asOf))
        return charges.filter { $0.kind != .refundExcess && inRange($0.dueDate, from, end) }.reduce(0) { $0 + $1.amount }
    }

    private static let expectedNote = L("Expected counts rent and charges due up to today.", "Aana tha mein aaj tak ke rent aur charges gine gaye hain.")

    private static func chargeMap(_ tenants: [Tenant], horizon: Date) -> [UUID: [Charge]] {
        var map: [UUID: [Charge]] = [:]
        for t in tenants {
            map[t.id] = Ledger.charges(for: t, horizon: horizon)
        }
        return map
    }

    private static func scopedExpenses(_ data: AppData, _ f: ReportFilter) -> [Expense] {
        data.expenses.filter { e in
            !e.isArchived && (f.propertyID == nil || e.propertyID == f.propertyID) && inRange(e.date, f.from, f.to)
        }
    }

    // MARK: Collection

    private static func monthlyCollection(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        let tenants = scope(data, f, includeArchived: true)
        let charges = chargeMap(tenants, horizon: f.to)
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var totalExpected = 0
        var totalCollected = 0
        for (i, month) in months(f).enumerated() {
            let end = DateMath.monthEnd(month)
            let expected = tenants.reduce(0) { $0 + billed(charges[$1.id] ?? [], from: month, to: end, asOf: asOf) }
            let collected = tenants.reduce(0) { $0 + Portfolio.netCollected($1, from: month, to: end) }
            totalExpected += expected
            totalCollected += collected
            let label = Fmt.month(month)
            rows.append([label, Fmt.inr(expected), Fmt.inr(collected), Fmt.inr(collected - expected)])
            chart.append(ChartPoint(label: label, series: L("Expected", "Aana tha"), value: expected, order: i))
            chart.append(ChartPoint(label: label, series: L("Collected", "Mila"), value: collected, order: i))
        }
        return ReportTable(title: L("Monthly collection", "Mahine ki vasooli"), subtitle: rangeText(f),
                           columns: [L("Month", "Mahina"), L("Expected", "Aana tha"), L("Collected", "Mila"), L("Difference", "Antar")], rows: rows,
                           totals: [L("Total", "Kul"), Fmt.inr(totalExpected), Fmt.inr(totalCollected), Fmt.inr(totalCollected - totalExpected)],
                           chart: chart, note: expectedNote)
    }

    private static func annualCollection(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        let tenants = scope(data, f, includeArchived: true)
        let charges = chargeMap(tenants, horizon: f.to)
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var start = DateMath.financialYearStart(f.from)
        let lastStart = DateMath.financialYearStart(f.to)
        var i = 0
        while start <= lastStart && i < 50 {
            let end = DateMath.addDays(-1, to: DateMath.addMonths(12, to: start))
            let expected = tenants.reduce(0) { $0 + billed(charges[$1.id] ?? [], from: start, to: end, asOf: asOf) }
            let collected = tenants.reduce(0) { $0 + Portfolio.netCollected($1, from: start, to: end) }
            let year = rbCalendar.component(.year, from: start)
            let label = "FY \(year)-" + String(String(year + 1).suffix(2))
            rows.append([label, Fmt.inr(expected), Fmt.inr(collected), Fmt.inr(collected - expected)])
            chart.append(ChartPoint(label: label, series: L("Expected", "Aana tha"), value: expected, order: i))
            chart.append(ChartPoint(label: label, series: L("Collected", "Mila"), value: collected, order: i))
            start = DateMath.addMonths(12, to: start)
            i += 1
        }
        return ReportTable(title: L("Annual collection", "Saal ki vasooli"), subtitle: L("Financial years, April to March", "Financial year, April se March"),
                           columns: [L("Year", "Saal"), L("Expected", "Aana tha"), L("Collected", "Mila"), L("Difference", "Antar")], rows: rows, chart: chart,
                           note: expectedNote)
    }

    private static func expectedVsActual(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        let tenants = scope(data, f, includeArchived: true).sorted { $0.name < $1.name }
        let charges = chargeMap(tenants, horizon: f.to)
        var rows: [[String]] = []
        var te = 0
        var tc = 0
        for t in tenants {
            let expected = billed(charges[t.id] ?? [], from: f.from, to: f.to, asOf: asOf)
            let collected = Portfolio.netCollected(t, from: f.from, to: f.to)
            if expected == 0 && collected == 0 { continue }
            te += expected
            tc += collected
            rows.append([t.name, place(t, data), Fmt.inr(expected), Fmt.inr(collected), Fmt.inr(collected - expected)])
        }
        return ReportTable(title: L("Expected vs collected", "Aana tha vs mila"), subtitle: rangeText(f),
                           columns: ["Tenant", "Property", L("Expected", "Aana tha"), L("Collected", "Mila"), L("Difference", "Antar")], rows: rows,
                           totals: [L("Total", "Kul"), "", Fmt.inr(te), Fmt.inr(tc), Fmt.inr(tc - te)], note: expectedNote)
    }

    // MARK: Dues

    private static func outstanding(_ data: AppData, _ f: ReportFilter, asOf: Date, overdueOnly: Bool) -> ReportTable {
        let grace = data.settings.gracePeriodDays
        var items: [(Tenant, TenantLedger)] = []
        for t in scope(data, f, includeArchived: false) {
            let ledger = Ledger.ledger(for: t, asOf: asOf, graceDays: grace)
            let amount = overdueOnly ? ledger.overdue : ledger.outstanding
            if amount > 0 { items.append((t, ledger)) }
        }
        items.sort { (overdueOnly ? $0.1.overdue : $0.1.outstanding) > (overdueOnly ? $1.1.overdue : $1.1.outstanding) }
        var total = 0
        var byProperty: [String: Int] = [:]
        let rows: [[String]] = items.map { item in
            let (t, ledger) = item
            let amount = overdueOnly ? ledger.overdue : ledger.outstanding
            total += amount
            byProperty[Reports.propertyOnly(t, data), default: 0] += amount
            let oldest = ledger.oldestUnpaid?.charge.title ?? ""
            return [t.name, place(t, data), Fmt.inr(amount), oldest, "\(ledger.daysOverdue)"]
        }
        let note = byProperty.sorted { $0.value > $1.value }
            .map { $0.key + ": " + Fmt.inr($0.value) }
            .joined(separator: "\n")
        return ReportTable(title: overdueOnly ? "Overdue rent" : L("Outstanding rent", "Baaki rent"),
                           subtitle: L("As of ", "Tareekh: ") + Fmt.date(asOf) + (overdueOnly ? L(", after a \(grace)-day grace period", ", \(grace) din ke grace period ke baad") : ""),
                           columns: ["Tenant", "Property", overdueOnly ? "Overdue" : L("Outstanding", "Baaki"), L("Oldest unpaid", "Sabse purana baaki"), L("Days", "Din")],
                           rows: rows, totals: [L("Total", "Kul"), "", Fmt.inr(total), "", ""],
                           note: note.isEmpty ? "" : L("By property:\n", "Property ke hisaab se:\n") + note)
    }

    static func propertyOnly(_ t: Tenant, _ data: AppData) -> String {
        data.properties.first { $0.id == t.propertyID }?.name ?? L("No property", "Koi property nahi")
    }

    private static func tenantLedger(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        guard let id = f.tenantID, let t = data.tenants.first(where: { $0.id == id }) else {
            return ReportTable(title: "Tenant ledger", subtitle: L("Choose a tenant", "Tenant chunein"), columns: [], rows: [])
        }
        struct Entry {
            var date: Date
            var order: Int
            var text: String
            var debit: Int
            var credit: Int
        }
        var entries: [Entry] = []
        for c in Ledger.charges(for: t, horizon: f.to) where c.dueDate <= DateMath.day(f.to) && c.amount > 0 {
            entries.append(Entry(date: c.dueDate, order: 0, text: c.title, debit: c.amount, credit: 0))
        }
        for p in t.payments where !p.isReversed && DateMath.day(p.date) <= DateMath.day(f.to) {
            if p.kind == .payment {
                let ref = p.reference.isEmpty ? "" : " · " + p.reference
                entries.append(Entry(date: DateMath.day(p.date), order: 1, text: "Payment · " + p.method.label + ref, debit: 0, credit: p.amount))
            } else {
                entries.append(Entry(date: DateMath.day(p.date), order: 1, text: L("Refund to tenant", "Tenant ko wapas"), debit: p.amount, credit: 0))
            }
        }
        entries.sort { $0.date != $1.date ? $0.date < $1.date : $0.order < $1.order }
        var balance = 0
        var rows: [[String]] = []
        var broughtForward = 0
        var started = false
        for e in entries {
            balance += e.debit - e.credit
            if DateMath.day(e.date) < DateMath.day(f.from) {
                broughtForward = balance
                continue
            }
            if !started {
                started = true
                if broughtForward != 0 {
                    rows.append([Fmt.date(f.from), L("Balance brought forward", "Pichla balance"), "", "", Fmt.inr(broughtForward)])
                }
            }
            rows.append([Fmt.date(e.date), e.text, e.debit > 0 ? Fmt.inr(e.debit) : "", e.credit > 0 ? Fmt.inr(e.credit) : "", Fmt.inr(balance)])
        }
        return ReportTable(title: "Ledger · " + t.name, subtitle: place(t, data) + " · " + rangeText(f),
                           columns: [L("Date", "Tareekh"), "Details", "Charge", "Paid", "Balance"], rows: rows,
                           totals: ["", L("Closing balance", "Aakhri balance"), "", "", Fmt.inr(balance)],
                           note: L("A positive balance is owed by the tenant; a negative balance is advance credit.", "Plus balance matlab tenant par baaki; minus balance matlab advance credit."))
    }

    // MARK: Payments

    private static func paymentsList(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        var items: [(Tenant, Payment)] = []
        for t in scope(data, f, includeArchived: true) {
            for p in t.payments where !p.isReversed && inRange(p.date, f.from, f.to) {
                items.append((t, p))
            }
        }
        items.sort { Ledger.paymentOrder($0.1, $1.1) }
        var total = 0
        let rows: [[String]] = items.map { item in
            let (t, p) = item
            let signed = p.kind == .payment ? p.amount : -p.amount
            total += signed
            let receipt = p.receiptNumber > 0 ? "#\(p.receiptNumber)" : ""
            let method = p.kind == .refund ? L("Refund", "Wapas") : p.method.label
            return [Fmt.date(p.date), receipt, t.name, method, p.reference, Fmt.inr(signed)]
        }
        return ReportTable(title: "Payments", subtitle: rangeText(f),
                           columns: [L("Date", "Tareekh"), L("Receipt", "Raseed"), "Tenant", L("Method", "Tarika"), "Reference", "Amount"], rows: rows,
                           totals: ["", "", "", "", L("Total", "Kul"), Fmt.inr(total)])
    }

    private static func paymentMethods(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        var amounts: [PaymentMethod: Int] = [:]
        var counts: [PaymentMethod: Int] = [:]
        for t in scope(data, f, includeArchived: true) {
            for p in t.payments where !p.isReversed && p.kind == .payment && inRange(p.date, f.from, f.to) {
                amounts[p.method, default: 0] += p.amount
                counts[p.method, default: 0] += 1
            }
        }
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var total = 0
        for (i, method) in PaymentMethod.allCases.enumerated() {
            let amount = amounts[method, default: 0]
            guard amount > 0 else { continue }
            total += amount
            rows.append([method.label, "\(counts[method, default: 0])", Fmt.inr(amount)])
            chart.append(ChartPoint(label: method.label, series: "Amount", value: amount, order: i))
        }
        return ReportTable(title: L("Payment methods", "Payment ke tarike"), subtitle: rangeText(f),
                           columns: [L("Method", "Tarika"), "Payments", "Amount"], rows: rows,
                           totals: [L("Total", "Kul"), "", Fmt.inr(total)], chart: chart)
    }

    // MARK: Income and expenses

    private static func propertyIncome(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var tc = 0
        var tx = 0
        var targets: [(UUID?, String)] = data.properties
            .filter { f.propertyID == nil || $0.id == f.propertyID }
            .map { (Optional($0.id), $0.name) }
        if f.propertyID == nil {
            targets.append((nil, L("No property", "Koi property nahi")))
        }
        for (i, target) in targets.enumerated() {
            let collected = data.tenants
                .filter { $0.propertyID == target.0 }
                .reduce(0) { $0 + Portfolio.netCollected($1, from: f.from, to: f.to) }
            let spent = data.expenses
                .filter { !$0.isArchived && $0.propertyID == target.0 && inRange($0.date, f.from, f.to) }
                .reduce(0) { $0 + $1.amount }
            if target.0 == nil && collected == 0 && spent == 0 { continue }
            tc += collected
            tx += spent
            rows.append([target.1, Fmt.inr(collected), Fmt.inr(spent), Fmt.inr(collected - spent)])
            chart.append(ChartPoint(label: target.1, series: "Net income", value: collected - spent, order: i))
        }
        return ReportTable(title: L("Property income", "Property ki income"), subtitle: rangeText(f),
                           columns: ["Property", L("Collected", "Mila"), L("Expenses", "Kharche"), "Net income"], rows: rows,
                           totals: [L("Total", "Kul"), Fmt.inr(tc), Fmt.inr(tx), Fmt.inr(tc - tx)], chart: chart)
    }

    private static func expenses(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        let list = scopedExpenses(data, f).sorted { $0.date < $1.date }
        var byCategory: [ExpenseCategory: Int] = [:]
        var total = 0
        var unpaid = 0
        let rows: [[String]] = list.map { e in
            total += e.amount
            if !e.isPaid { unpaid += e.amount }
            byCategory[e.category, default: 0] += e.amount
            let property = data.properties.first { $0.id == e.propertyID }?.name ?? "—"
            return [Fmt.date(e.date), property, e.category.label, e.vendor, Fmt.inr(e.amount), e.isPaid ? "Paid" : L("Unpaid", "Baaki")]
        }
        var chart: [ChartPoint] = []
        for (i, category) in ExpenseCategory.allCases.enumerated() {
            let amount = byCategory[category, default: 0]
            if amount > 0 {
                chart.append(ChartPoint(label: category.label, series: L("Spent", "Kharch"), value: amount, order: i))
            }
        }
        let note = unpaid > 0 ? L("Unpaid bills: ", "Baaki bills: ") + Fmt.inr(unpaid) : ""
        return ReportTable(title: L("Expenses", "Kharche"), subtitle: rangeText(f),
                           columns: [L("Date", "Tareekh"), "Property", "Category", "Vendor", "Amount", "Status"], rows: rows,
                           totals: ["", "", "", L("Total", "Kul"), Fmt.inr(total), ""], chart: chart, note: note)
    }

    private static func netIncome(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        let tenants = scope(data, f, includeArchived: true)
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var tc = 0
        var tx = 0
        for (i, month) in months(f).enumerated() {
            let end = DateMath.monthEnd(month)
            let collected = tenants.reduce(0) { $0 + Portfolio.netCollected($1, from: month, to: end) }
            let spent = data.expenses
                .filter { !$0.isArchived && (f.propertyID == nil || $0.propertyID == f.propertyID) && inRange($0.date, month, end) }
                .reduce(0) { $0 + $1.amount }
            tc += collected
            tx += spent
            let label = Fmt.month(month)
            rows.append([label, Fmt.inr(collected), Fmt.inr(spent), Fmt.inr(collected - spent)])
            chart.append(ChartPoint(label: label, series: "Net income", value: collected - spent, order: i))
        }
        return ReportTable(title: L("Net rental income", "Net rent income"), subtitle: rangeText(f),
                           columns: [L("Month", "Mahina"), L("Collected", "Mila"), L("Expenses", "Kharche"), "Net"], rows: rows,
                           totals: [L("Total", "Kul"), Fmt.inr(tc), Fmt.inr(tx), Fmt.inr(tc - tx)], chart: chart)
    }

    // MARK: Credit, deposits, increases, agreements

    private static func advanceCredit(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        var rows: [[String]] = []
        var total = 0
        for t in scope(data, f, includeArchived: false).sorted(by: { $0.name < $1.name }) {
            let ledger = Ledger.ledger(for: t, asOf: asOf, graceDays: data.settings.gracePeriodDays)
            guard ledger.credit > 0 else { continue }
            total += ledger.credit
            rows.append([t.name, place(t, data), Fmt.inr(ledger.advanceCredit), Fmt.inr(ledger.prepaid), Fmt.inr(ledger.credit)])
        }
        return ReportTable(title: L("Advance and credit", "Advance aur credit"), subtitle: L("As of ", "Tareekh: ") + Fmt.date(asOf),
                           columns: ["Tenant", "Property", L("Unused credit", "Bacha credit"), L("Paid ahead", "Pehle diya"), L("Total", "Kul")], rows: rows,
                           totals: [L("Total", "Kul"), "", "", "", Fmt.inr(total)])
    }

    private static func deposits(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        var rows: [[String]] = []
        var total = DepositSummary()
        for t in scope(data, f, includeArchived: false).sorted(by: { $0.name < $1.name }) where !t.deposits.isEmpty {
            let d = Ledger.deposit(of: t)
            total.received += d.received
            total.additional += d.additional
            total.deducted += d.deducted
            total.refunded += d.refunded
            rows.append([t.name, Fmt.inr(d.totalIn), Fmt.inr(d.deducted), Fmt.inr(d.refunded), Fmt.inr(d.held)])
        }
        return ReportTable(title: L("Security deposits", "Security deposit"), subtitle: L("Kept separate from rent income", "Rent income se alag rakha"),
                           columns: ["Tenant", L("Received", "Mila"), L("Deducted", "Kata"), L("Refunded", "Wapas diya"), L("Held", "Jama")], rows: rows,
                           totals: [L("Total", "Kul"), Fmt.inr(total.totalIn), Fmt.inr(total.deducted), Fmt.inr(total.refunded), Fmt.inr(total.held)])
    }

    private static func increaseHistory(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        struct Item {
            var date: Date
            var row: [String]
        }
        var items: [Item] = []
        for t in scope(data, f, includeArchived: true) {
            let history = t.rentHistory.sorted { $0.effectiveDate < $1.effectiveDate }
            for (i, change) in history.enumerated() where i > 0 && inRange(change.effectiveDate, f.from, f.to) {
                let before = history[i - 1].amount
                let text = Fmt.inr(before) + " → " + Fmt.inr(change.amount)
                items.append(Item(date: change.effectiveDate, row: [Fmt.date(change.effectiveDate), t.name, text, change.reason]))
            }
            for e in t.escalationEvents where e.kind != .applied {
                let when = e.scheduledDate ?? e.recordedAt
                guard inRange(when, f.from, f.to) else { continue }
                items.append(Item(date: when, row: [Fmt.date(when), t.name, e.kind.label, e.note]))
            }
        }
        items.sort { $0.date < $1.date }
        return ReportTable(title: L("Rent increase history", "Rent badhotri history"), subtitle: rangeText(f),
                           columns: [L("Date", "Tareekh"), "Tenant", L("Change", "Badlav"), L("Reason", "Kaaran")], rows: items.map { $0.row })
    }

    private static func agreementExpiry(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        struct Item {
            var end: Date
            var row: [String]
        }
        var items: [Item] = []
        for t in scope(data, f, includeArchived: false) {
            for a in t.agreements {
                let status = Agreements.status(a, asOf: asOf)
                let endText = a.endDate.map { Fmt.date($0) } ?? "—"
                let days = a.endDate.map { "\(DateMath.daysBetween(asOf, $0))" } ?? ""
                items.append(Item(end: a.endDate ?? .distantFuture, row: [t.name, a.title, endText, status.label, days]))
            }
        }
        items.sort { $0.end < $1.end }
        return ReportTable(title: L("Agreement expiry", "Agreement khatam hone ki tareekh"), subtitle: L("As of ", "Tareekh: ") + Fmt.date(asOf),
                           columns: ["Tenant", "Agreement", L("Ends", "Khatam"), "Status", L("Days left", "Din baaki")], rows: items.map { $0.row })
    }

    // MARK: Summaries, partnership, repairs, utilities

    /// The first day of the Indian financial-year quarter containing a day (April, July, October, January).
    static func quarterStart(_ d: Date) -> Date {
        let fy = DateMath.financialYearStart(d)
        let months = rbCalendar.dateComponents([.month], from: fy, to: DateMath.monthStart(d)).month ?? 0
        return DateMath.addMonths((months / 3) * 3, to: fy)
    }

    static func quarterLabel(_ start: Date) -> String {
        let fy = DateMath.financialYearStart(start)
        let months = rbCalendar.dateComponents([.month], from: fy, to: start).month ?? 0
        let year = rbCalendar.component(.year, from: fy)
        return "Q\(months / 3 + 1) FY \(year)-" + String(String(year + 1).suffix(2))
    }

    struct Period {
        var label: String
        var start: Date
        var end: Date
    }

    static func periods(_ f: ReportFilter) -> [Period] {
        var list: [Period] = []
        let last = DateMath.day(f.to)
        switch f.grouping {
        case .month:
            for m in months(f) {
                list.append(Period(label: Fmt.month(m), start: m, end: DateMath.monthEnd(m)))
            }
        case .quarter:
            var q = quarterStart(f.from)
            while q <= last && list.count < 80 {
                list.append(Period(label: quarterLabel(q), start: q, end: DateMath.addDays(-1, to: DateMath.addMonths(3, to: q))))
                q = DateMath.addMonths(3, to: q)
            }
        case .financialYear:
            var y = DateMath.financialYearStart(f.from)
            while y <= last && list.count < 50 {
                let year = rbCalendar.component(.year, from: y)
                list.append(Period(label: "FY \(year)-" + String(String(year + 1).suffix(2)), start: y,
                                   end: DateMath.addDays(-1, to: DateMath.addMonths(12, to: y))))
                y = DateMath.addMonths(12, to: y)
            }
        }
        return list
    }

    private static func periodSummary(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        let tenants = scope(data, f, includeArchived: true)
        let settings = data.partnership.settings
        let withPartner = settings.enabled
        var rows: [[String]] = []
        var chart: [ChartPoint] = []
        var tc = 0
        var tx = 0
        var tp = 0
        for (i, period) in periods(f).enumerated() {
            let collected = tenants.reduce(0) { $0 + Portfolio.netCollected($1, from: period.start, to: period.end) }
            let spent = data.expenses
                .filter { !$0.isArchived && (f.propertyID == nil || $0.propertyID == f.propertyID) && inRange($0.date, period.start, period.end) }
                .reduce(0) { $0 + $1.amount }
            tc += collected
            tx += spent
            var row = [period.label, Fmt.inr(collected), Fmt.inr(spent), Fmt.inr(collected - spent)]
            if withPartner {
                let partnerRent = data.partnership.entries
                    .filter { $0.kind == .rent && !$0.isVoided }
                    .filter { entry in
                        let key = Partnership.monthKey(of: entry)
                        guard let d = Partnership.monthDate(key) else { return false }
                        return d >= period.start && d <= period.end
                    }
                    .reduce(0) { $0 + $1.amount }
                tp += partnerRent
                row.append(Fmt.inr(partnerRent))
            }
            rows.append(row)
            chart.append(ChartPoint(label: period.label, series: L("Collected", "Mila"), value: collected, order: i))
            chart.append(ChartPoint(label: period.label, series: L("Expenses", "Kharche"), value: spent, order: i))
        }
        var columns = [L("Period", "Samay"), L("Rent collected", "Mila rent"), L("Expenses", "Kharche"), "Net"]
        var totals = [L("Total", "Kul"), Fmt.inr(tc), Fmt.inr(tx), Fmt.inr(tc - tx)]
        if withPartner {
            columns.append("Partnership rent")
            totals.append(Fmt.inr(tp))
        }
        return ReportTable(title: L("Income and expense summary", "Income aur kharcha summary"), subtitle: rangeText(f) + " · " + f.grouping.label,
                           columns: columns, rows: rows, totals: totals, chart: chart,
                           note: L("Rent collected is money received from RentBook tenants, less refunds.", "Mila rent matlab RentBook tenants se mila paisa, refund ghata kar."))
    }

    private static func partnerSettlement(_ data: AppData, _ f: ReportFilter, asOf: Date) -> ReportTable {
        let settings = data.partnership.settings
        let summary = Partnership.summary(data, asOf: asOf)
        let from = DateMath.monthStart(f.from)
        let to = DateMath.day(f.to)
        let months = summary.months.filter { $0.start >= from && $0.start <= to }
        let opening = summary.months.last(where: { $0.start < from })?.closing ?? settings.openingBalance
        var rows: [[String]] = [[L("Opening balance", "Shuru ka balance"), "", "", "", "", "", Fmt.inr(opening)]]
        var mine = 0
        var theirs = 0
        var fromRent = 0
        var fromExpenses = 0
        var paid = 0
        for m in months {
            mine += m.rentMine
            theirs += m.rentPartner
            fromRent += m.rentEffect
            fromExpenses += m.expenseEffect
            paid += m.transferEffect + m.adjustmentEffect
            rows.append([Fmt.month(m.start), Fmt.inr(m.rentMine), Fmt.inr(m.rentPartner), Fmt.inr(m.rentEffect),
                         Fmt.inr(m.expenseEffect), Fmt.inr(m.transferEffect + m.adjustmentEffect), Fmt.inr(m.closing)])
        }
        let closing = months.last?.closing ?? opening
        let me = settings.myName
        let other = settings.partnerName
        let note = L("Due from rent: " + other + "'s share of the rent you collected, less your share of the rent " + other + " collected.\n"
                     + "Expenses: your share of what " + other + " paid, less " + other + "'s share of what you paid.\n"
                     + "Paid: money passed between you, and corrections.\n"
                     + "Balance: positive means you owe " + other + "; negative means " + other + " owes you.\n",
                     "Rent se hisaab: jo rent aapne liya usme " + other + " ka hissa, minus jo rent " + other + " ne liya usme aapka hissa.\n"
                     + "Kharche: " + other + " ke diye kharchon mein aapka hissa, minus aapke diye kharchon mein " + other + " ka hissa.\n"
                     + "Diye: aapas ka len-den aur sudhaar.\n"
                     + "Balance: plus matlab aapko " + other + " ko dena hai; minus matlab " + other + " ko aapko dena hai.\n")
            + L("Now: ", "Abhi: ") + Partnership.balanceText(summary.balance, settings) + "."
        return ReportTable(title: L("Partner settlement", "Partner hisaab"), subtitle: rangeText(f),
                           columns: [L("Month", "Mahina"), "Rent – " + me, "Rent – " + other, L("Due from rent", "Rent se hisaab"), L("Expenses", "Kharche"), "Paid", "Balance"],
                           rows: rows,
                           totals: [L("Total", "Kul"), Fmt.inr(mine), Fmt.inr(theirs), Fmt.inr(fromRent), Fmt.inr(fromExpenses),
                                    Fmt.inr(paid), Fmt.inr(closing)],
                           note: note)
    }

    private static func partnerAllocation(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        let settings = data.partnership.settings
        let list = data.expenses.filter { e in
            !e.isArchived && e.amount > 0 && (f.propertyID == nil || e.propertyID == f.propertyID) && inRange(e.date, f.from, f.to)
        }.sorted { $0.date < $1.date }
        var total = 0
        var mineTotal = 0
        var theirsTotal = 0
        let rows: [[String]] = list.map { e in
            let s = Partnership.shares(of: e, settings: settings)
            total += e.amount
            mineTotal += s.mine
            theirsTotal += s.partner
            let name = e.title.isEmpty ? (e.vendor.isEmpty ? e.category.label : e.vendor) : e.title
            return [Fmt.date(e.date), name, Partnership.name(e.paidBy, settings), Partnership.splitText(e.split, settings: settings),
                    Fmt.inr(e.amount), Fmt.inr(s.mine), Fmt.inr(s.partner)]
        }
        return ReportTable(title: L("Expense sharing", "Kharcha batwara"), subtitle: rangeText(f),
                           columns: [L("Date", "Tareekh"), L("Expense", "Kharcha"), L("Paid by", "Kisne diya"), L("Split", "Batwara"), "Amount", settings.myName, settings.partnerName],
                           rows: rows, totals: [L("Total", "Kul"), "", "", "", Fmt.inr(total), Fmt.inr(mineTotal), Fmt.inr(theirsTotal)])
    }

    private static func repairs(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        let settings = data.partnership.settings
        let list = data.expenses.filter { e in
            !e.isArchived && e.isRepair && (f.propertyID == nil || e.propertyID == f.propertyID)
                && inRange(e.reportedOn ?? e.date, f.from, f.to)
        }.sorted { ($0.reportedOn ?? $0.date) < ($1.reportedOn ?? $1.date) }
        var total = 0
        let rows: [[String]] = list.map { e in
            total += e.amount
            let property = data.properties.first { $0.id == e.propertyID }
            let place = Portfolio.unitName(e.unitID, in: property)
            let where_ = place.isEmpty ? (property?.name ?? "—") : place + ", " + (property?.name ?? "")
            let issue = e.issue.isEmpty ? (e.title.isEmpty ? e.category.label : e.title) : e.issue
            return [Fmt.date(e.reportedOn ?? e.date), where_, issue, e.repairStatus.label, e.vendor, Fmt.inr(e.amount),
                    Partnership.name(e.paidBy, settings)]
        }
        let open = list.filter { $0.repairStatus != .done }.count
        return ReportTable(title: L("Repairs", "Repair"), subtitle: rangeText(f),
                           columns: [L("Reported", "Bataya"), L("Where", "Kahan"), L("Issue", "Kaam"), "Status", L("Done by", "Kisne kiya"), L("Cost", "Kharcha"), L("Paid by", "Kisne diya")], rows: rows,
                           totals: [L("Total", "Kul"), "", "", "", "", Fmt.inr(total), ""],
                           note: open > 0 ? L("Still open: \(open)", "Abhi khule: \(open)") : "")
    }

    private static func utilityUsage(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        struct Item {
            var date: Date
            var row: [String]
        }
        var items: [Item] = []
        var billed = 0
        for t in scope(data, f, includeArchived: true) {
            for kind in MeterKind.allCases {
                for line in Utilities.usage(kind, of: t) where inRange(line.reading.date, f.from, f.to) {
                    billed += line.reading.billedAmount
                    items.append(Item(date: line.reading.date,
                                      row: [Fmt.date(line.reading.date), t.name, kind.label, Fmt.number(line.reading.reading),
                                            line.previous == nil ? "" : Fmt.number(line.units),
                                            line.reading.billedAmount > 0 ? Fmt.inr(line.reading.billedAmount) : ""]))
                }
            }
        }
        items.sort { $0.date < $1.date }
        return ReportTable(title: L("Electricity and water", "Bijli aur paani"), subtitle: rangeText(f),
                           columns: [L("Date", "Tareekh"), "Tenant", "Meter", "Reading", L("Units used", "Kitne unit"), L("Billed", "Bill")], rows: items.map { $0.row },
                           totals: [L("Total", "Kul"), "", "", "", "", Fmt.inr(billed)])
    }

    // MARK: One-tap pack

    /// The main reports for a period, for a single PDF or Excel file.
    static func pack(_ data: AppData, filter: ReportFilter, asOf: Date = Date()) -> [ReportTable] {
        var kinds: [ReportKind] = [.periodSummary, .monthlyCollection, .outstanding, .paymentsList, .expenses]
        if data.partnership.settings.enabled {
            kinds += [.partnerAllocation, .partnerSettlement]
        }
        kinds += [.repairs, .deposits]
        var f = filter
        f.tenantID = nil
        return kinds.map { build($0, data: data, filter: f, asOf: asOf) }
    }
}
