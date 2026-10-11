//  ExpenseViews.swift
//  Property expenses and bills: list with filters, add and edit, attached bills,
//  who paid and how it is shared with your partner, and repair work from report
//  to completion.

import SwiftUI

enum ExpensePeriod: String, CaseIterable, Identifiable {
    case thisMonth, thisYear, lastYear, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth: return L("This month", "Is mahine")
        case .thisYear: return L("This financial year", "Is financial year")
        case .lastYear: return L("Last financial year", "Pichhla financial year")
        case .all: return L("All time", "Shuru se ab tak")
        }
    }

    func contains(_ date: Date, asOf: Date = Date()) -> Bool {
        let today = DateMath.day(asOf)
        let start: Date
        let end: Date
        switch self {
        case .thisMonth:
            start = DateMath.monthStart(today)
            end = DateMath.monthEnd(today)
        case .thisYear:
            start = DateMath.financialYearStart(today)
            end = DateMath.addDays(-1, to: DateMath.addMonths(12, to: start))
        case .lastYear:
            start = DateMath.addMonths(-12, to: DateMath.financialYearStart(today))
            end = DateMath.addDays(-1, to: DateMath.addMonths(12, to: start))
        case .all:
            return true
        }
        let day = DateMath.day(date)
        return day >= start && day <= end
    }
}

enum ExpenseStatusFilter: String, CaseIterable, Identifiable {
    case all, unpaid, paid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("Paid and unpaid", "Diye aur baaki")
        case .unpaid: return L("Unpaid bills", "Baaki bills")
        case .paid: return L("Paid", "Diye hue")
        }
    }
}

enum ExpensePlace {
    static func text(_ e: Expense, store: Store) -> String {
        guard let p = store.property(e.propertyID) else { return "" }
        let unit = Portfolio.unitName(e.unitID, in: p)
        return unit.isEmpty ? p.name : unit + ", " + p.name
    }

    /// What the expense was for: its title, else the vendor, else the category.
    static func name(_ e: Expense) -> String {
        if !e.title.isEmpty { return e.title }
        if e.isRepair && !e.issue.isEmpty { return e.issue }
        return e.vendor.isEmpty ? e.category.label : e.vendor
    }
}

func repairColor(_ status: RepairStatus) -> Color {
    switch status {
    case .reported: return .red
    case .inProgress: return .orange
    case .done: return .green
    }
}

struct ExpenseListView: View {
    @EnvironmentObject var store: Store
    let propertyID: UUID?

    @State private var filterProperty: UUID? = nil
    @State private var category: ExpenseCategory? = nil
    @State private var status: ExpenseStatusFilter = .all
    @State private var period: ExpensePeriod = .all
    @State private var query = ""
    @State private var showingAdd = false

    private var isFiltered: Bool {
        filterProperty != nil || category != nil || status != .all || period != .all
    }

    private var screenTitle: String {
        if let p = store.property(propertyID) { return p.name + L(" expenses", " ke kharche") }
        return L("Expenses", "Kharche")
    }

