//  ReportViews.swift
//  The Reports tab: report list, each report with filters, chart, table,
//  and export to PDF or CSV.

import SwiftUI
import Charts

enum RangePreset: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3Months, last6Months, last12Months, thisYear, lastYear, allTime, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .last3Months: return "Last 3 months"
        case .last6Months: return "Last 6 months"
        case .last12Months: return "Last 12 months"
        case .thisYear: return "This financial year"
        case .lastYear: return "Last financial year"
        case .allTime: return "All time"
        case .custom: return "Choose dates"
        }
    }

    /// Start and end days, or nil for custom dates.
    func range(asOf: Date, earliest: Date) -> (from: Date, to: Date)? {
        let today = DateMath.day(asOf)
        let month = DateMath.monthStart(today)
        switch self {
        case .thisMonth:
            return (month, DateMath.monthEnd(today))
        case .lastMonth:
            let start = DateMath.addMonths(-1, to: month)
            return (start, DateMath.monthEnd(start))
        case .last3Months:
            return (DateMath.addMonths(-2, to: month), DateMath.monthEnd(today))
        case .last6Months:
            return (DateMath.addMonths(-5, to: month), DateMath.monthEnd(today))
        case .last12Months:
            return (DateMath.addMonths(-11, to: month), DateMath.monthEnd(today))
        case .thisYear:
            let start = DateMath.financialYearStart(today)
            return (start, DateMath.addDays(-1, to: DateMath.addMonths(12, to: start)))
        case .lastYear:
            let start = DateMath.addMonths(-12, to: DateMath.financialYearStart(today))
            return (start, DateMath.addDays(-1, to: DateMath.addMonths(12, to: start)))
        case .allTime:
            return (min(DateMath.day(earliest), month), DateMath.monthEnd(today))
        case .custom:
            return nil
        }
    }
}

struct ReportsHomeView: View {
    @EnvironmentObject var store: Store

    private let rentReports: [ReportKind] = [.monthlyCollection, .annualCollection, .expectedVsActual, .outstanding,
                                             .overdue, .tenantLedger, .paymentsList, .paymentMethods, .advanceCredit]
    private let incomeReports: [ReportKind] = [.propertyIncome, .netIncome, .expenses]
    private let otherReports: [ReportKind] = [.deposits, .increaseHistory, .agreementExpiry]

    var body: some View {
        let snap = store.snapshot
        List {
            Section("This month") {
                TileGrid {
                    StatTile(title: "Rent expected", value: Fmt.inr(snap.expectedThisMonth))
                    StatTile(title: "Collected", value: Fmt.inr(snap.collectedThisMonth), tint: .green)
                    StatTile(title: "Outstanding", value: Fmt.inr(snap.outstanding), tint: snap.outstanding > 0 ? .orange : .primary)
                    StatTile(title: "Overdue", value: Fmt.inr(snap.overdue), tint: snap.overdue > 0 ? .red : .primary)
                }
            }
            Section {
                NavigationLink(value: Route.expenses(nil)) {
                    Label("Expenses and bills", systemImage: "wrench.and.screwdriver")
                }
            }
            reportSection("Rent", rentReports)
            reportSection("Income and expenses", incomeReports)
            reportSection("Deposits, increases and agreements", otherReports)
        }
        .navigationTitle("Reports")
    }

