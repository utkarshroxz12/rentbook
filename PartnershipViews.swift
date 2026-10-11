//  PartnershipViews.swift
//  The hisaab with your brother (or any partner): rent each of you collects from your
//  own fixed tenants, shared and personal expenses, money passed between you, and the
//  balance month by month. Kept apart from your RentBook tenants.

import SwiftUI

enum PartnerSheet: Identifiable {
    case settings
    case rent(String)
    case entry(PartnerEntryKind)
    case pay(Partner, Int)
    case correct(UUID)
    case expense
    case message(String)
    case source(UUID?)
    case rule(UUID?)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .rent(let month): return "rent-" + month
        case .entry(let kind): return "entry-" + kind.rawValue
        case .pay(let who, let amount): return "pay-" + who.rawValue + "-\(amount)"
        case .correct(let id): return "correct-" + id.uuidString
        case .expense: return "expense"
        case .message(let month): return "message-" + month
        case .source(let id): return "source-" + (id?.uuidString ?? "new")
        case .rule(let id): return "rule-" + (id?.uuidString ?? "new")
        }
    }
}

/// The forms the partnership screens open, in one place.
struct PartnerSheetView: View {
    @EnvironmentObject var store: Store
    let sheet: PartnerSheet

    var body: some View {
        switch sheet {
        case .settings:
            PartnershipSettingsView()
        case .rent(let month):
            PrepareRentView(monthKey: month)
        case .entry(let kind):
            PartnerEntryFormView(kind: kind)
        case .pay(let who, let amount):
            PartnerEntryFormView(kind: .transfer, presetParty: who, presetAmount: amount)
        case .correct(let id):
            if let entry = store.partnerEntry(id) {
                PartnerEntryFormView(kind: entry.kind, correcting: entry)
            } else {
                Text(L("This entry was removed.", "Yeh entry hata di gayi."))
            }
        case .expense:
            ExpenseFormView(expense: nil)
        case .message(let month):
            PartnerMessageView(monthKey: month)
        case .source(let id):
            PartnerSourceFormView(source: store.partnerSource(id))
        case .rule(let id):
            RuleFormView(rule: store.partnership.rules.first { $0.id == id })
        }
    }
}

func partnerBalanceColor(_ balance: Int) -> Color {
    balance > 0 ? .orange : (balance < 0 ? .green : .primary)
}

// MARK: - Home

