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

enum ReportKind: String, CaseIterable, Identifiable, Hashable {
    case monthlyCollection, annualCollection, expectedVsActual, outstanding, overdue, tenantLedger
    case paymentsList, paymentMethods, propertyIncome, expenses, netIncome
    case advanceCredit, deposits, increaseHistory, agreementExpiry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthlyCollection: return "Monthly collection"
        case .annualCollection: return "Annual collection"
        case .expectedVsActual: return "Expected vs collected"
        case .outstanding: return "Outstanding rent"
        case .overdue: return "Overdue rent"
        case .tenantLedger: return "Tenant ledger"
        case .paymentsList: return "Payments"
        case .paymentMethods: return "Payment methods"
        case .propertyIncome: return "Property income"
        case .expenses: return "Expenses"
        case .netIncome: return "Net rental income"
        case .advanceCredit: return "Advance and credit"
        case .deposits: return "Security deposits"
        case .increaseHistory: return "Rent increase history"
        case .agreementExpiry: return "Agreement expiry"
        }
    }

    var detail: String {
        switch self {
        case .monthlyCollection: return "Expected and collected rent for each month, with a trend chart"
        case .annualCollection: return "Totals for each financial year (April to March)"
        case .expectedVsActual: return "Each tenant's billed rent against what they paid"
        case .outstanding: return "Who owes what today, and since when"
        case .overdue: return "Dues past the grace period"
        case .tenantLedger: return "Every charge and payment for one tenant, with running balance"
        case .paymentsList: return "All payments received in a period"
        case .paymentMethods: return "How rent was paid: UPI, cash, bank and others"
        case .propertyIncome: return "Collection, expenses and net income for each property"
        case .expenses: return "Property expenses by date and category"
        case .netIncome: return "Rent collected minus expenses, month by month"
        case .advanceCredit: return "Money paid ahead of time"
        case .deposits: return "Deposits received, deducted, refunded and held"
        case .increaseHistory: return "Every rent change with reasons"
        case .agreementExpiry: return "Agreement end dates and status"
        }
    }

    var usesDateRange: Bool {
        switch self {
        case .outstanding, .overdue, .advanceCredit, .deposits, .agreementExpiry: return false
        default: return true
        }
    }

    var needsTenant: Bool { self == .tenantLedger }
}

struct ReportFilter: Hashable {
    var from: Date
    var to: Date
    var propertyID: UUID? = nil
    var tenantID: UUID? = nil
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
        Fmt.date(f.from) + " to " + Fmt.date(f.to)
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

