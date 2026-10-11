//  ReportViews.swift
//  The Accounts tab (expenses, repairs, recurring expenses, worksheets, the hisaab
//  with your partner, reports and tax), each report with filters, chart and table,
//  and export to PDF, Excel or CSV.

import SwiftUI
import Charts

enum RangePreset: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, thisQuarter, lastQuarter, last3Months, last6Months, last12Months, thisYear, lastYear, allTime, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth: return L("This month", "Is mahine")
        case .lastMonth: return L("Last month", "Pichhla mahina")
        case .thisQuarter: return L("This quarter", "Is quarter")
        case .lastQuarter: return L("Last quarter", "Pichhla quarter")
        case .last3Months: return L("Last 3 months", "Pichhle 3 mahine")
        case .last6Months: return L("Last 6 months", "Pichhle 6 mahine")
        case .last12Months: return L("Last 12 months", "Pichhle 12 mahine")
        case .thisYear: return L("This financial year", "Is financial year")
        case .lastYear: return L("Last financial year", "Pichhla financial year")
        case .allTime: return L("All time", "Shuru se ab tak")
        case .custom: return L("Choose dates", "Tareekh chunein")
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
        case .thisQuarter:
            let start = Reports.quarterStart(today)
            return (start, DateMath.addDays(-1, to: DateMath.addMonths(3, to: start)))
        case .lastQuarter:
            let start = DateMath.addMonths(-3, to: Reports.quarterStart(today))
            return (start, DateMath.addDays(-1, to: DateMath.addMonths(3, to: start)))
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

/// The earliest day anything was recorded, for "All time".
func earliestRecord(_ data: AppData) -> Date {
    var dates: [Date] = []
    for t in data.tenants {
        if let s = t.billingStartDate ?? t.startDate { dates.append(s) }
        if let first = t.payments.map({ $0.date }).min() { dates.append(first) }
    }
    if let first = data.expenses.map({ $0.date }).min() { dates.append(first) }
    if let first = data.partnership.entries.map({ $0.date }).min() { dates.append(first) }
    return dates.min() ?? DateMath.addMonths(-11, to: Date())
}

// MARK: - Accounts tab