struct PartnershipHomeView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: PartnerSheet? = nil
    @State private var share: ShareItem? = nil
    @State private var showAllMonths = false

    var body: some View {
        let settings = store.partnerSettings
        List {
            if settings.enabled {
                let summary = Partnership.summary(store.data)
                balanceSection(summary, settings)
                thisMonthSection(summary, settings)
                actionsSection(settings)
                monthsSection(summary, settings)
                moreSection(settings)
            } else {
                introSection
            }
        }
        .navigationTitle(L("Hisaab with ", "Hisaab: ") + settings.partnerName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if settings.enabled {
                    Menu {
                        Button {
                            sheet = .message(DateMath.monthKey(Date()))
                        } label: {
                            Label(L("Send this month's hisaab", "Is mahine ka hisaab bhejein"), systemImage: "paperplane")
                        }
                        Button {
                            exportPDF()
                        } label: {
                            Label(L("Full statement (PDF)", "Poora statement (PDF)"), systemImage: "doc.richtext")
                        }
                        Button {
                            exportExcel()
                        } label: {
                            Label(L("Full statement (Excel)", "Poora statement (Excel)"), systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $sheet) { which in
            PartnerSheetView(sheet: which).environmentObject(store)
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Share the rent business with your brother", "Bhai ke saath rent ka hisaab"))
                    .font(.headline)
                Text(L("List the fixed tenants each of you collects rent from, record the rent each month, and add the expenses each of you pays. RentBook works out each share and shows who owes whom, month by month. Your tenants in RentBook are not changed.",
                       "Dono ke fixed tenants likhein jinse aap rent lete hain, har mahine ka rent record karein, aur jo kharche koi bhi de woh jodein. RentBook har ek ka hissa nikal kar batata hai kisko kitna dena hai, mahine dar mahine. Aapke RentBook tenants par koi asar nahi."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                sheet = .settings
            } label: {
                Label(L("Set up the hisaab", "Hisaab shuru karein"), systemImage: "person.2.badge.gearshape")
            }
        }
    }

    private func balanceSection(_ summary: PartnerSummary, _ settings: PartnershipSettings) -> some View {
        let balance = summary.balance
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Balance today", "Aaj ka balance"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(abs(balance)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(partnerBalanceColor(balance))
                Text(Partnership.balanceText(balance, settings))
                    .font(.headline)
            }
            .padding(.vertical, 4)
            if balance > 0 {
                Button {
                    sheet = .pay(.me, balance)
                } label: {
                    Label(L("Record money paid to ", "Record karein: ") + settings.partnerName + L("", " ko diye"), systemImage: "arrow.up.right.circle")
                }
            } else if balance < 0 {
                Button {
                    sheet = .pay(.partner, -balance)
                } label: {
                    Label(L("Record money received from ", "Record karein: ") + settings.partnerName + L("", " se mile"), systemImage: "arrow.down.left.circle")
                }
            }
        } footer: {
            Text(L("Rent you hold beyond your share, less expenses you paid for ", "Aapke hisse se zyada jo rent aapke paas hai, minus jo kharche aapne ")
                 + settings.partnerName + L(", is owed to them. A minus balance means they took more than their share.",
                                            " ke liye diye, woh unka hai. Minus balance matlab unhone apne hisse se zyada liya."))
        }
    }

    @ViewBuilder
    private func thisMonthSection(_ summary: PartnerSummary, _ settings: PartnershipSettings) -> some View {
        let key = DateMath.monthKey(Date())
        let pending = Partnership.pendingRent(store.partnership, month: key)
        if let m = summary.months.first(where: { $0.key == key }) {
            let s = Partnership.statement(m)
            Section {
                NavigationLink(value: Route.partnerMonth(key)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Fmt.month(m.start))
                                .font(.headline)
                            Spacer()
                            Text(L("Details", "Poora dekhein"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        monthLine(L("Rent collected by ", "Rent liya: ") + settings.myName, s.rentByMe)
                        monthLine(L("Rent collected by ", "Rent liya: ") + settings.partnerName, s.rentByPartner)
                        monthLine(L("Expenses", "Kharche"), s.totalExpenses)
                        monthLine(L("Due for the month", "Is mahine ka hisaab"), s.dueForMonth, bold: true)
                    }
                    .padding(.vertical, 2)
                }
                if !pending.isEmpty {
                    Button {
                        sheet = .rent(key)
                    } label: {
                        Label(L("Record this month's rent (\(pending.count) left)", "Is mahine ka rent record karein (\(pending.count) baaki)"),
                              systemImage: "indianrupeesign.circle")
                    }
                }
            } header: {
                Text(L("This month", "Is mahine"))
            }
        }
    }

    private func monthLine(_ title: String, _ value: Int, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text(Fmt.inr(value))
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
        }
    }

    private func actionsSection(_ settings: PartnershipSettings) -> some View {
        Section {
            Button {
                sheet = .rent(DateMath.monthKey(Date()))
            } label: {
                Label(L("Record rent", "Rent record karein"), systemImage: "indianrupeesign.circle")
            }
            Button {
                sheet = .expense
            } label: {
                Label(L("Add an expense", "Kharcha jodein"), systemImage: "cart.badge.plus")
            }
            Button {
                sheet = .entry(.transfer)
            } label: {
                Label(L("Money paid to or received from ", "Len-den: ") + settings.partnerName, systemImage: "arrow.left.arrow.right")
            }
            Button {
                sheet = .entry(.adjustment)
            } label: {
                Label(L("Correct the balance", "Balance theek karein"), systemImage: "plusminus.circle")
            }
        }
    }

    private func monthsSection(_ summary: PartnerSummary, _ settings: PartnershipSettings) -> some View {
        let months = Array(summary.months.reversed())
        let shown = showAllMonths ? months : Array(months.prefix(12))
        return Section {
            if months.isEmpty {
                Text(L("No months yet. Record rent or an expense to start.", "Abhi koi mahina nahi. Rent ya kharcha record karke shuru karein."))
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { m in
                NavigationLink(value: Route.partnerMonth(m.key)) {
                    PartnerMonthRow(month: m, settings: settings)
                }
            }
            if months.count > 12 {
                Button(showAllMonths ? L("Show fewer", "Kam dikhayein") : L("Show all \(months.count) months", "Saare \(months.count) mahine dikhayein")) {
                    showAllMonths.toggle()
                }
            }
        } header: {
            Text(L("Month by month", "Mahine dar mahine"))
        }
    }

    private func moreSection(_ settings: PartnershipSettings) -> some View {
        let active = store.partnership.sources.filter { $0.isActive }.count
        return Section {
            NavigationLink(value: Route.partnerSources) {
                LabeledContent(L("Fixed tenants", "Fixed tenants"), value: "\(active)")
            }
            NavigationLink(value: Route.partnerRules) {
                LabeledContent(L("Sharing rules", "Batwara rules"), value: "\(store.partnership.rules.count)")
            }
            NavigationLink(value: Route.partnerHistory) {
                Label(L("Full history", "Poori history"), systemImage: "clock.arrow.circlepath")
            }
            NavigationLink(value: Route.report(.partnerSettlement)) {
                Label(L("Settlement report", "Hisaab report"), systemImage: "doc.text")
            }
            NavigationLink(value: Route.report(.partnerAllocation)) {
                Label(L("Expense sharing report", "Kharcha batwara report"), systemImage: "chart.pie")
            }
            Button {
                sheet = .settings
            } label: {
                Label(L("Hisaab settings", "Hisaab settings"), systemImage: "gearshape")
            }
        } footer: {
            Text(settingsSummary(settings))
        }
    }

    private func settingsSummary(_ s: PartnershipSettings) -> String {
        var text = s.myName + " " + Fmt.percent(s.myShare) + " · " + s.partnerName + " " + Fmt.percent(100 - s.myShare)
        if let start = s.startDate {
            text += L(" · from ", " · shuru ") + Fmt.month(start)
        }
        if s.openingBalance != 0 {
            text += L(" · opening balance ", " · pichla balance ") + Fmt.inr(s.openingBalance)
        }
        return text
    }

    private var allTimeFilter: ReportFilter {
        let summary = Partnership.summary(store.data)
        let first = summary.months.first?.start ?? DateMath.monthStart(Date())
        return ReportFilter(from: first, to: DateMath.monthEnd(Date()))
    }

    private func exportPDF() {
        let table = Reports.build(.partnerSettlement, data: store.data, filter: allTimeFilter)
        if let url = PDFMaker.report(table, landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportExcel() {
        let settlement = Reports.build(.partnerSettlement, data: store.data, filter: allTimeFilter)
        let sharing = Reports.build(.partnerAllocation, data: store.data, filter: allTimeFilter)
        var sheets = [Excel.sheet(settlement, name: L("Settlement", "Hisaab")), Excel.sheet(sharing, name: L("Expense sharing", "Kharcha batwara"))]
        for m in Partnership.summary(store.data).months.reversed().prefix(24) {
            sheets.append(Excel.sheet(Partnership.statementTable(m, data: store.data), name: Fmt.month(m.start)))
        }
        let name = L("Hisaab with ", "Hisaab ") + store.partnerSettings.partnerName + " " + DateMath.dayKey(Date())
        if let url = store.excelFile(sheets: sheets, named: name) {
            share = ShareItem(url: url)
        }
    }
}

struct PartnerMonthRow: View {
    let month: PartnerMonth
    let settings: PartnershipSettings

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.month(month.start))
                Text(concat(L("Rent ", "Rent "), Fmt.inr(month.totalRent), L(" · expenses ", " · kharche "), Fmt.inr(month.expensesTotal)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.inr(month.closing))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(partnerBalanceColor(month.closing))
                Text(L("balance", "balance"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - One month

struct PartnerMonthView: View {
    @EnvironmentObject var store: Store
    let monthKey: String

    @State private var sheet: PartnerSheet? = nil
    @State private var share: ShareItem? = nil
    @State private var chosenEntry: PartnerEntry? = nil
    @State private var voiding: PartnerEntry? = nil
    @State private var voidReason = ""

    var body: some View {
        let settings = store.partnerSettings
        let summary = Partnership.summary(store.data)
        List {
            if let m = summary.months.first(where: { $0.key == monthKey }) {
                rentSection(m, settings)
                expensesSection(m, settings)
                moneySection(m, settings)
                workingSection(m, settings)
            } else {
                Section {
                    Text(L("Nothing recorded for this month, or it is before the hisaab starts.",
                           "Is mahine ka kuch record nahi, ya yeh hisaab shuru hone se pehle ka hai."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Partnership.monthLabel(monthKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sheet = .message(monthKey)
                    } label: {
                        Label(L("Send to ", "Bhejein: ") + settings.partnerName, systemImage: "paperplane")
                    }
                    Button {
                        exportPDF()
                    } label: {
                        Label(L("Statement (PDF)", "Statement (PDF)"), systemImage: "doc.richtext")
                    }
                    Button {
                        exportExcel()
                    } label: {
                        Label(L("Statement (Excel)", "Statement (Excel)"), systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sheet) { which in
            PartnerSheetView(sheet: which).environmentObject(store)
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog(entryTitle, isPresented: entryBinding, titleVisibility: .visible) {
            if let e = chosenEntry {
                Button(L("Correct this entry", "Yeh entry theek karein")) {
                    sheet = .correct(e.id)
                }
                Button(L("Void this entry", "Yeh entry radd karein"), role: .destructive) {
                    voidReason = ""
                    voiding = e
                }
            }
        } message: {
            Text(L("A corrected or voided entry stays in the history, crossed out.", "Theek ki gayi ya radd entry history mein kati hui dikhti hai."))
        }
        .alert(L("Void this entry?", "Yeh entry radd karein?"), isPresented: voidBinding) {
            TextField(L("Reason", "Kaaran"), text: $voidReason)
            Button(L("Void", "Radd karein"), role: .destructive) {
                if let e = voiding {
                    store.voidPartnerEntry(e.id, reason: voidReason)
                }
                voiding = nil
            }
            Button(L("Cancel", "Cancel"), role: .cancel) { voiding = nil }
        } message: {
            Text(L("It will no longer count in the balance.", "Yeh balance mein nahi gini jayegi."))
        }
    }

    private var entryTitle: String {
        guard let e = chosenEntry else { return "" }
        return store.entryText(e)
    }

    private var entryBinding: Binding<Bool> {
        Binding(get: { chosenEntry != nil }, set: { if !$0 { chosenEntry = nil } })
    }

    private var voidBinding: Binding<Bool> {
        Binding(get: { voiding != nil }, set: { if !$0 { voiding = nil } })
    }

    private func rentSection(_ m: PartnerMonth, _ settings: PartnershipSettings) -> some View {
        let pending = Partnership.pendingRent(store.partnership, month: monthKey)
        return Section {
            ForEach(m.rent) { line in
                Button {
                    chosenEntry = line.entry
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.sourceName)
                            Text(concat(L("collected by ", "liya: "), Partnership.name(line.entry.party, settings), " · ", Fmt.date(line.entry.date)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.inr(line.entry.amount))
                            .font(.subheadline.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !pending.isEmpty {
                Button {
                    sheet = .rent(monthKey)
                } label: {
                    Label(L("Not recorded yet: ", "Abhi record nahi: ") + pending.map { $0.name }.joined(separator: ", "),
                          systemImage: "plus.circle")
                }
            }
        } header: {
            Text(L("Rent collected · ", "Rent liya · ") + Fmt.inr(m.totalRent))
        }
    }

    private func expensesSection(_ m: PartnerMonth, _ settings: PartnershipSettings) -> some View {
        Section {
            if m.expenses.isEmpty {
                Text(L("No shared expenses.", "Koi shared kharcha nahi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(m.expenses) { line in
                NavigationLink(value: Route.expense(line.expense.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExpensePlace.name(line.expense))
                            Text(concat(L("paid by ", "diya: "), Partnership.name(line.expense.paidBy, settings), " · ",
                                        Partnership.splitText(line.expense.split, settings: settings), " · ", settings.partnerName, " ",
                                        Fmt.inr(line.partnerShare)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.inr(line.expense.amount))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            Button {
                sheet = .expense
            } label: {
                Label(L("Add an expense", "Kharcha jodein"), systemImage: "plus.circle")
            }
        } header: {
            Text(L("Expenses · ", "Kharche · ") + Fmt.inr(m.expensesTotal))
        }
    }

    @ViewBuilder
    private func moneySection(_ m: PartnerMonth, _ settings: PartnershipSettings) -> some View {
        let entries = (m.transfers + m.adjustments).sorted { $0.date < $1.date }
        if !entries.isEmpty {
            Section(L("Money passed and corrections", "Len-den aur sudhaar")) {
                ForEach(entries) { e in
                    Button {
                        chosenEntry = e
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.entryText(e))
                                    .lineLimit(2)
                                if !e.note.isEmpty {
                                    Text(e.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.inr(Partnership.effect(of: e)))
                                .font(.subheadline.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workingSection(_ m: PartnerMonth, _ settings: PartnershipSettings) -> some View {
        let s = Partnership.statement(m)
        let other = settings.partnerName
        let percent = Partnership.partnerPercentText(settings)
        return Section {
            Group {
                LabeledContent(L("Total rent", "Kul rent"), value: Fmt.inr(s.totalRent))
                LabeledContent(L(other + "'s share (" + percent + ")", other + " ka hissa (" + percent + ")"), value: Fmt.inr(s.partnerRentShare))
                LabeledContent(L("Less " + other + "'s share of expenses", "Minus " + other + " ka kharchon mein hissa"), value: Fmt.inr(-s.partnerExpenseShare))
                LabeledContent(L(other + "'s share for the month", "Is mahine " + other + " ka hissa"), value: Fmt.inr(s.partnerShare))
                LabeledContent(L("Already with " + other, other + " ke paas pehle se"), value: Fmt.inr(s.partnerHolds))
                LabeledContent(L("Due for the month", "Is mahine ka hisaab"), value: Fmt.inr(s.dueForMonth))
                    .font(.subheadline.weight(.semibold))
            }
            LabeledContent(L("Balance brought forward", "Pichla balance"), value: Fmt.inr(s.opening))
            if s.paidToPartner > 0 {
                LabeledContent(L("Paid to ", "Diye: ") + other, value: Fmt.inr(-s.paidToPartner))
            }
            if s.receivedFromPartner > 0 {
                LabeledContent(L("Received from ", "Mile: ") + other, value: Fmt.inr(s.receivedFromPartner))
            }
            if s.corrections != 0 {
                LabeledContent(L("Corrections", "Sudhaar"), value: Fmt.inr(s.corrections))
            }
            LabeledContent(L("Balance at month end", "Mahine ke ant mein balance"), value: Fmt.inr(s.closing))
                .font(.headline)
        } header: {
            Text(L("Working out", "Hisaab kaise bana"))
        } footer: {
            Text(Partnership.balanceText(s.closing, settings))
        }
    }

    private func month() -> PartnerMonth? {
        Partnership.summary(store.data).months.first { $0.key == monthKey }
    }

    private func exportPDF() {
        guard let m = month() else { return }
        if let url = PDFMaker.report(Partnership.statementTable(m, data: store.data), landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportExcel() {
        guard let m = month() else { return }
        let table = Partnership.statementTable(m, data: store.data)
        if let url = store.excelFile([table], named: table.title) {
            share = ShareItem(url: url)
        }
    }
}

// MARK: - Month picker

/// Months from three years back to three months ahead, newest first.
struct MonthPicker: View {
    let title: String
    @Binding var monthKey: String

    private var keys: [String] {
        let now = DateMath.monthStart(Date())
        var list = (-3...36).map { DateMath.monthKey(DateMath.addMonths(-$0, to: now)) }
        if !list.contains(monthKey), Partnership.monthDate(monthKey) != nil {
            list.append(monthKey)
        }
        return list
    }

    var body: some View {
        Picker(title, selection: $monthKey) {
            ForEach(keys, id: \.self) { key in
                Text(Partnership.monthLabel(key)).tag(key)
            }
        }
    }
}

// MARK: - Recording rent for a month

struct PrepareRentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var monthKey: String
    @State private var rows: [RentLine] = []
    @State private var prepared = false

    struct RentLine: Identifiable {
        var source: PartnerSource
        var include = true
        var amountText: String
        var date: Date
        var id: UUID { source.id }
    }

    init(monthKey: String) {
        _monthKey = State(initialValue: monthKey)
    }

    private var total: Int {
        rows.filter { $0.include }.reduce(0) { $0 + (parseAmount($1.amountText) ?? 0) }
    }

    var body: some View {
        let settings = store.partnerSettings
        NavigationStack {
            Form {
                Section {
                    MonthPicker(title: L("Month", "Mahina"), monthKey: $monthKey)
                } footer: {
                    if let start = settings.startDate, let month = Partnership.monthDate(monthKey), month < DateMath.monthStart(start) {
                        Text(L("This month is before the hisaab starts (", "Yeh mahina hisaab shuru hone se pehle ka hai (") + Fmt.month(start)
                             + L("), so it will not count.", "), isliye gina nahi jayega."))
                            .foregroundStyle(.orange)
                    }
                }
                if rows.isEmpty {
                    Section {
                        Text(store.partnership.sources.isEmpty
                             ? L("Add your fixed tenants first, with who collects each rent.", "Pehle fixed tenants jodein, aur kaun kiska rent leta hai.")
                             : L("Rent for every fixed tenant is already recorded for this month.", "Is mahine sab fixed tenants ka rent record ho chuka hai."))
                            .foregroundStyle(.secondary)
                        Button {
                            addOther()
                        } label: {
                            Label(L("Add other rent", "Doosra rent jodein"), systemImage: "plus")
                        }
                    }
                }
                ForEach($rows) { row in
                    RentLineEditor(row: row, settings: settings)
                }
                if !rows.isEmpty {
                    Section {
                        LabeledContent(L("Total", "Kul"), value: Fmt.inr(total))
                        Button {
                            addOther()
                        } label: {
                            Label(L("Add other rent", "Doosra rent jodein"), systemImage: "plus")
                        }
                    } footer: {
                        Text(L("Change an amount if less or more was collected. Leave a tenant switched off if their rent has not come yet.",
                               "Kam ya zyada mila ho to amount badlein. Jiska rent abhi nahi aaya use off rehne dein."))
                    }
                }
            }
            .navigationTitle(L("Record rent", "Rent record karein"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(total <= 0)
                }
            }
            .keyboardDoneButton()
            .onAppear {
                if !prepared {
                    prepared = true
                    rebuild()
                }
            }
            .onChange(of: monthKey) { _ in
                rebuild()
            }
        }
    }

    private var defaultDate: Date {
        guard let month = Partnership.monthDate(monthKey) else { return DateMath.day(Date()) }
        let today = DateMath.day(Date())
        if DateMath.monthStart(today) == month { return today }
        return DateMath.dayOfMonth(5, in: month)
    }

    private func rebuild() {
        let pending = Partnership.pendingRent(store.partnership, month: monthKey)
        let others = rows.filter { $0.source.name.isEmpty }
        rows = pending.map { RentLine(source: $0, amountText: amountString($0.monthlyRent), date: defaultDate) } + others
    }

    private func addOther() {
        var source = PartnerSource()
        source.id = UUID()
        rows.append(RentLine(source: source, amountText: "", date: defaultDate))
    }

    private func save() {
        var entries: [PartnerEntry] = []
        for row in rows where row.include {
            guard let amount = parseAmount(row.amountText), amount > 0 else { continue }
            var e = PartnerEntry()
            e.kind = .rent
            e.month = monthKey
            e.date = DateMath.day(row.date)
            e.amount = amount
            e.party = row.source.collectedBy
            if row.source.name.isEmpty {
                let from = row.source.place.trimmingCharacters(in: .whitespacesAndNewlines)
                e.title = from.isEmpty ? L("Other rent", "Doosra rent") : from
            } else {
                e.sourceID = row.source.id
                e.title = row.source.name
            }
            entries.append(e)
        }
        store.addPartnerEntries(entries)
        dismiss()
    }
}

/// One fixed tenant's rent while recording a month.
struct RentLineEditor: View {
    @Binding var row: PrepareRentView.RentLine
    let settings: PartnershipSettings

    var body: some View {
        Section {
            Toggle(isOn: $row.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.source.name.isEmpty ? L("Other rent", "Doosra rent") : row.source.name)
                    Text(L("collected by ", "liya: ") + Partnership.name(row.source.collectedBy, settings))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if row.include {
                if row.source.name.isEmpty {
                    Picker(L("Collected by", "Kisne liya"), selection: $row.source.collectedBy) {
                        Text(settings.myName).tag(Partner.me)
                        Text(settings.partnerName).tag(Partner.partner)
                    }
                    TextField(L("From whom", "Kisse"), text: $row.source.place)
                }
                MoneyField(title: L("Amount", "Amount"), text: $row.amountText)
                DatePicker(L("Received on", "Kab mila"), selection: $row.date, displayedComponents: .date)
            }
        }
    }
}

// MARK: - Payments, corrections and fixing entries

struct PartnerEntryFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let kind: PartnerEntryKind
    let correcting: PartnerEntry?

    @State private var party: Partner
    @State private var amountText: String
    @State private var date: Date
    @State private var monthKey: String
    @State private var sourceID: UUID?
    @State private var title: String
    @State private var method: PaymentMethod
    @State private var note: String
    @State private var reason = ""

    init(kind: PartnerEntryKind, correcting: PartnerEntry? = nil, presetParty: Partner? = nil, presetAmount: Int? = nil) {
        self.kind = kind
        self.correcting = correcting
        let e = correcting ?? PartnerEntry()
        _party = State(initialValue: presetParty ?? e.party)
        _amountText = State(initialValue: amountString(presetAmount ?? e.amount))
        _date = State(initialValue: correcting == nil ? DateMath.day(Date()) : e.date)
        _monthKey = State(initialValue: correcting.map { Partnership.monthKey(of: $0) } ?? DateMath.monthKey(Date()))
        _sourceID = State(initialValue: e.sourceID)
        _title = State(initialValue: e.title)
        _method = State(initialValue: e.method ?? .upi)
        _note = State(initialValue: e.note)
    }

    private var amount: Int { parseAmount(amountText) ?? 0 }

    private var canSave: Bool {
        amount > 0 && (kind != .adjustment || !note.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var screenTitle: String {
        if correcting != nil { return L("Correct entry", "Entry theek karein") }
        switch kind {
        case .rent: return L("Rent", "Rent")
        case .transfer: return L("Money passed", "Len-den")
        case .adjustment: return L("Balance correction", "Balance sudhaar")
        }
    }

    var body: some View {
        let settings = store.partnerSettings
        NavigationStack {
            Form {
                switch kind {
                case .rent: rentFields(settings)
                case .transfer: transferFields(settings)
                case .adjustment: adjustmentFields(settings)
                }
                if correcting != nil {
                    Section {
                        TextField(L("Why it is being corrected", "Kyun theek kar rahe hain"), text: $reason)
                    } footer: {
                        Text(L("The original entry stays in the history, crossed out, and this one replaces it.",
                               "Purani entry history mein kati hui rahegi, aur yeh uski jagah legi."))
                    }
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(!canSave)
                }
            }
            .keyboardDoneButton()
        }
    }

    @ViewBuilder
    private func rentFields(_ settings: PartnershipSettings) -> some View {
        Section {
            Picker(L("Tenant", "Tenant"), selection: $sourceID) {
                Text(L("Other", "Doosra")).tag(Optional<UUID>.none)
                ForEach(store.partnership.sources) { s in
                    Text(s.name).tag(Optional(s.id))
                }
            }
            if sourceID == nil {
                TextField(L("From whom", "Kisse"), text: $title)
            }
            Picker(L("Collected by", "Kisne liya"), selection: $party) {
                Text(settings.myName).tag(Partner.me)
                Text(settings.partnerName).tag(Partner.partner)
            }
            MonthPicker(title: L("For the month", "Kis mahine ka"), monthKey: $monthKey)
            MoneyField(title: L("Amount", "Amount"), text: $amountText)
            DatePicker(L("Received on", "Kab mila"), selection: $date, displayedComponents: .date)
            TextField(L("Note", "Note"), text: $note)
        }
        .onChange(of: sourceID) { id in
            if let s = store.partnerSource(id) {
                party = s.collectedBy
                if amount == 0 { amountText = amountString(s.monthlyRent) }
            }
        }
    }

    @ViewBuilder
    private func transferFields(_ settings: PartnershipSettings) -> some View {
        Section {
            Picker(L("Who paid", "Kisne diya"), selection: $party) {
                Text(L("I paid ", "Maine diye: ") + settings.partnerName).tag(Partner.me)
                Text(settings.partnerName + L(" paid me", " ne mujhe diye")).tag(Partner.partner)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            Text(party == .me
                 ? L("Money you hand over to " + settings.partnerName + ", for their share or as a loan.", settings.partnerName + " ko diye paise, unke hisse ke ya udhaar.")
                 : L("Money " + settings.partnerName + " gives you, or rent of yours they kept.", settings.partnerName + " ne jo paise aapko diye."))
        }
        Section {
            MoneyField(title: L("Amount", "Amount"), text: $amountText)
            DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
            Picker(L("How", "Kaise"), selection: $method) {
                ForEach(PaymentMethod.selectable) { m in
                    Text(m.label).tag(m)
                }
            }
            TextField(L("Note", "Note"), text: $note)
        }
    }

    @ViewBuilder
    private func adjustmentFields(_ settings: PartnershipSettings) -> some View {
        Section {
            Picker(L("Correction", "Sudhaar"), selection: $party) {
                Text(L("Lower what I owe ", "Mera dena kam karein: ") + settings.partnerName).tag(Partner.me)
                Text(L("Raise what I owe ", "Mera dena badhayein: ") + settings.partnerName).tag(Partner.partner)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            Text(L("Use a correction for anything agreed between you that is not rent, an expense or money passed.",
                   "Jo baat aapas mein tay hui ho aur rent, kharcha ya len-den na ho, uske liye sudhaar use karein."))
        }
        Section {
            MoneyField(title: L("Amount", "Amount"), text: $amountText)
            DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
            TextField(L("Reason (needed)", "Kaaran (zaroori)"), text: $note)
        }
    }

    private func save() {
        var e = PartnerEntry()
        e.kind = kind
        e.amount = amount
        e.party = party
        e.date = DateMath.day(date)
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .rent:
            e.month = monthKey
            e.sourceID = sourceID
            if let s = store.partnerSource(sourceID) {
                e.title = s.name
            } else {
                let from = title.trimmingCharacters(in: .whitespacesAndNewlines)
                e.title = from.isEmpty ? L("Other rent", "Doosra rent") : from
            }
        case .transfer:
            e.month = DateMath.monthKey(e.date)
            e.method = method
        case .adjustment:
            e.month = DateMath.monthKey(e.date)
        }
        if let old = correcting {
            store.correctPartnerEntry(old.id, with: e, reason: reason)
        } else {
            store.addPartnerEntries([e])
        }
        dismiss()
    }
}

// MARK: - Fixed tenants

struct PartnerSourcesView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: PartnerSheet? = nil
    @State private var askImport = false
    @State private var removing: PartnerSource? = nil

    var body: some View {
        let settings = store.partnerSettings
        let sources = store.partnership.sources
        let active = sources.filter { $0.isActive }
        let stopped = sources.filter { !$0.isActive }
        List {
            Section {
                TileGrid {
                    StatTile(title: L("Collected by ", "Leta hai: ") + settings.myName,
                             value: Fmt.inr(active.filter { $0.collectedBy == .me }.reduce(0) { $0 + $1.monthlyRent }))
                    StatTile(title: L("Collected by ", "Leta hai: ") + settings.partnerName,
                             value: Fmt.inr(active.filter { $0.collectedBy == .partner }.reduce(0) { $0 + $1.monthlyRent }))
                }
            } footer: {
                Text(L("Monthly rent of the fixed tenants. These are kept apart from your RentBook tenants.",
                       "Fixed tenants ka mahine ka rent. Yeh aapke RentBook tenants se alag hain."))
            }
            sourceSection(L("Collected by ", "Leta hai: ") + settings.myName, active.filter { $0.collectedBy == .me })
            sourceSection(L("Collected by ", "Leta hai: ") + settings.partnerName, active.filter { $0.collectedBy == .partner })
            if !stopped.isEmpty {
                sourceSection(L("Stopped", "Band"), stopped)
            }
            Section {
                Button {
                    sheet = .source(nil)
                } label: {
                    Label(L("Add a fixed tenant", "Fixed tenant jodein"), systemImage: "plus")
                }
                if !store.liveTenants.isEmpty {
                    Button {
                        askImport = true
                    } label: {
                        Label(L("Copy from my RentBook tenants", "Mere RentBook tenants se copy karein"), systemImage: "person.2.badge.plus")
                    }
                }
            }
        }
        .navigationTitle(L("Fixed tenants", "Fixed tenants"))
        .sheet(item: $sheet) { which in
            PartnerSheetView(sheet: which).environmentObject(store)
        }
        .confirmationDialog(L("Copy your RentBook tenants?", "RentBook tenants copy karein?"), isPresented: $askImport, titleVisibility: .visible) {
            Button(L("Copy as collected by ", "Copy karein, leta hai: ") + settings.myName) { importTenants() }
        } message: {
            Text(L("Each current tenant not already listed is added with today's rent. Their records in RentBook stay as they are.",
                   "Jo tenant yahan nahi hain, unhe aaj ke rent ke saath joda jayega. RentBook mein unke record waise hi rahenge."))
        }
        .confirmationDialog(removeTitle, isPresented: removeBinding, titleVisibility: .visible) {
            if let s = removing {
                if store.sourceHasRecords(s.id) {
                    Button(L("Stop", "Band karein"), role: .destructive) { store.setSourceActive(s.id, false) }
                } else {
                    Button(L("Remove", "Hatayein"), role: .destructive) { store.deleteSource(s.id) }
                }
            }
        } message: {
            if let s = removing, store.sourceHasRecords(s.id) {
                Text(L("Rent recorded for this tenant stays in the hisaab. It will no longer be asked for each month.",
                       "Is tenant ka record kiya rent hisaab mein rahega. Har mahine iska rent nahi poocha jayega."))
            } else {
                Text(L("No rent has been recorded for this tenant.", "Is tenant ka koi rent record nahi hua."))
            }
        }
    }

    private var removeTitle: String {
        guard let s = removing else { return "" }
        return store.sourceHasRecords(s.id) ? L("Stop ", "Band karein: ") + s.name + "?" : L("Remove ", "Hatayein: ") + s.name + "?"
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    @ViewBuilder
    private func sourceSection(_ title: String, _ list: [PartnerSource]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { s in
                    Button {
                        sheet = .source(s.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name)
                                if !s.place.isEmpty {
                                    Text(s.place)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.inr(s.monthlyRent))
                                .font(.subheadline.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if s.isActive {
                            Button {
                                removing = s
                            } label: {
                                Label(L("Stop", "Band"), systemImage: "pause.circle")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                store.setSourceActive(s.id, true)
                            } label: {
                                Label(L("Restart", "Phir shuru"), systemImage: "play.circle")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
    }

    private func importTenants() {
        let existing = Set(store.partnership.sources.map { $0.name.lowercased() })
        for t in store.liveTenants where !existing.contains(t.name.lowercased()) {
            var s = PartnerSource()
            s.name = t.name
            s.place = store.place(of: t)
            s.monthlyRent = Ledger.currentRent(of: t)
            s.collectedBy = .me
            store.saveSource(s, isNew: true)
        }
    }
}

struct PartnerSourceFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: PartnerSource?

    @State private var name: String
    @State private var place: String
    @State private var rentText: String
    @State private var collectedBy: Partner
    @State private var isActive: Bool
    @State private var notes: String

    init(source: PartnerSource?) {
        existing = source
        let s = source ?? PartnerSource()
        _name = State(initialValue: s.name)
        _place = State(initialValue: s.place)
        _rentText = State(initialValue: amountString(s.monthlyRent))
        _collectedBy = State(initialValue: s.collectedBy)
        _isActive = State(initialValue: s.isActive)
        _notes = State(initialValue: s.notes)
    }

    var body: some View {
        let settings = store.partnerSettings
        NavigationStack {
            Form {
                Section {
                    TextField(L("Tenant's name", "Tenant ka naam"), text: $name)
                    TextField(L("Property or shop (optional)", "Property ya dukaan (optional)"), text: $place)
                    MoneyField(title: L("Monthly rent", "Mahine ka rent"), text: $rentText)
                    Picker(L("Rent collected by", "Rent kaun leta hai"), selection: $collectedBy) {
                        Text(settings.myName).tag(Partner.me)
                        Text(settings.partnerName).tag(Partner.partner)
                    }
                }
                Section {
                    Toggle(L("Ask for this rent each month", "Har mahine yeh rent poochein"), isOn: $isActive)
                    TextField(L("Notes", "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text(L("Changing the rent here does not change months already recorded.",
                           "Yahan rent badalne se pehle record kiye mahine nahi badlenge."))
                }
            }
            .navigationTitle(existing == nil ? L("New fixed tenant", "Naya fixed tenant") : L("Fixed tenant", "Fixed tenant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .keyboardDoneButton()
        }
    }

    private func save() {
        var s = existing ?? PartnerSource()
        s.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        s.monthlyRent = parseAmount(rentText) ?? 0
        s.collectedBy = collectedBy
        s.isActive = isActive
        s.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveSource(s, isNew: existing == nil)
        dismiss()
    }
}

// MARK: - Sharing rules

struct AllocationRulesView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: PartnerSheet? = nil
    @State private var deleting: AllocationRule? = nil

    var body: some View {
        let rules = store.partnership.rules
        List {
            Section {
                if rules.isEmpty {
                    Text(L("No rules yet. New expenses are shared ", "Abhi koi rule nahi. Naye kharche ")
                         + Partnership.splitText(ExpenseSplit(), settings: store.partnerSettings) + L(".", " bante hain."))
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { r in
                    Button {
                        sheet = .rule(r.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name.isEmpty ? L("Rule", "Rule") : r.name)
                            Text(store.ruleText(r))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deleting = r
                        } label: {
                            Label(L("Delete", "Delete"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            } footer: {
                Text(L("When you add an expense, the rule that fits its property and category best fills in who pays and how it is shared. You can still change it on the expense.",
                       "Kharcha jodte samay, property aur category se mel khata rule batata hai kaun dega aur kaise batega. Kharche par phir bhi badal sakte hain."))
            }
            Section {
                Button {
                    sheet = .rule(nil)
                } label: {
                    Label(L("Add a rule", "Rule jodein"), systemImage: "plus")
                }
            }
        }
        .navigationTitle(L("Sharing rules", "Batwara rules"))
        .sheet(item: $sheet) { which in
            PartnerSheetView(sheet: which).environmentObject(store)
        }
        .confirmationDialog(L("Delete this rule?", "Yeh rule delete karein?"), isPresented: deleteBinding, titleVisibility: .visible) {
            Button(L("Delete rule", "Rule delete karein"), role: .destructive) {
                if let r = deleting { store.deleteRule(r.id) }
                deleting = nil
            }
        } message: {
            Text(L("Expenses already saved keep their sharing.", "Pehle se save kharchon ka batwara nahi badlega."))
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

struct RuleFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: AllocationRule?

    @State private var name: String
    @State private var propertyID: UUID?
    @State private var category: ExpenseCategory?
    @State private var paidBy: Partner?
    @State private var kind: SplitKind
    @State private var percentText: String

    init(rule: AllocationRule?) {
        existing = rule
        let r = rule ?? AllocationRule()
        _name = State(initialValue: r.name)
        _propertyID = State(initialValue: r.propertyID)
        _category = State(initialValue: r.category)
        _paidBy = State(initialValue: r.paidBy)
        _kind = State(initialValue: r.split.kind)
        _percentText = State(initialValue: Fmt.number(r.split.myPercent))
    }

    var body: some View {
        let settings = store.partnerSettings
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name, e.g. Shop repairs", "Naam, jaise Dukaan repair"), text: $name)
                }
                Section {
                    Picker(L("Property", "Property"), selection: $propertyID) {
                        Text(L("Any property", "Koi bhi property")).tag(Optional<UUID>.none)
                        ForEach(store.activeProperties) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    Picker(L("Category", "Category"), selection: $category) {
                        Text(L("Any category", "Koi bhi category")).tag(Optional<ExpenseCategory>.none)
                        ForEach(ExpenseCategory.allCases) { c in
                            Text(c.label).tag(Optional(c))
                        }
                    }
                } header: {
                    Text(L("Applies to", "Kis par lagega"))
                }
                Section {
                    Picker(L("Usually paid by", "Aam taur par kaun deta hai"), selection: $paidBy) {
                        Text(L("Don't change", "Na badlein")).tag(Optional<Partner>.none)
                        Text(settings.myName).tag(Optional(Partner.me))
                        Text(settings.partnerName).tag(Optional(Partner.partner))
                    }
                    Picker(L("Shared as", "Batwara"), selection: $kind) {
                        Text(L("Shared ", "Dono ka ") + Partnership.splitText(ExpenseSplit(), settings: settings)).tag(SplitKind.shared)
                        Text(L("Only ", "Sirf ") + settings.myName + L("'s", " ka")).tag(SplitKind.mine)
                        Text(L("Only ", "Sirf ") + settings.partnerName + L("'s", " ka")).tag(SplitKind.partners)
                        Text(L("Custom share", "Apna hissa")).tag(SplitKind.custom)
                    }
                    if kind == .custom {
                        HStack {
                            Text(L("Share of ", "Hissa: ") + settings.myName)
                            Spacer()
                            TextField("60", text: $percentText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Sharing", "Batwara"))
                }
            }
            .navigationTitle(existing == nil ? L("New rule", "Naya rule") : L("Rule", "Rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                }
            }
            .keyboardDoneButton()
        }
    }

    private func save() {
        var r = existing ?? AllocationRule()
        r.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        r.propertyID = propertyID
        r.category = category
        r.paidBy = paidBy
        r.split = ExpenseSplit(kind: kind, myPercent: min(max(parseDecimal(percentText) ?? 50, 0), 100))
        store.saveRule(r, isNew: existing == nil)
        dismiss()
    }
}

// MARK: - History

struct PartnerHistoryView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: PartnerSheet? = nil
    @State private var chosen: PartnerEntry? = nil
    @State private var voiding: PartnerEntry? = nil
    @State private var voidReason = ""
    @State private var showVoided = true

    var body: some View {
        let lines = Partnership.history(store.data).filter { showVoided || !$0.voided }.reversed()
        let settings = store.partnerSettings
        List {
            Section {
                Toggle(L("Show voided entries", "Radd entries dikhayein"), isOn: $showVoided)
                LabeledContent(L("Opening balance", "Shuru ka balance"), value: Fmt.inr(settings.openingBalance))
            } footer: {
                Text(L("Newest first. The amount is the change in what you owe ", "Naya sabse upar. Amount batata hai ")
                     + settings.partnerName + L("; the balance is after each line.", " ko dene mein kitna badla; balance har line ke baad ka hai."))
            }
            Section {
                ForEach(Array(lines)) { line in
                    row(line)
                }
            }
        }
        .navigationTitle(L("History", "History"))
        .sheet(item: $sheet) { which in
            PartnerSheetView(sheet: which).environmentObject(store)
        }
        .confirmationDialog(chosen.map { store.entryText($0) } ?? "", isPresented: chosenBinding, titleVisibility: .visible) {
            if let e = chosen, !e.isVoided {
                Button(L("Correct this entry", "Yeh entry theek karein")) { sheet = .correct(e.id) }
                Button(L("Void this entry", "Yeh entry radd karein"), role: .destructive) {
                    voidReason = ""
                    voiding = e
                }
            }
        }
        .alert(L("Void this entry?", "Yeh entry radd karein?"), isPresented: voidBinding) {
            TextField(L("Reason", "Kaaran"), text: $voidReason)
            Button(L("Void", "Radd karein"), role: .destructive) {
                if let e = voiding { store.voidPartnerEntry(e.id, reason: voidReason) }
                voiding = nil
            }
            Button(L("Cancel", "Cancel"), role: .cancel) { voiding = nil }
        } message: {
            Text(L("It will no longer count in the balance.", "Yeh balance mein nahi gini jayegi."))
        }
    }

    private var chosenBinding: Binding<Bool> {
        Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })
    }

    private var voidBinding: Binding<Bool> {
        Binding(get: { voiding != nil }, set: { if !$0 { voiding = nil } })
    }

    @ViewBuilder
    private func row(_ line: PartnerHistoryLine) -> some View {
        if let expenseID = line.expenseID {
            NavigationLink(value: Route.expense(expenseID)) {
                HistoryRow(line: line)
            }
        } else if let id = line.entryID, let entry = store.partnerEntry(id) {
            Button {
                if !entry.isVoided { chosen = entry }
            } label: {
                HistoryRow(line: line)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HistoryRow(line: line)
        }
    }
}

struct HistoryRow: View {
    let line: PartnerHistoryLine

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .strikethrough(line.voided)
                    .foregroundStyle(line.voided ? .secondary : .primary)
                Text(Fmt.date(line.date) + " · " + line.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(line.voided ? "—" : (line.effect > 0 ? "+" : "") + Fmt.inr(line.effect))
                    .font(.subheadline.weight(.semibold))
                Text(Fmt.inr(line.balance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings

struct PartnershipSettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = true
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var shareText = "50"
    @State private var phone = ""
    @State private var hasStart = true
    @State private var startMonth = DateMath.monthKey(Date())
    @State private var openingDirection: Partner? = nil
    @State private var openingText = ""
    @State private var prepared = false
    @State private var confirming = false

    private var draft: PartnershipSettings {
        var s = store.partnerSettings
        s.enabled = enabled
        s.myName = myName
        s.partnerName = partnerName
        s.myShare = min(max(parseDecimal(shareText) ?? 50, 0), 100)
        s.partnerPhone = phone.trimmingCharacters(in: .whitespaces)
        s.startDate = hasStart ? Partnership.monthDate(startMonth) : nil
        let amount = parseAmount(openingText) ?? 0
        switch openingDirection {
        case .some(.me): s.openingBalance = amount
        case .some(.partner): s.openingBalance = -amount
        case .none: s.openingBalance = 0
        }
        return s
    }

    /// The balance today with these settings, to show what a change does.
    private var balanceWithDraft: Int {
        var data = store.data
        data.partnership.settings = draft
        return Partnership.summary(data).balance
    }

    private var changesBalance: Bool {
        store.partnerSettings.enabled && balanceWithDraft != Partnership.summary(store.data).balance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L("Keep a hisaab with a partner", "Partner ke saath hisaab rakhein"), isOn: $enabled)
                } footer: {
                    Text(L("Turning it off hides the hisaab. Nothing recorded is deleted.", "Band karne se hisaab chhup jata hai. Kuch delete nahi hota."))
                }
                if enabled {
                    namesSection
                    startSection
                    if changesBalance {
                        Section {
                            LabeledContent(L("Balance now", "Abhi ka balance"), value: Fmt.inr(Partnership.summary(store.data).balance))
                            LabeledContent(L("Balance with these changes", "In badlavon ke baad"), value: Fmt.inr(balanceWithDraft))
                        } footer: {
                            Text(L("Changing the shares, the start or the opening balance changes every month's working.",
                                   "Hissa, shuru ka mahina ya pichla balance badalne se har mahine ka hisaab badal jata hai."))
                        }
                    }
                }
            }
            .navigationTitle(L("Hisaab settings", "Hisaab settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) {
                        if changesBalance { confirming = true } else { save() }
                    }
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .confirmationDialog(L("Change the balance?", "Balance badlein?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(L("Save changes", "Badlav save karein")) { save() }
            } message: {
                Text(Fmt.inr(Partnership.summary(store.data).balance) + " → " + Fmt.inr(balanceWithDraft))
            }
        }
    }

    private var namesSection: some View {
        Section {
            TextField(L("Your name", "Aapka naam"), text: $myName)
            TextField(L("Partner's name", "Partner ka naam"), text: $partnerName)
            HStack {
                Text(L("Your share", "Aapka hissa"))
                Spacer()
                TextField("50", text: $shareText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("%").foregroundStyle(.secondary)
            }
            LabeledContent((partnerName.isEmpty ? L("Partner", "Partner") : partnerName) + L("'s share", " ka hissa"),
                           value: Fmt.percent(100 - min(max(parseDecimal(shareText) ?? 50, 0), 100)))
            TextField(L("Partner's mobile (for WhatsApp)", "Partner ka mobile (WhatsApp ke liye)"), text: $phone)
                .keyboardType(.phonePad)
        } header: {
            Text(L("Partners", "Partners"))
        } footer: {
            Text(L("Rent and shared expenses are split in these shares. Each expense can still be shared differently.",
                   "Rent aur shared kharche isi hisse mein bante hain. Har kharche ka batwara alag bhi rakh sakte hain."))
        }
    }

    private var startSection: some View {
        Section {
            Toggle(L("Start from a month", "Ek mahine se shuru karein"), isOn: $hasStart)
            if hasStart {
                MonthPicker(title: L("First month", "Pehla mahina"), monthKey: $startMonth)
            }
            Picker(L("Before that", "Usse pehle"), selection: $openingDirection) {
                Text(L("Nothing was owed", "Kuch baaki nahi tha")).tag(Optional<Partner>.none)
                Text(L("I owed ", "Mujhe dena tha: ") + (partnerName.isEmpty ? L("my partner", "partner") : partnerName)).tag(Optional(Partner.me))
                Text((partnerName.isEmpty ? L("My partner", "Partner") : partnerName) + L(" owed me", " ko mujhe dena tha")).tag(Optional(Partner.partner))
            }
            if openingDirection != nil {
                MoneyField(title: L("Amount", "Amount"), text: $openingText)
            }
        } header: {
            Text(L("Starting point", "Shuruaat"))
        } footer: {
            Text(L("Expenses and rent before the first month are left out. Put whatever was owed before it as the starting amount.",
                   "Pehle mahine se pehle ke kharche aur rent nahi gine jaate. Usse pehle ka jo baaki tha woh yahan likhein."))
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let s = store.partnerSettings
        let fresh = !s.enabled && store.partnership.entries.isEmpty && store.partnership.sources.isEmpty
        enabled = true
        let landlord = store.settings.landlordName.trimmingCharacters(in: .whitespaces)
        myName = fresh && s.myName == "Me" && !landlord.isEmpty ? landlord : (s.myName == "Me" ? L("Me", "Main") : s.myName)
        partnerName = fresh && s.partnerName == "Brother" ? L("Brother", "Bhai") : s.partnerName
        shareText = Fmt.number(s.myShare)
        phone = s.partnerPhone
        hasStart = s.startDate != nil || fresh
        startMonth = DateMath.monthKey(s.startDate ?? Date())
        if s.openingBalance > 0 {
            openingDirection = .me
            openingText = String(s.openingBalance)
        } else if s.openingBalance < 0 {
            openingDirection = .partner
            openingText = String(-s.openingBalance)
        }
    }

    private func save() {
        store.savePartnershipSettings(draft)
        dismiss()
    }
}

// MARK: - Sending the statement

struct PartnerMessageView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let monthKey: String

    @State private var language: AppLanguage = Lang.current
    @State private var text = ""
    @State private var prepared = false
    @State private var showShare = false
    @State private var copied = false

    var body: some View {
        let settings = store.partnerSettings
        NavigationStack {
            Form {
                Section {
                    Picker(L("Language", "Bhasha"), selection: $language) {
                        ForEach(AppLanguage.allCases) { l in
                            Text(l.label).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                    Button(L("Start again from the statement", "Statement se dobara banayein")) {
                        regenerate()
                    }
                } header: {
                    Text(L("Message", "Message"))
                } footer: {
                    Text(L("Edit the text as you like before sending.", "Bhejne se pehle text badal sakte hain."))
                }
                Section {
                    if let url = Messages.whatsappURL(phone: settings.partnerPhone, text: text) {
                        Button {
                            openURL(url)
                            dismiss()
                        } label: {
                            Label(L("Open in WhatsApp", "WhatsApp mein kholein"), systemImage: "paperplane.fill")
                        }
                    } else {
                        Text(L("Add your partner's mobile in Hisaab settings to send on WhatsApp.",
                               "WhatsApp par bhejne ke liye Hisaab settings mein partner ka mobile jodein."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? L("Copied", "Copy ho gaya") : L("Copy text", "Text copy karein"), systemImage: "doc.on.doc")
                    }
                    Button {
                        showShare = true
                    } label: {
                        Label(L("Share another way", "Kisi aur tarah share karein"), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle(L("Send hisaab", "Hisaab bhejein"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close", "Band karein")) { dismiss() }
                }
            }
            .onAppear {
                if !prepared {
                    prepared = true
                    regenerate()
                }
            }
            .onChange(of: language) { _ in
                regenerate()
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [text])
            }
        }
    }

    private func regenerate() {
        let summary = Partnership.summary(store.data)
        if let m = summary.months.first(where: { $0.key == monthKey }) {
            text = Partnership.statementText(m, settings: store.partnerSettings, language: language)
        } else {
            text = L("Balance now: ", "Ab ka balance: ", in: language) + Partnership.owedText(summary.balance, language: language)
        }
        copied = false
    }
}