    var body: some View {
        let list = filtered
        let total = list.reduce(0) { $0 + $1.amount }
        let unpaid = list.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }
        let groups = Dictionary(grouping: list) { DateMath.monthStart($0.date) }.sorted { $0.key > $1.key }
        List {
            Section {
                TileGrid {
                    StatTile(title: L("Total", "Kul"), value: Fmt.inr(total))
                    StatTile(title: L("Unpaid bills", "Baaki bills"), value: Fmt.inr(unpaid), tint: unpaid > 0 ? .orange : .primary)
                }
                if isFiltered {
                    HStack {
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Clear", "Hatayein")) { clearFilters() }
                            .font(.caption)
                    }
                }
            }
            if list.isEmpty {
                Text(store.data.expenses.isEmpty ? L("No expenses yet. Tap + to add one.", "Abhi koi kharcha nahi. + dabakar jodein.")
                     : L("No expenses match.", "Aisa koi kharcha nahi mila."))
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.key) { group in
                Section(monthTitle(group.key, group.value)) {
                    ForEach(group.value) { e in
                        NavigationLink(value: Route.expense(e.id)) {
                            ExpenseRow(expense: e, place: propertyID == nil ? ExpensePlace.text(e, store: store) : "")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                togglePaid(e)
                            } label: {
                                Label(e.isPaid ? L("Unpaid", "Baaki") : L("Paid", "Diya"),
                                      systemImage: e.isPaid ? "xmark.circle" : "checkmark.circle")
                            }
                            .tint(e.isPaid ? .orange : .green)
                            Button {
                                store.setExpenseArchived(e.id, true)
                            } label: {
                                Label(L("Archive", "Archive"), systemImage: "archivebox")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: L("What for, vendor, category or note", "Kis cheez ka, vendor, category ya note"))
        .navigationTitle(screenTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                filterMenu
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseFormView(expense: nil, presetPropertyID: propertyID ?? filterProperty).environmentObject(store)
        }
    }

    private var filtered: [Expense] {
        let pid = propertyID ?? filterProperty
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let wanted = status
        let chosenCategory = category
        let chosenPeriod = period
        return store.data.expenses.filter { e in
            if e.isArchived { return false }
            if let pid = pid, e.propertyID != pid { return false }
            if let c = chosenCategory, e.category != c { return false }
            if wanted == .unpaid && e.isPaid { return false }
            if wanted == .paid && !e.isPaid { return false }
            if !chosenPeriod.contains(e.date) { return false }
            if !q.isEmpty {
                let text = (e.title + " " + e.vendor + " " + e.note + " " + e.issue + " " + e.category.label).lowercased()
                if !text.contains(q) { return false }
            }
            return true
        }
        .sorted { $0.date > $1.date }
    }

    private func monthTitle(_ month: Date, _ items: [Expense]) -> String {
        let total = items.reduce(0) { $0 + $1.amount }
        return Fmt.month(month) + " · " + Fmt.inr(total)
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let id = filterProperty, let p = store.property(id) { parts.append(p.name) }
        if let c = category { parts.append(c.label) }
        if status != .all { parts.append(status.label) }
        if period != .all { parts.append(period.label) }
        return parts.joined(separator: " · ")
    }

    private func clearFilters() {
        filterProperty = nil
        category = nil
        status = .all
        period = .all
    }

    private var filterMenu: some View {
        Menu {
            if propertyID == nil {
                Picker(L("Property", "Property"), selection: $filterProperty) {
                    Text(L("All properties", "Saari properties")).tag(Optional<UUID>.none)
                    ForEach(store.activeProperties) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            Picker(L("Category", "Category"), selection: $category) {
                Text(L("All categories", "Saari categories")).tag(Optional<ExpenseCategory>.none)
                ForEach(ExpenseCategory.allCases) { c in
                    Text(c.label).tag(Optional(c))
                }
            }
            Picker(L("Status", "Status"), selection: $status) {
                ForEach(ExpenseStatusFilter.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Picker(L("Period", "Samay"), selection: $period) {
                ForEach(ExpensePeriod.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
        } label: {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private func togglePaid(_ e: Expense) {
        let paid = !e.isPaid
        store.updateExpense(e.id, log: paid ? "Bill marked paid" : "Bill marked unpaid",
                            details: ExpensePlace.name(e) + " · " + Fmt.inr(e.amount)) { x in
            x.isPaid = paid
            if paid { x.dueDate = nil }
        }
    }
}

struct ExpenseRow: View {
    @EnvironmentObject var store: Store
    let expense: Expense
    let place: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ExpensePlace.name(expense))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.inr(expense.amount))
                    .font(.subheadline.weight(.semibold))
                if expense.isRepair && expense.repairStatus != .done {
                    TagLabel(text: expense.repairStatus.label, color: repairColor(expense.repairStatus))
                } else if !expense.isPaid {
                    TagLabel(text: L("Unpaid", "Baaki"), color: .orange)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [Fmt.date(expense.date)]
        if !expense.title.isEmpty || !expense.vendor.isEmpty { parts.append(expense.category.label) }
        if !place.isEmpty { parts.append(place) }
        let settings = store.partnerSettings
        if settings.enabled {
            if expense.paidBy == .partner {
                parts.append(L("paid by ", "diya: ") + settings.partnerName)
            }
            if expense.split.kind != .shared {
                parts.append(Partnership.splitText(expense.split, settings: settings))
            }
        }
        if !expense.isPaid, let due = expense.dueDate { parts.append(L("due ", "dena hai ") + Fmt.date(due)) }
        return parts.joined(separator: " · ")
    }
}

/// Who paid an expense and how it is shared, with the amounts for each partner.
struct SplitSection: View {
    let settings: PartnershipSettings
    let amount: Int
    @Binding var paidBy: Partner
    @Binding var kind: SplitKind
    @Binding var myPercentText: String
    var footerNote = ""

    private var split: ExpenseSplit {
        ExpenseSplit(kind: kind, myPercent: parseDecimal(myPercentText) ?? 50)
    }

    private var preview: Expense {
        var e = Expense()
        e.amount = amount
        e.paidBy = paidBy
        e.split = split
        return e
    }

    var body: some View {
        let shares = Partnership.shares(of: preview, settings: settings)
        Section {
            Picker(L("Paid by", "Kisne diya"), selection: $paidBy) {
                Text(settings.myName).tag(Partner.me)
                Text(settings.partnerName).tag(Partner.partner)
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
                    TextField("50", text: $myPercentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    Text("%").foregroundStyle(.secondary)
                }
            }
            if amount > 0 {
                LabeledContent(settings.myName, value: Fmt.inr(shares.mine))
                LabeledContent(settings.partnerName, value: Fmt.inr(shares.partner))
            }
        } header: {
            Text(L("Sharing with ", "Hissa: ") + settings.partnerName)
        } footer: {
            Text(footer(shares))
        }
    }

    private func footer(_ shares: (mine: Int, partner: Int)) -> String {
        var text: String
        var anyDate = settings
        anyDate.startDate = nil
        if !Partnership.counts(preview, settings: anyDate) {
            text = amount > 0 ? L("Not part of the hisaab with ", "Iska ") + settings.partnerName + L(".", " ke hisaab se lena-dena nahi.")
                : L("Enter the amount to see each share.", "Har hisse ke liye amount daalein.")
        } else if paidBy == .me {
            text = L(settings.partnerName + " owes you " + Fmt.inr(shares.partner) + " for this.",
                     "Iske liye " + settings.partnerName + " se " + Fmt.inr(shares.partner) + " lene hain.")
        } else {
            text = L("You owe " + settings.partnerName + " " + Fmt.inr(shares.mine) + " for this.",
                     "Iske liye " + settings.partnerName + " ko " + Fmt.inr(shares.mine) + " dene hain.")
        }
        if !footerNote.isEmpty { text += "\n" + footerNote }
        return text
    }
}

struct ExpenseFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let existing: Expense?

    @State private var title: String
    @State private var propertyID: UUID?
    @State private var unitID: UUID?
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var amountText: String
    @State private var vendor: String
    @State private var note: String
    @State private var isPaid: Bool
    @State private var dueDate: Date?
    @State private var paidBy: Partner
    @State private var splitKind: SplitKind
    @State private var myPercentText: String
    @State private var userChoseSplit: Bool
    @State private var ruleName = ""
    @State private var isRepair: Bool
    @State private var issue: String
    @State private var repairStatus: RepairStatus
    @State private var reportedOn: Date
    @State private var completedOn: Date

    init(expense: Expense?, presetPropertyID: UUID? = nil, presetRepair: Bool = false) {
        existing = expense
        var e = expense ?? Expense()
        if expense == nil && presetRepair {
            e.isRepair = true
            e.repairStatus = .reported
            e.isPaid = false
        }
        _title = State(initialValue: e.title)
        _propertyID = State(initialValue: expense == nil ? presetPropertyID : e.propertyID)
        _unitID = State(initialValue: e.unitID)
        _category = State(initialValue: e.category)
        _date = State(initialValue: e.date)
        _amountText = State(initialValue: amountString(e.amount))
        _vendor = State(initialValue: e.vendor)
        _note = State(initialValue: e.note)
        _isPaid = State(initialValue: e.isPaid)
        _dueDate = State(initialValue: e.dueDate)
        _paidBy = State(initialValue: e.paidBy)
        _splitKind = State(initialValue: e.split.kind)
        _myPercentText = State(initialValue: Fmt.number(e.split.myPercent))
        _userChoseSplit = State(initialValue: expense != nil)
        _isRepair = State(initialValue: e.isRepair)
        _issue = State(initialValue: e.issue)
        _repairStatus = State(initialValue: e.repairStatus)
        _reportedOn = State(initialValue: e.reportedOn ?? e.date)
        _completedOn = State(initialValue: e.completedOn ?? e.date)
    }

    private var screenTitle: String {
        if existing != nil { return L("Edit expense", "Kharcha badlein") }
        return isRepair ? L("New repair", "Naya repair") : L("New expense", "Naya kharcha")
    }

    private var amount: Int { parseAmount(amountText) ?? 0 }

    /// A repair can be saved before its cost is known.
    private var canSave: Bool {
        amount > 0 || (isRepair && repairStatus != .done)
    }

    private var paidByBinding: Binding<Partner> {
        Binding(get: { paidBy }, set: { paidBy = $0; userChoseSplit = true })
    }

    private var splitBinding: Binding<SplitKind> {
        Binding(get: { splitKind }, set: { splitKind = $0; userChoseSplit = true })
    }

    private var percentBinding: Binding<String> {
        Binding(get: { myPercentText }, set: { myPercentText = $0; userChoseSplit = true })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: L("Amount", "Amount"), text: $amountText)
                    TextField(L("What for (e.g. bathroom tap)", "Kis cheez ka (jaise bathroom ka nal)"), text: $title)
                    Picker(L("Category", "Category"), selection: $category) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
                    TextField(L("Paid to (vendor)", "Kisko diya (vendor)"), text: $vendor)
                    TextField(L("Note", "Note"), text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section(L("Property", "Property")) {
                    Picker(L("Property", "Property"), selection: $propertyID) {
                        Text(L("None", "Koi nahi")).tag(Optional<UUID>.none)
                        ForEach(store.activeProperties) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    if let p = store.property(propertyID), !p.units.isEmpty {
                        Picker(L("Unit", "Unit"), selection: $unitID) {
                            Text(L("Whole property", "Poori property")).tag(Optional<UUID>.none)
                            ForEach(p.units) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                    }
                }
                if store.partnerSettings.enabled {
                    SplitSection(settings: store.partnerSettings, amount: amount, paidBy: paidByBinding,
                                 kind: splitBinding, myPercentText: percentBinding,
                                 footerNote: ruleName.isEmpty ? "" : L("Sharing rule used: ", "Rule laga: ") + ruleName)
                }
                repairSection
                Section {
                    Toggle(L("Already paid", "Paise de diye"), isOn: $isPaid)
                    if !isPaid {
                        OptionalDatePicker(title: L("Payment due date", "Dene ki tareekh"), date: $dueDate)
                    }
                } footer: {
                    Text(L("Unpaid bills show on the home screen until you mark them paid. Attach the bill after saving.",
                           "Baaki bills home screen par dikhte hain jab tak aap unhe paid mark na karein. Save karne ke baad bill jodein."))
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
            .onAppear {
                applyRule()
            }
            .onChange(of: propertyID) { _ in
                fixUnit()
                applyRule()
            }
            .onChange(of: category) { _ in
                applyRule()
            }
        }
    }

    private var repairSection: some View {
        Section {
            Toggle(L("Track as repair work", "Repair ki tarah track karein"), isOn: $isRepair)
            if isRepair {
                TextField(L("What needs fixing", "Kya theek karna hai"), text: $issue, axis: .vertical)
                    .lineLimit(1...3)
                Picker(L("Status", "Status"), selection: $repairStatus) {
                    ForEach(RepairStatus.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                DatePicker(L("Reported on", "Kab bataya"), selection: $reportedOn, displayedComponents: .date)
                if repairStatus == .done {
                    DatePicker(L("Completed on", "Kab poora hua"), selection: $completedOn, displayedComponents: .date)
                }
            }
        } footer: {
            if isRepair {
                Text(L("Open repairs show on the home screen. The cost can be added when the work is done.",
                       "Khule repair home screen par dikhte hain. Kaam hone par kharcha jod sakte hain."))
            }
        }
    }

    /// Applies the saved sharing rule for this property and category to a new expense,
    /// until who paid or the split is changed by hand.
    private func applyRule() {
        guard existing == nil, !userChoseSplit, store.partnerSettings.enabled else { return }
        if let rule = store.suggestedRule(propertyID: propertyID, category: category) {
            splitKind = rule.split.kind
            myPercentText = Fmt.number(rule.split.myPercent)
            if let who = rule.paidBy { paidBy = who }
            ruleName = rule.name.isEmpty ? store.ruleText(rule) : rule.name
        } else {
            splitKind = .shared
            ruleName = ""
        }
    }

    private func fixUnit() {
        guard let unit = unitID else { return }
        if let p = store.property(propertyID), p.units.contains(where: { $0.id == unit }) { return }
        unitID = nil
    }

    private func save() {
        var e = existing ?? Expense()
        e.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        e.propertyID = propertyID
        e.unitID = propertyID == nil ? nil : unitID
        e.category = category
        e.date = DateMath.day(date)
        e.amount = amount
        e.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        e.isPaid = isPaid
        e.dueDate = isPaid ? nil : dueDate.map { DateMath.day($0) }
        e.paidBy = paidBy
        e.split = ExpenseSplit(kind: splitKind, myPercent: min(max(parseDecimal(myPercentText) ?? 50, 0), 100))
        e.isRepair = isRepair
        if isRepair {
            e.issue = issue.trimmingCharacters(in: .whitespacesAndNewlines)
            e.repairStatus = repairStatus
            e.reportedOn = DateMath.day(reportedOn)
            e.completedOn = repairStatus == .done ? DateMath.day(completedOn) : nil
        }
        store.saveExpense(e, isNew: existing == nil)
        dismiss()
    }
}

struct ExpenseDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let expenseID: UUID

    @State private var editing = false
    @State private var askArchive = false

    var body: some View {
        if let e = store.expense(expenseID) {
            content(e)
        } else {
            Text(L("This expense was removed.", "Yeh kharcha hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ e: Expense) -> some View {
        let place = ExpensePlace.text(e, store: store)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title.isEmpty ? e.category.label : e.title + " · " + e.category.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Fmt.inr(e.amount))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    HStack {
                        if !e.isPaid {
                            TagLabel(text: L("Unpaid", "Baaki"), color: .orange)
                        }
                        if e.recurringID != nil {
                            TagLabel(text: L("Recurring", "Har mahine"), color: .blue)
                        }
                    }
                }
                .padding(.vertical, 4)
                LabeledContent(L("Date", "Tareekh"), value: Fmt.date(e.date))
                if !e.vendor.isEmpty {
                    LabeledContent(L("Paid to", "Kisko diya"), value: e.vendor)
                }
                LabeledContent(L("Property", "Property"), value: place.isEmpty ? L("Not linked", "Juda nahi") : place)
                if !e.isPaid, let due = e.dueDate {
                    LabeledContent(L("Due", "Dena hai"), value: Fmt.date(due))
                }
                if !e.note.isEmpty {
                    Text(e.note)
                }
                if e.isArchived {
                    Text(L("Archived", "Archive kiya hua"))
                        .foregroundStyle(.secondary)
                }
            }
            if store.partnerSettings.enabled {
                sharingSection(e)
            }
            if e.isRepair {
                repairSection(e)
            }
            AttachmentsSection(title: L("Bill, receipt and photos", "Bill, raseed aur photo"), ids: e.attachmentIDs, category: "Expense bill") { id in
                store.updateExpense(e.id) { $0.attachmentIDs.append(id) }
            }
            actionsSection(e)
        }
        .attachmentHost()
        .navigationTitle(e.isRepair ? L("Repair", "Repair") : L("Expense", "Kharcha"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("Edit", "Badlein")) { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            ExpenseFormView(expense: e).environmentObject(store)
        }
        .confirmationDialog(L("Archive this expense?", "Yeh kharcha archive karein?"), isPresented: $askArchive, titleVisibility: .visible) {
            Button(L("Archive", "Archive karein"), role: .destructive) {
                store.setExpenseArchived(e.id, true)
                dismiss()
            }
        } message: {
            Text(L("It no longer counts in totals, reports or the hisaab with your partner. You can restore it from Settings → Archived.",
                   "Yeh totals, reports aur partner ke hisaab mein nahi gina jayega. Settings → Archived se wapas la sakte hain."))
        }
    }

    private func sharingSection(_ e: Expense) -> some View {
        let settings = store.partnerSettings
        let shares = Partnership.shares(of: e, settings: settings)
        let counts = Partnership.counts(e, settings: settings)
        return Section {
            LabeledContent(L("Paid by", "Kisne diya"), value: Partnership.name(e.paidBy, settings))
            LabeledContent(L("Shared as", "Batwara"), value: Partnership.splitText(e.split, settings: settings))
            LabeledContent(settings.myName, value: Fmt.inr(shares.mine))
            LabeledContent(settings.partnerName, value: Fmt.inr(shares.partner))
        } header: {
            Text(L("Sharing with ", "Hissa: ") + settings.partnerName)
        } footer: {
            if !counts {
                if let start = settings.startDate, DateMath.monthStart(e.date) < DateMath.monthStart(start), e.amount > 0 {
                    Text(L("Before the hisaab starts (", "Hisaab shuru hone se pehle ka (") + Fmt.month(start) + L("), so it is not counted.", "), isliye nahi gina."))
                } else {
                    Text(L("Not part of the hisaab with ", "Iska ") + settings.partnerName + L(".", " ke hisaab se lena-dena nahi."))
                }
            } else if e.paidBy == .me {
                Text(L(settings.partnerName + " owes you " + Fmt.inr(shares.partner) + " for this.",
                       "Iske liye " + settings.partnerName + " se " + Fmt.inr(shares.partner) + " lene hain."))
            } else {
                Text(L("You owe " + settings.partnerName + " " + Fmt.inr(shares.mine) + " for this.",
                       "Iske liye " + settings.partnerName + " ko " + Fmt.inr(shares.mine) + " dene hain."))
            }
        }
    }

    private func repairSection(_ e: Expense) -> some View {
        Section(L("Repair", "Repair")) {
            if !e.issue.isEmpty {
                Text(e.issue)
            }
            HStack {
                Text(L("Status", "Status"))
                Spacer()
                TagLabel(text: e.repairStatus.label, color: repairColor(e.repairStatus))
            }
            if let reported = e.reportedOn {
                LabeledContent(L("Reported on", "Kab bataya"), value: Fmt.date(reported))
            }
            if let done = e.completedOn, e.repairStatus == .done {
                LabeledContent(L("Completed on", "Kab poora hua"), value: Fmt.date(done))
                if let reported = e.reportedOn {
                    let days = DateMath.daysBetween(reported, done)
                    LabeledContent(L("Took", "Laga samay"), value: L("\(days) days", "\(days) din"))
                }
            }
            if e.repairStatus == .reported {
                Button {
                    setStatus(e, .inProgress)
                } label: {
                    Label(L("Work has started", "Kaam shuru ho gaya"), systemImage: "hammer")
                }
            }
            if e.repairStatus != .done {
                Button {
                    setStatus(e, .done)
                } label: {
                    Label(L("Mark as done", "Poora ho gaya"), systemImage: "checkmark.seal")
                }
            }
        }
    }

    private func setStatus(_ e: Expense, _ status: RepairStatus) {
        store.updateExpense(e.id, log: "Repair status changed", details: ExpensePlace.name(e) + ": " + status.label) { x in
            x.repairStatus = status
            if status == .done {
                x.completedOn = DateMath.day(Date())
            }
        }
    }

    private func actionsSection(_ e: Expense) -> some View {
        Section {
            Button {
                let paid = !e.isPaid
                store.updateExpense(e.id, log: paid ? "Bill marked paid" : "Bill marked unpaid",
                                    details: ExpensePlace.name(e) + " · " + Fmt.inr(e.amount)) { x in
                    x.isPaid = paid
                    if paid { x.dueDate = nil }
                }
            } label: {
                Label(e.isPaid ? L("Mark as unpaid", "Baaki mark karein") : L("Mark as paid", "Paid mark karein"),
                      systemImage: e.isPaid ? "xmark.circle" : "checkmark.circle")
            }
            if e.isArchived {
                Button {
                    store.setExpenseArchived(e.id, false)
                } label: {
                    Label(L("Restore expense", "Kharcha wapas layein"), systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(role: .destructive) {
                    askArchive = true
                } label: {
                    Label(L("Archive expense", "Kharcha archive karein"), systemImage: "archivebox")
                }
            }
        }
    }
}

// MARK: - Repairs

struct RepairsView: View {
    @EnvironmentObject var store: Store
    @State private var propertyID: UUID? = nil
    @State private var showingAdd = false
    @State private var showAllDone = false

    var body: some View {
        let all = store.data.expenses.filter { !$0.isArchived && $0.isRepair && (propertyID == nil || $0.propertyID == propertyID) }
        let open = all.filter { $0.repairStatus != .done }.sorted { ($0.reportedOn ?? $0.date) < ($1.reportedOn ?? $1.date) }
        let done = all.filter { $0.repairStatus == .done }.sorted { ($0.completedOn ?? $0.date) > ($1.completedOn ?? $1.date) }
        let yearStart = DateMath.financialYearStart(Date())
        let yearCost = all.filter { DateMath.day($0.date) >= yearStart }.reduce(0) { $0 + $1.amount }
        List {
            Section {
                TileGrid {
                    StatTile(title: L("Open repairs", "Khule repair"), value: "\(open.count)", tint: open.isEmpty ? .primary : .orange)
                    StatTile(title: L("Spent this financial year", "Is saal kharcha"), value: Fmt.inr(yearCost))
                }
                Picker(L("Property", "Property"), selection: $propertyID) {
                    Text(L("All properties", "Saari properties")).tag(Optional<UUID>.none)
                    ForEach(store.activeProperties) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            Section(L("Open", "Khule")) {
                if open.isEmpty {
                    Text(L("Nothing waiting to be fixed.", "Koi kaam baaki nahi."))
                        .foregroundStyle(.secondary)
                }
                ForEach(open) { e in
                    NavigationLink(value: Route.expense(e.id)) {
                        RepairRow(expense: e, place: ExpensePlace.text(e, store: store))
                    }
                }
            }
            if !done.isEmpty {
                Section(L("Done", "Ho gaye")) {
                    ForEach(showAllDone ? done : Array(done.prefix(10))) { e in
                        NavigationLink(value: Route.expense(e.id)) {
                            RepairRow(expense: e, place: ExpensePlace.text(e, store: store))
                        }
                    }
                    if done.count > 10 {
                        Button(showAllDone ? L("Show fewer", "Kam dikhayein") : L("Show all \(done.count)", "Saare \(done.count) dikhayein")) {
                            showAllDone.toggle()
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: Route.report(.repairs)) {
                    Label(L("Repairs report", "Repair report"), systemImage: "doc.text")
                }
            } footer: {
                Text(L("Each repair is also an expense, so it counts in reports and in the hisaab with your partner. Attach bills and photos on the repair.",
                       "Har repair ek kharcha bhi hai, isliye reports aur partner ke hisaab mein gina jata hai. Bill aur photo repair par jodein."))
            }
        }
        .navigationTitle(L("Repairs", "Repairs"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseFormView(expense: nil, presetPropertyID: propertyID, presetRepair: true).environmentObject(store)
        }
    }
}

struct RepairRow: View {
    let expense: Expense
    let place: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.issue.isEmpty ? ExpensePlace.name(expense) : expense.issue)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if expense.amount > 0 {
                    Text(Fmt.inr(expense.amount))
                        .font(.subheadline.weight(.semibold))
                }
                TagLabel(text: expense.repairStatus.label, color: repairColor(expense.repairStatus))
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [expense.category.label]
        if !place.isEmpty { parts.append(place) }
        if expense.repairStatus == .done, let done = expense.completedOn {
            parts.append(L("done ", "poora ") + Fmt.date(done))
        } else {
            let reported = expense.reportedOn ?? expense.date
            let days = DateMath.daysBetween(reported, Date())
            parts.append(L("reported ", "bataya ") + Fmt.date(reported) + (days > 0 ? L(" (\(days) days ago)", " (\(days) din pehle)") : ""))
        }
        if !expense.vendor.isEmpty { parts.append(expense.vendor) }
        return parts.joined(separator: " · ")
    }
}