struct AccountsHomeView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let snap = store.snapshot
        let settings = store.partnerSettings
        List {
            Section {
                NavigationLink(value: Route.partnership) {
                    if settings.enabled, let balance = snap.partnerBalance {
                        HStack {
                            Label(L("Hisaab with ", "Hisaab: ") + settings.partnerName, systemImage: "person.2")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.inr(abs(balance)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(partnerBalanceColor(balance))
                                Text(balance > 0 ? L("you owe", "aapko dena") : (balance < 0 ? L("owed to you", "aapko lena") : L("settled", "barabar")))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(L("Hisaab with your brother", "Bhai ke saath hisaab"), systemImage: "person.2")
                            Text(L("Shared rent, expenses and who owes whom", "Shared rent, kharche aur kisko kitna dena"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink(value: Route.expenses(nil)) {
                    Label(L("Expenses and bills", "Kharche aur bills"), systemImage: "cart")
                }
                NavigationLink(value: Route.repairs) {
                    HStack {
                        Label(L("Repairs", "Repairs"), systemImage: "wrench.and.screwdriver")
                        Spacer()
                        if snap.openRepairs > 0 {
                            TagLabel(text: L("\(snap.openRepairs) open", "\(snap.openRepairs) khule"), color: .orange)
                        }
                    }
                }
                NavigationLink(value: Route.recurring) {
                    HStack {
                        Label(L("Recurring expenses", "Recurring kharche"), systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if snap.pendingRecurring > 0 {
                            TagLabel(text: L("\(snap.pendingRecurring) to review", "\(snap.pendingRecurring) review"), color: .orange)
                        }
                    }
                }
            } header: {
                Text(L("Partnership", "Partnership"))
            } footer: {
                if settings.enabled {
                    Text(L("Expenses, repairs and recurring expenses count in the hisaab from its start month, shared as set on each one.",
                           "Kharche, repair aur recurring kharche hisaab shuru hone ke mahine se gine jaate hain, har ek par set batwara ke hisaab se."))
                }
            }
            Section {
                NavigationLink(value: Route.rentSheets) {
                    Label(L("Rent records worksheets", "Rent records worksheet"), systemImage: "tablecells")
                }
            } header: {
                Text(L("Money", "Paisa"))
            }
            Section {
                NavigationLink(value: Route.oneTap) {
                    Label(L("One-tap reports (PDF and Excel)", "Ek tap reports (PDF aur Excel)"), systemImage: "bolt.horizontal.circle")
                }
                NavigationLink(value: Route.reports) {
                    Label(L("All reports", "Saari reports"), systemImage: "chart.bar.xaxis")
                }
                NavigationLink(value: Route.tax) {
                    Label(L("Tax summary", "Tax summary"), systemImage: "building.columns")
                }
            } header: {
                Text(L("Reports", "Reports"))
            }
            Section(L("This month", "Is mahine")) {
                TileGrid {
                    StatTile(title: L("Rent expected", "Aane wala rent"), value: Fmt.inr(snap.expectedThisMonth))
                    StatTile(title: L("Collected", "Mila"), value: Fmt.inr(snap.collectedThisMonth), tint: .green)
                    StatTile(title: L("Outstanding", "Baaki"), value: Fmt.inr(snap.outstanding), tint: snap.outstanding > 0 ? .orange : .primary)
                    StatTile(title: L("Overdue", "Overdue"), value: Fmt.inr(snap.overdue), tint: snap.overdue > 0 ? .red : .primary)
                }
            }
        }
        .navigationTitle(L("Accounts", "Hisaab"))
    }
}

struct ReportsListView: View {
    @EnvironmentObject var store: Store

    private let rentReports: [ReportKind] = [.monthlyCollection, .annualCollection, .expectedVsActual, .outstanding,
                                             .overdue, .tenantLedger, .paymentsList, .paymentMethods, .advanceCredit]
    private let incomeReports: [ReportKind] = [.periodSummary, .propertyIncome, .netIncome, .expenses, .repairs, .utilityUsage]
    private let partnerReports: [ReportKind] = [.partnerSettlement, .partnerAllocation]
    private let otherReports: [ReportKind] = [.deposits, .increaseHistory, .agreementExpiry]

    var body: some View {
        List {
            reportSection(L("Rent", "Rent"), rentReports)
            reportSection(L("Income and expenses", "Income aur kharche"), incomeReports)
            if store.partnerSettings.enabled {
                reportSection(L("Partnership", "Partnership"), partnerReports)
            }
            reportSection(L("Deposits, increases and agreements", "Deposit, badhotri aur agreements"), otherReports)
        }
        .navigationTitle(L("Reports", "Reports"))
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

// MARK: - One-tap reports

struct OneTapReportsView: View {
    @EnvironmentObject var store: Store
    @State private var preset: RangePreset = .thisYear
    @State private var from = DateMath.monthStart(Date())
    @State private var to = DateMath.day(Date())
    @State private var grouping: SummaryGrouping = .month
    @State private var propertyID: UUID? = nil
    @State private var share: ShareItem? = nil

    private var presets: [RangePreset] {
        [.thisMonth, .lastMonth, .thisQuarter, .lastQuarter, .thisYear, .lastYear, .allTime, .custom]
    }

    private var dates: (from: Date, to: Date) {
        if let r = preset.range(asOf: Date(), earliest: earliestRecord(store.data)) { return r }
        let a = DateMath.day(from)
        let b = DateMath.day(to)
        return a <= b ? (a, b) : (b, a)
    }

    private var filter: ReportFilter {
        let r = dates
        return ReportFilter(from: r.from, to: r.to, propertyID: propertyID, tenantID: nil, grouping: grouping)
    }

    private var title: String {
        L("RentBook reports", "RentBook reports") + " · " + Fmt.date(dates.from) + " – " + Fmt.date(dates.to)
    }

    var body: some View {
        let tables = Reports.pack(store.data, filter: filter)
        List {
            Section {
                Picker(L("Period", "Samay"), selection: $preset) {
                    ForEach(presets) { p in
                        Text(p.label).tag(p)
                    }
                }
                if preset == .custom {
                    DatePicker(L("From", "Se"), selection: $from, displayedComponents: .date)
                    DatePicker(L("To", "Tak"), selection: $to, displayedComponents: .date)
                } else {
                    LabeledContent(L("Dates", "Tareekh"), value: Fmt.date(dates.from) + " – " + Fmt.date(dates.to))
                }
                Picker(L("Summary by", "Summary"), selection: $grouping) {
                    ForEach(SummaryGrouping.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                Picker(L("Property", "Property"), selection: $propertyID) {
                    Text(L("All properties", "Saari properties")).tag(Optional<UUID>.none)
                    ForEach(store.activeProperties) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            Section {
                Button {
                    if let url = PDFMaker.reports(tables, title: L("RentBook reports", "RentBook reports"),
                                                  subtitle: Fmt.date(dates.from) + " – " + Fmt.date(dates.to),
                                                  landlord: store.settings.landlordName) {
                        share = ShareItem(url: url)
                    }
                } label: {
                    Label(L("One PDF with every report", "Saari reports ek PDF mein"), systemImage: "doc.richtext")
                }
                Button {
                    let name = L("RentBook reports ", "RentBook reports ") + DateMath.dayKey(dates.from) + " to " + DateMath.dayKey(dates.to)
                    if let url = store.excelFile(tables, named: name) {
                        share = ShareItem(url: url)
                    }
                } label: {
                    Label(L("One Excel file, a sheet for each report", "Ek Excel file, har report ki alag sheet"), systemImage: "tablecells")
                }
            } footer: {
                Text(L("Included: ", "Shaamil: ") + tables.map { $0.title }.joined(separator: ", ") + ".")
            }
        }
        .navigationTitle(L("One-tap reports", "Ek tap reports"))
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
    }
}

// MARK: - One report

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
    @State private var grouping: SummaryGrouping = .month
    @State private var share: ShareItem? = nil
    @State private var prepared = false

    init(kind: ReportKind) {
        self.kind = kind
        let start: RangePreset
        switch kind {
        case .monthlyCollection, .netIncome: start = .last12Months
        case .annualCollection, .tenantLedger, .increaseHistory, .partnerSettlement: start = .allTime
        default: start = .thisYear
        }
        let today = DateMath.day(Date())
        _preset = State(initialValue: start)
        _from = State(initialValue: DateMath.monthStart(today))
        _to = State(initialValue: today)
    }

    private var showsProperty: Bool {
        switch kind {
        case .tenantLedger, .partnerSettlement: return false
        default: return true
        }
    }

    private var showsTenant: Bool {
        switch kind {
        case .tenantLedger, .paymentsList, .expectedVsActual, .increaseHistory, .monthlyCollection, .utilityUsage: return true
        default: return false
        }
    }

    private var dates: (from: Date, to: Date) {
        if let r = preset.range(asOf: Date(), earliest: earliestRecord(store.data)) { return r }
        let a = DateMath.day(from)
        let b = DateMath.day(to)
        return a <= b ? (a, b) : (b, a)
    }

    private var filter: ReportFilter {
        let r = dates
        return ReportFilter(from: r.from, to: r.to, propertyID: showsProperty ? propertyID : nil,
                            tenantID: showsTenant ? tenantID : nil, grouping: grouping)
    }

    private var tenantChoices: [Tenant] {
        store.data.tenants.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var propertyChoices: [RentalProperty] {
        store.data.properties.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var tenantPlaceholder: String { kind.needsTenant ? L("Choose a tenant", "Tenant chunein") : L("All tenants", "Saare tenants") }

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
                        Label(L("Share as PDF", "PDF share karein"), systemImage: "doc.richtext")
                    }
                    Button {
                        exportExcel()
                    } label: {
                        Label(L("Share as Excel", "Excel share karein"), systemImage: "tablecells")
                    }
                    Button {
                        exportCSV()
                    } label: {
                        Label(L("Share as CSV", "CSV share karein"), systemImage: "doc.plaintext")
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
                Picker(L("Period", "Samay"), selection: $preset) {
                    ForEach(RangePreset.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                if preset == .custom {
                    DatePicker(L("From", "Se"), selection: $from, displayedComponents: .date)
                    DatePicker(L("To", "Tak"), selection: $to, displayedComponents: .date)
                } else {
                    LabeledContent(L("Dates", "Tareekh"), value: Fmt.date(dates.from) + " – " + Fmt.date(dates.to))
                }
            }
            if kind.usesGrouping {
                Picker(L("Group by", "Kis hisaab se"), selection: $grouping) {
                    ForEach(SummaryGrouping.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
            }
            if showsProperty {
                Picker(L("Property", "Property"), selection: $propertyID) {
                    Text(L("All properties", "Saari properties")).tag(Optional<UUID>.none)
                    ForEach(propertyChoices) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            if showsTenant {
                Picker(L("Tenant", "Tenant"), selection: $tenantID) {
                    Text(tenantPlaceholder).tag(Optional<UUID>.none)
                    ForEach(tenantChoices) { t in
                        Text(t.isArchived ? t.name + L(" (archived)", " (archive)") : t.name).tag(Optional(t.id))
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
            Section(L("Totals", "Kul")) {
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
                Text(kind.needsTenant && tenantID == nil ? L("Choose a tenant above.", "Upar tenant chunein.")
                     : L("Nothing to show for these choices.", "In choices ke liye kuch nahi."))
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
        PDFMaker.safeName(table.title) + " " + DateMath.dayKey(Date())
    }

    private func exportPDF() {
        let table = Reports.build(kind, data: store.data, filter: filter)
        if let url = PDFMaker.report(table, landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportExcel() {
        let table = Reports.build(kind, data: store.data, filter: filter)
        if let url = store.excelFile([table], named: fileName(table)) {
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