    private static let expectedNote = "Expected counts rent and charges due up to today."

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
            chart.append(ChartPoint(label: label, series: "Expected", value: expected, order: i))
            chart.append(ChartPoint(label: label, series: "Collected", value: collected, order: i))
        }
        return ReportTable(title: "Monthly collection", subtitle: rangeText(f),
                           columns: ["Month", "Expected", "Collected", "Difference"], rows: rows,
                           totals: ["Total", Fmt.inr(totalExpected), Fmt.inr(totalCollected), Fmt.inr(totalCollected - totalExpected)],
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
            chart.append(ChartPoint(label: label, series: "Expected", value: expected, order: i))
            chart.append(ChartPoint(label: label, series: "Collected", value: collected, order: i))
            start = DateMath.addMonths(12, to: start)
            i += 1
        }
        return ReportTable(title: "Annual collection", subtitle: "Financial years, April to March",
                           columns: ["Year", "Expected", "Collected", "Difference"], rows: rows, chart: chart,
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
        return ReportTable(title: "Expected vs collected", subtitle: rangeText(f),
                           columns: ["Tenant", "Property", "Expected", "Collected", "Difference"], rows: rows,
                           totals: ["Total", "", Fmt.inr(te), Fmt.inr(tc), Fmt.inr(tc - te)], note: expectedNote)
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
        return ReportTable(title: overdueOnly ? "Overdue rent" : "Outstanding rent",
                           subtitle: "As of " + Fmt.date(asOf) + (overdueOnly ? ", after a \(grace)-day grace period" : ""),
                           columns: ["Tenant", "Property", overdueOnly ? "Overdue" : "Outstanding", "Oldest unpaid", "Days"],
                           rows: rows, totals: ["Total", "", Fmt.inr(total), "", ""],
                           note: note.isEmpty ? "" : "By property:\n" + note)
    }

    static func propertyOnly(_ t: Tenant, _ data: AppData) -> String {
        data.properties.first { $0.id == t.propertyID }?.name ?? "No property"
    }

    private static func tenantLedger(_ data: AppData, _ f: ReportFilter) -> ReportTable {
        guard let id = f.tenantID, let t = data.tenants.first(where: { $0.id == id }) else {
            return ReportTable(title: "Tenant ledger", subtitle: "Choose a tenant", columns: [], rows: [])
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
                entries.append(Entry(date: DateMath.day(p.date), order: 1, text: "Refund to tenant", debit: p.amount, credit: 0))
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
                    rows.append([Fmt.date(f.from), "Balance brought forward", "", "", Fmt.inr(broughtForward)])
                }
            }
            rows.append([Fmt.date(e.date), e.text, e.debit > 0 ? Fmt.inr(e.debit) : "", e.credit > 0 ? Fmt.inr(e.credit) : "", Fmt.inr(balance)])
        }
        return ReportTable(title: "Ledger · " + t.name, subtitle: place(t, data) + " · " + rangeText(f),
                           columns: ["Date", "Details", "Charge", "Paid", "Balance"], rows: rows,
                           totals: ["", "Closing balance", "", "", Fmt.inr(balance)],
                           note: "A positive balance is owed by the tenant; a negative balance is advance credit.")
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
            let method = p.kind == .refund ? "Refund" : p.method.label
            return [Fmt.date(p.date), receipt, t.name, method, p.reference, Fmt.inr(signed)]
        }
        return ReportTable(title: "Payments", subtitle: rangeText(f),
                           columns: ["Date", "Receipt", "Tenant", "Method", "Reference", "Amount"], rows: rows,
                           totals: ["", "", "", "", "Total", Fmt.inr(total)])
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
        return ReportTable(title: "Payment methods", subtitle: rangeText(f),
                           columns: ["Method", "Payments", "Amount"], rows: rows,
                           totals: ["Total", "", Fmt.inr(total)], chart: chart)
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
            targets.append((nil, "No property"))
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
        return ReportTable(title: "Property income", subtitle: rangeText(f),
                           columns: ["Property", "Collected", "Expenses", "Net income"], rows: rows,
                           totals: ["Total", Fmt.inr(tc), Fmt.inr(tx), Fmt.inr(tc - tx)], chart: chart)
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
            return [Fmt.date(e.date), property, e.category.label, e.vendor, Fmt.inr(e.amount), e.isPaid ? "Paid" : "Unpaid"]
        }
        var chart: [ChartPoint] = []
        for (i, category) in ExpenseCategory.allCases.enumerated() {
            let amount = byCategory[category, default: 0]
            if amount > 0 {
                chart.append(ChartPoint(label: category.label, series: "Spent", value: amount, order: i))
            }
        }
        let note = unpaid > 0 ? "Unpaid bills: " + Fmt.inr(unpaid) : ""
        return ReportTable(title: "Expenses", subtitle: rangeText(f),
                           columns: ["Date", "Property", "Category", "Vendor", "Amount", "Status"], rows: rows,
                           totals: ["", "", "", "Total", Fmt.inr(total), ""], chart: chart, note: note)
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
        return ReportTable(title: "Net rental income", subtitle: rangeText(f),
                           columns: ["Month", "Collected", "Expenses", "Net"], rows: rows,
                           totals: ["Total", Fmt.inr(tc), Fmt.inr(tx), Fmt.inr(tc - tx)], chart: chart)
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
        return ReportTable(title: "Advance and credit", subtitle: "As of " + Fmt.date(asOf),
                           columns: ["Tenant", "Property", "Unused credit", "Paid ahead", "Total"], rows: rows,
                           totals: ["Total", "", "", "", Fmt.inr(total)])
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
        return ReportTable(title: "Security deposits", subtitle: "Kept separate from rent income",
                           columns: ["Tenant", "Received", "Deducted", "Refunded", "Held"], rows: rows,
                           totals: ["Total", Fmt.inr(total.totalIn), Fmt.inr(total.deducted), Fmt.inr(total.refunded), Fmt.inr(total.held)])
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
        return ReportTable(title: "Rent increase history", subtitle: rangeText(f),
                           columns: ["Date", "Tenant", "Change", "Reason"], rows: items.map { $0.row })
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
        return ReportTable(title: "Agreement expiry", subtitle: "As of " + Fmt.date(asOf),
                           columns: ["Tenant", "Agreement", "Ends", "Status", "Days left"], rows: items.map { $0.row })
    }
}
