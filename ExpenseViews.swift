//  ExpenseViews.swift
//  Property expenses and bills: list with filters, add and edit, attached bills.

import SwiftUI

enum ExpensePeriod: String, CaseIterable, Identifiable {
    case thisMonth, thisYear, lastYear, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth: return "This month"
        case .thisYear: return "This financial year"
        case .lastYear: return "Last financial year"
        case .all: return "All time"
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
        case .all: return "Paid and unpaid"
        case .unpaid: return "Unpaid bills"
        case .paid: return "Paid"
        }
    }
}

enum ExpensePlace {
    static func text(_ e: Expense, store: Store) -> String {
        guard let p = store.property(e.propertyID) else { return "" }
        let unit = Portfolio.unitName(e.unitID, in: p)
        return unit.isEmpty ? p.name : unit + ", " + p.name
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
        if let p = store.property(propertyID) { return p.name + " expenses" }
        return "Expenses"
    }

    var body: some View {
        let list = filtered
        let total = list.reduce(0) { $0 + $1.amount }
        let unpaid = list.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }
        let groups = Dictionary(grouping: list) { DateMath.monthStart($0.date) }.sorted { $0.key > $1.key }
        List {
            Section {
                TileGrid {
                    StatTile(title: "Total", value: Fmt.inr(total))
                    StatTile(title: "Unpaid bills", value: Fmt.inr(unpaid), tint: unpaid > 0 ? .orange : .primary)
                }
                if isFiltered {
                    HStack {
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { clearFilters() }
                            .font(.caption)
                    }
                }
            }
            if list.isEmpty {
                Text(store.data.expenses.isEmpty ? "No expenses yet. Tap + to add one." : "No expenses match.")
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
                                Label(e.isPaid ? "Unpaid" : "Paid", systemImage: e.isPaid ? "xmark.circle" : "checkmark.circle")
                            }
                            .tint(e.isPaid ? .orange : .green)
                            Button {
                                store.setExpenseArchived(e.id, true)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Vendor, category or note")
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
                let text = (e.vendor + " " + e.note + " " + e.category.label).lowercased()
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
                Picker("Property", selection: $filterProperty) {
                    Text("All properties").tag(Optional<UUID>.none)
                    ForEach(store.activeProperties) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            }
            Picker("Category", selection: $category) {
                Text("All categories").tag(Optional<ExpenseCategory>.none)
                ForEach(ExpenseCategory.allCases) { c in
                    Text(c.label).tag(Optional(c))
                }
            }
            Picker("Status", selection: $status) {
                ForEach(ExpenseStatusFilter.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Picker("Period", selection: $period) {
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
                            details: e.category.label + " · " + Fmt.inr(e.amount)) { x in
            x.isPaid = paid
            if paid { x.dueDate = nil }
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let place: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor.isEmpty ? expense.category.label : expense.vendor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.inr(expense.amount))
                    .font(.subheadline.weight(.semibold))
                if !expense.isPaid {
                    TagLabel(text: "Unpaid", color: .orange)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [Fmt.date(expense.date)]
        if !expense.vendor.isEmpty { parts.append(expense.category.label) }
        if !place.isEmpty { parts.append(place) }
        if !expense.isPaid, let due = expense.dueDate { parts.append("due " + Fmt.date(due)) }
        return parts.joined(separator: " · ")
    }
}

struct ExpenseFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let existing: Expense?

    @State private var propertyID: UUID?
    @State private var unitID: UUID?
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var amountText: String
    @State private var vendor: String
    @State private var note: String
    @State private var isPaid: Bool
    @State private var dueDate: Date?

    init(expense: Expense?, presetPropertyID: UUID? = nil) {
        existing = expense
        let e = expense ?? Expense()
        _propertyID = State(initialValue: expense == nil ? presetPropertyID : e.propertyID)
        _unitID = State(initialValue: e.unitID)
        _category = State(initialValue: e.category)
        _date = State(initialValue: e.date)
        _amountText = State(initialValue: amountString(e.amount))
        _vendor = State(initialValue: e.vendor)
        _note = State(initialValue: e.note)
        _isPaid = State(initialValue: e.isPaid)
        _dueDate = State(initialValue: e.dueDate)
    }

    private var screenTitle: String { existing == nil ? "New expense" : "Edit expense" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "Amount", text: $amountText)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Paid to (vendor)", text: $vendor)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Property") {
                    Picker("Property", selection: $propertyID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(store.activeProperties) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    if let p = store.property(propertyID), !p.units.isEmpty {
                        Picker("Unit", selection: $unitID) {
                            Text("Whole property").tag(Optional<UUID>.none)
                            ForEach(p.units) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                    }
                }
                Section {
                    Toggle("Already paid", isOn: $isPaid)
                    if !isPaid {
                        OptionalDatePicker(title: "Payment due date", date: $dueDate)
                    }
                } footer: {
                    Text("Unpaid bills show on the home screen until you mark them paid. Attach the bill after saving.")
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((parseAmount(amountText) ?? 0) <= 0)
                }
            }
            .keyboardDoneButton()
            .onChange(of: propertyID) { _ in
                fixUnit()
            }
        }
    }

    private func fixUnit() {
        guard let unit = unitID else { return }
        if let p = store.property(propertyID), p.units.contains(where: { $0.id == unit }) { return }
        unitID = nil
    }

    private func save() {
        var e = existing ?? Expense()
        e.propertyID = propertyID
        e.unitID = propertyID == nil ? nil : unitID
        e.category = category
        e.date = DateMath.day(date)
        e.amount = parseAmount(amountText) ?? 0
        e.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        e.isPaid = isPaid
        if isPaid {
            e.dueDate = nil
        } else {
            e.dueDate = dueDate.map { DateMath.day($0) }
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
            Text("This expense was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ e: Expense) -> some View {
        let place = ExpensePlace.text(e, store: store)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.category.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Fmt.inr(e.amount))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if !e.isPaid {
                        TagLabel(text: "Unpaid", color: .orange)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Date", value: Fmt.date(e.date))
                if !e.vendor.isEmpty {
                    LabeledContent("Paid to", value: e.vendor)
                }
                LabeledContent("Property", value: place.isEmpty ? "Not linked" : place)
                if !e.isPaid, let due = e.dueDate {
                    LabeledContent("Due", value: Fmt.date(due))
                }
                if !e.note.isEmpty {
                    Text(e.note)
                }
                if e.isArchived {
                    Text("Archived")
                        .foregroundStyle(.secondary)
                }
            }
            AttachmentsSection(title: "Bill and receipt", ids: e.attachmentIDs, category: "Expense bill") { id in
                store.updateExpense(e.id) { $0.attachmentIDs.append(id) }
            }
            actionsSection(e)
        }
        .attachmentHost()
        .navigationTitle("Expense")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            ExpenseFormView(expense: e).environmentObject(store)
        }
        .confirmationDialog("Archive this expense?", isPresented: $askArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                store.setExpenseArchived(e.id, true)
                dismiss()
            }
        } message: {
            Text("It no longer counts in totals and reports. You can restore it from Settings → Archived.")
        }
    }

    private func actionsSection(_ e: Expense) -> some View {
        Section {
            Button {
                let paid = !e.isPaid
                store.updateExpense(e.id, log: paid ? "Bill marked paid" : "Bill marked unpaid",
                                    details: e.category.label + " · " + Fmt.inr(e.amount)) { x in
                    x.isPaid = paid
                    if paid { x.dueDate = nil }
                }
            } label: {
                Label(e.isPaid ? "Mark as unpaid" : "Mark as paid", systemImage: e.isPaid ? "xmark.circle" : "checkmark.circle")
            }
            if e.isArchived {
                Button {
                    store.setExpenseArchived(e.id, false)
                } label: {
                    Label("Restore expense", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(role: .destructive) {
                    askArchive = true
                } label: {
                    Label("Archive expense", systemImage: "archivebox")
                }
            }
        }
    }
}