    private func reportSection(_ title: String, _ kinds: [ReportKind]) -> some View {
        Section(title) {
            ForEach(kinds) { kind in
                NavigationLink(value: Route.report(kind)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TotalPair: Identifiable {
    let id: Int
    let label: String
    let value: String
}

struct ReportView: View {
    @EnvironmentObject var store: Store
    let kind: ReportKind

    @State private var preset: RangePreset
    @State private var from: Date
    @State private var to: Date
    @State private var propertyID: UUID? = nil
    @State private var tenantID: UUID? = nil
    @State private var share: ShareItem? = nil
    @State private var prepared = false

    init(kind: ReportKind) {
        self.kind = kind
        let start: RangePreset
        switch kind {
        case .monthlyCollection, .netIncome: start = .last12Months
        case .annualCollection, .tenantLedger, .increaseHistory: start = .allTime
        default: start = .thisYear
        }
        let today = DateMath.day(Date())
        _preset = State(initialValue: start)
        _from = State(initialValue: DateMath.monthStart(today))
        _to = State(initialValue: today)
    }

    private var showsProperty: Bool { kind != .tenantLedger }

    private var showsTenant: Bool {
        switch kind {
        case .tenantLedger, .paymentsList, .expectedVsActual, .increaseHistory, .monthlyCollection: return true
        default: return false
        }
    }

    private var earliest: Date {
        var dates: [Date] = []
        for t in store.data.tenants {
            if let s = t.billingStartDate ?? t.startDate { dates.append(s) }
            if let first = t.payments.map({ $0.date }).min() { dates.append(first) }
        }
        if let first = store.data.expenses.map({ $0.date }).min() { dates.append(first) }
        return dates.min() ?? DateMath.addMonths(-11, to: Date())
    }

    private var dates: (from: Date, to: Date) {
        if let r = preset.range(asOf: Date(), earliest: earliest) { return r }
        let a = DateMath.day(from)
        let b = DateMath.day(to)
        return a <= b ? (a, b) : (b, a)
    }

    private var filter: ReportFilter {
        let r = dates
        return ReportFilter(from: r.from, to: r.to, propertyID: showsProperty ? propertyID : nil,
                            tenantID: showsTenant ? tenantID : nil)
    }

    private var tenantChoices: [Tenant] {
        store.data.tenants.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var propertyChoices: [RentalProperty] {
        store.data.properties.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var tenantPlaceholder: String { kind.needsTenant ? "Choose a tenant" : "All tenants" }

    var body: some View {
        let table = Reports.build(kind, data: store.data, filter: filter)
        List {
            filtersSection
            if !table.chart.isEmpty && !table.rows.isEmpty {
                Section {
                    ReportChart(points: table.chart)
                        .frame(height: 220)
                        .padding(.vertical, 6)
                }
            }
            totalsSection(table)
            rowsSection(table)
            if !table.note.isEmpty {
                Section {
                    Text(table.note)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Share as PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        exportCSV()
                    } label: {
                        Label("Share as spreadsheet (CSV)", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            if !prepared {
                prepared = true
                if kind.needsTenant && tenantID == nil {
                    tenantID = store.liveTenants.first?.id ?? tenantChoices.first?.id
                }
            }
        }
    }

    private var filtersSection: some View {
        Section {
            if kind.usesDateRange {
                Picker("Period", selection: $preset) {
                    ForEach(RangePreset.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                if preset == .custom {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                } else {
                    LabeledContent("Dates", value: Fmt.date(dates.from) + " – " + Fmt.date(dates.to))
                }
            }
            if showsProperty {
                Picker("Property", selection: $propertyID) {
                    Text("All properties").tag(Optional<UUID>.none)
                    ForEach(propertyChoices) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            if showsTenant {
                Picker("Tenant", selection: $tenantID) {
                    Text(tenantPlaceholder).tag(Optional<UUID>.none)
                    ForEach(tenantChoices) { t in
                        Text(t.isArchived ? t.name + " (archived)" : t.name).tag(Optional(t.id))
                    }
                }
            }
        } footer: {
            Text(kind.detail)
        }
    }

    @ViewBuilder
    private func totalsSection(_ table: ReportTable) -> some View {
        let pairs = totalPairs(table)
        if !pairs.isEmpty {
            Section("Totals") {
                ForEach(pairs) { pair in
                    LabeledContent(pair.label, value: pair.value)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func totalPairs(_ table: ReportTable) -> [TotalPair] {
        guard let totals = table.totals else { return [] }
        var out: [TotalPair] = []
        for (i, cell) in totals.enumerated() where i < table.columns.count {
            if cell.hasPrefix("₹") || cell.hasPrefix("-₹") {
                out.append(TotalPair(id: i, label: table.columns[i], value: cell))
            }
        }
        return out
    }

    private func rowsSection(_ table: ReportTable) -> some View {
        Section {
            if table.rows.isEmpty {
                Text(kind.needsTenant && tenantID == nil ? "Choose a tenant above." : "Nothing to show for these choices.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { item in
                ReportRowView(columns: table.columns, cells: item.element)
            }
        } header: {
            Text(table.subtitle)
        }
    }

    private func fileName(_ table: ReportTable) -> String {
        let safe = table.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return safe + " " + DateMath.dayKey(Date())
    }

    private func exportPDF() {
        let table = Reports.build(kind, data: store.data, filter: filter)
        if let url = PDFMaker.report(table, landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportCSV() {
        let table = Reports.build(kind, data: store.data, filter: filter)
        // The byte-order mark helps Excel read the file as UTF-8.
        if let url = store.writeTemporary("\u{FEFF}" + table.csv, named: fileName(table) + ".csv") {
            share = ShareItem(url: url)
        }
    }
}

struct ReportChart: View {
    let points: [ChartPoint]

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Period", p.label), y: .value("Amount", p.value))
                .foregroundStyle(by: .value("Series", p.series))
                .position(by: .value("Series", p.series))
        }
    }
}

/// One table row shown as a small card: the first column as the title,
/// then each other column with its heading.
struct ReportRowView: View {
    let columns: [String]
    let cells: [String]

    private var count: Int { min(columns.count, cells.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cells.first ?? "")
                .font(.subheadline.weight(.semibold))
            ForEach(1..<max(1, count), id: \.self) { i in
                if !cells[i].isEmpty {
                    HStack(alignment: .top) {
                        Text(columns[i])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(cells[i])
                            .font(.caption.weight(.medium))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
