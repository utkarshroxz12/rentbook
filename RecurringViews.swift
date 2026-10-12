//  RecurringViews.swift
//  Monthly expenses such as society maintenance or a watchman's salary. Each month, on its
//  day, the expense saves itself and counts in the hisaab; or, when set to be checked first,
//  an entry waits for review and nothing is saved until you check it.

import SwiftUI

struct RecurringListView: View {
    @EnvironmentObject var store: Store
    @State private var editing: RecurringExpense? = nil
    @State private var adding = false
    @State private var deleting: RecurringExpense? = nil

    var body: some View {
        let pending = store.pendingRecurring
        let templates = store.data.recurringExpenses.sorted { $0.dayOfMonth < $1.dayOfMonth }
        let monthly = templates.filter { $0.isActive }.reduce(0) { $0 + $1.amount }
        let saved = store.data.expenses.filter { $0.recurringID != nil && !$0.isArchived }.sorted { $0.date > $1.date }
        List {
            if !pending.isEmpty {
                Section {
                    NavigationLink(value: Route.recurringReview) {
                        HStack {
                            Label(L("Waiting for review", "Review ke liye"), systemImage: "checklist")
                            Spacer()
                            TagLabel(text: "\(pending.count)", color: .orange)
                        }
                    }
                } footer: {
                    Text(L("These are set to be checked first. Check each amount, then save; until then they are not in your expenses or the hisaab.",
                           "Inhe pehle check karna hai. Har amount dekh kar save karein; tab tak yeh kharchon aur hisaab mein nahi aate."))
                }
            }
            Section {
                if templates.isEmpty {
                    Text(L("No recurring expenses yet. Add things you pay every month, such as society maintenance.",
                           "Abhi koi recurring kharcha nahi. Har mahine dene wale kharche jodein, jaise society maintenance."))
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { r in
                    Button {
                        editing = r
                    } label: {
                        RecurringRow(template: r)
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
                        Button {
                            store.setRecurringActive(r.id, !r.isActive)
                        } label: {
                            Label(r.isActive ? L("Pause", "Rokein") : L("Restart", "Phir shuru"), systemImage: r.isActive ? "pause.circle" : "play.circle")
                        }
                        .tint(r.isActive ? .orange : .green)
                    }
                }
            } header: {
                Text(L("Every month", "Har mahine"))
            } footer: {
                if monthly > 0 {
                    Text(concat(L("Active schedules add up to ", "Chalu kharche kul "), Fmt.inr(monthly), L(" a month.", " har mahine.")))
                }
            }
            if !saved.isEmpty {
                Section {
                    ForEach(saved.prefix(8)) { e in
                        NavigationLink(value: Route.expense(e.id)) {
                            ExpenseRow(expense: e, place: ExpensePlace.text(e, store: store))
                        }
                    }
                } header: {
                    Text(L("Saved recently", "Haal mein save hue"))
                } footer: {
                    Text(L("Tap one to change its amount. Deleting one skips that month.",
                           "Amount badalne ke liye tap karein. Delete karne par woh mahina chhoot jayega."))
                }
            }
        }
        .navigationTitle(L("Recurring expenses", "Recurring kharche"))
        .onAppear {
            store.addDueRecurring()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) {
            RecurringFormView(template: nil).environmentObject(store)
        }
        .sheet(item: $editing) { r in
            RecurringFormView(template: r).environmentObject(store)
        }
        .confirmationDialog(L("Delete this recurring expense?", "Yeh recurring kharcha delete karein?"), isPresented: deleteBinding, titleVisibility: .visible) {
            Button(L("Delete", "Delete karein"), role: .destructive) {
                if let r = deleting { store.deleteRecurring(r.id) }
                deleting = nil
            }
        } message: {
            Text(L("Expenses already saved from it stay. To stop it for a while, pause it instead.",
                   "Isse pehle save hue kharche rahenge. Kuch samay ke liye rokna ho to pause karein."))
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

struct RecurringRow: View {
    @EnvironmentObject var store: Store
    let template: RecurringExpense

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title.isEmpty ? template.category.label : template.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.inr(template.amount))
                    .font(.subheadline.weight(.semibold))
                if !template.isActive {
                    TagLabel(text: L("Paused", "Ruka hua"), color: .gray)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [L("day ", "tareekh ") + "\(template.dayOfMonth)"]
        parts.append(template.autoAdd ? L("saves itself", "khud save hota hai") : L("checked first", "pehle check"))
        if let p = store.property(template.propertyID) { parts.append(p.name) }
        let settings = store.partnerSettings
        if settings.enabled {
            parts.append(Partnership.name(template.paidBy, settings) + " · " + Partnership.splitText(template.split, settings: settings))
        }
        if let end = template.endDate { parts.append(L("until ", "tak ") + Fmt.date(end)) }
        return parts.joined(separator: " · ")
    }
}

struct RecurringFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: RecurringExpense?

    @State private var title: String
    @State private var category: ExpenseCategory
    @State private var amountText: String
    @State private var day: Int
    @State private var propertyID: UUID?
    @State private var unitID: UUID?
    @State private var vendor: String
    @State private var startDate: Date
    @State private var endDate: Date?
    @State private var isActive: Bool
    @State private var markPaid: Bool
    @State private var paidBy: Partner
    @State private var splitKind: SplitKind
    @State private var percentText: String
    @State private var autoAdd: Bool
    @State private var skipped: [String]

    init(template: RecurringExpense?) {
        existing = template
        let r = template ?? RecurringExpense()
        _title = State(initialValue: r.title)
        _category = State(initialValue: r.category)
        _amountText = State(initialValue: amountString(r.amount))
        _day = State(initialValue: r.dayOfMonth)
        _propertyID = State(initialValue: r.propertyID)
        _unitID = State(initialValue: r.unitID)
        _vendor = State(initialValue: r.vendor)
        _startDate = State(initialValue: template == nil ? DateMath.monthStart(Date()) : r.startDate)
        _endDate = State(initialValue: r.endDate)
        _isActive = State(initialValue: r.isActive)
        _markPaid = State(initialValue: r.markPaid)
        _paidBy = State(initialValue: r.paidBy)
        _splitKind = State(initialValue: r.split.kind)
        _percentText = State(initialValue: Fmt.number(r.split.myPercent))
        _autoAdd = State(initialValue: r.autoAdd)
        _skipped = State(initialValue: r.skippedMonths.sorted())
    }

    private var amount: Int { parseAmount(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("What for, e.g. Society maintenance", "Kis cheez ka, jaise Society maintenance"), text: $title)
                    MoneyField(title: L("Amount each month", "Har mahine ka amount"), text: $amountText)
                    Picker(L("Category", "Category"), selection: $category) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    Stepper(L("Day of the month: ", "Mahine ki tareekh: ") + "\(day)", value: $day, in: 1...31)
                    TextField(L("Paid to (vendor)", "Kisko dete hain (vendor)"), text: $vendor)
                } footer: {
                    if day > 28 {
                        Text(L("In shorter months the last day is used.", "Chhote mahinon mein aakhri tareekh li jayegi."))
                    }
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
                    SplitSection(settings: store.partnerSettings, amount: amount, paidBy: $paidBy, kind: $splitKind, myPercentText: $percentText)
                }
                Section {
                    DatePicker(L("Starts", "Shuru"), selection: $startDate, displayedComponents: .date)
                    OptionalDatePicker(title: L("Ends", "Khatam"), date: $endDate)
                    Toggle(L("Save it by itself each month", "Har mahine khud save ho"), isOn: $autoAdd)
                    Toggle(L("Save as already paid", "Paid ki tarah save karein"), isOn: $markPaid)
                    Toggle(L("Active", "Chalu"), isOn: $isActive)
                } footer: {
                    if autoAdd {
                        Text(L("From the 1st of each month, that month's expense is saved by itself, dated on the day above, and counts in your expenses and the hisaab for the month. Months since the start are saved too. You can still change or delete any month.",
                               "Har mahine ki 1 tareekh se us mahine ka kharcha khud save hoga, upar di tareekh ke saath, aur us mahine ke kharchon aur hisaab mein judega. Shuru se ab tak ke mahine bhi save honge. Kisi bhi mahine ko baad mein badal ya delete kar sakte hain."))
                    } else {
                        Text(L("Each month, on the day above, an entry is prepared for you to check and save. Until then it is not in your expenses or the hisaab.",
                               "Har mahine upar di tareekh par ek entry banegi jise aap dekh kar save karenge. Tab tak yeh kharchon aur hisaab mein nahi aayegi."))
                    }
                }
                if !skipped.isEmpty {
                    Section {
                        ForEach(skipped, id: \.self) { key in
                            HStack {
                                Text(Partnership.monthLabel(key))
                                Spacer()
                                Button(L("Add back", "Wapas jodein")) {
                                    skipped.removeAll { $0 == key }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text(L("Skipped months", "Chhode gaye mahine"))
                    } footer: {
                        Text(L("These months were skipped, or their expense was deleted, so they are not saved. Add one back and save to have it saved again.",
                               "Yeh mahine chhode gaye ya inka kharcha delete hua, isliye save nahi hote. Wapas jodkar save karein to phir se save ho jayega."))
                    }
                }
            }
            .navigationTitle(existing == nil ? L("New recurring expense", "Naya recurring kharcha") : L("Recurring expense", "Recurring kharcha"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(amount <= 0)
                }
            }
            .keyboardDoneButton()
            .onChange(of: propertyID) { _ in
                if let unit = unitID, store.property(propertyID)?.units.contains(where: { $0.id == unit }) != true {
                    unitID = nil
                }
            }
        }
    }

    private func save() {
        var r = existing ?? RecurringExpense()
        r.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        r.category = category
        r.amount = amount
        r.dayOfMonth = day
        r.propertyID = propertyID
        r.unitID = propertyID == nil ? nil : unitID
        r.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        r.startDate = startDate
        r.endDate = endDate
        r.isActive = isActive
        r.markPaid = markPaid
        r.paidBy = paidBy
        r.split = ExpenseSplit(kind: splitKind, myPercent: min(max(parseDecimal(percentText) ?? 50, 0), 100))
        r.autoAdd = autoAdd
        r.skippedMonths = skipped
        store.saveRecurring(r, isNew: existing == nil)
        dismiss()
    }
}

/// One prepared entry while reviewing: include it or not, its amount and date.
struct ReviewLineEditor: View {
    @Binding var line: RecurringReviewView.ReviewLine
    let title: String
    let subtitle: String
    let onSkip: () -> Void

    var body: some View {
        Section {
            Toggle(isOn: $line.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if line.include {
                MoneyField(title: L("Amount", "Amount"), text: $line.amountText)
                DatePicker(L("Date", "Tareekh"), selection: $line.date, displayedComponents: .date)
            }
            Button(L("Skip this month", "Is mahine chhodein")) {
                onSkip()
            }
            .font(.subheadline)
        }
    }
}

struct RecurringReviewView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    struct ReviewLine: Identifiable {
        var pending: PendingExpense
        var include = true
        var amountText: String
        var date: Date
        var id: String { pending.id }
    }

    @State private var lines: [ReviewLine] = []
    @State private var prepared = false
    @State private var skipping: PendingExpense? = nil

    private var total: Int {
        lines.filter { $0.include }.reduce(0) { $0 + (parseAmount($1.amountText) ?? 0) }
    }

    var body: some View {
        List {
            if lines.isEmpty {
                Section {
                    Text(L("Nothing to review. Entries appear here on the day each expense falls due.",
                           "Review ke liye kuch nahi. Har kharcha apni tareekh par yahan dikhega."))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach($lines) { line in
                ReviewLineEditor(line: line, title: title(line.wrappedValue.pending),
                                 subtitle: Partnership.monthLabel(line.wrappedValue.pending.month) + subtitle(line.wrappedValue.pending)) {
                    skipping = line.wrappedValue.pending
                }
            }
            if !lines.isEmpty {
                Section {
                    LabeledContent(L("Total to save", "Kul save hoga"), value: Fmt.inr(total))
                    Button {
                        save()
                    } label: {
                        Label(L("Save the ticked expenses", "Tick kiye kharche save karein"), systemImage: "checkmark.circle.fill")
                    }
                    .disabled(total <= 0)
                }
            }
        }
        .navigationTitle(L("Review recurring", "Recurring review"))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onAppear {
            if !prepared {
                prepared = true
                rebuild()
            }
        }
        .confirmationDialog(L("Skip this month?", "Is mahine chhodein?"), isPresented: skipBinding, titleVisibility: .visible) {
            Button(L("Skip", "Chhodein"), role: .destructive) {
                if let p = skipping {
                    store.skipPending(p)
                    lines.removeAll { $0.id == p.id }
                }
                skipping = nil
            }
        } message: {
            Text(L("No expense is saved for this month, and it will not be asked again.", "Is mahine ka kharcha save nahi hoga, aur dobara nahi poocha jayega."))
        }
    }

    private var skipBinding: Binding<Bool> {
        Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } })
    }

    private func title(_ p: PendingExpense) -> String {
        p.template.title.isEmpty ? p.template.category.label : p.template.title
    }

    private func subtitle(_ p: PendingExpense) -> String {
        var parts: [String] = []
        if let prop = store.property(p.template.propertyID) { parts.append(prop.name) }
        let settings = store.partnerSettings
        if settings.enabled {
            parts.append(Partnership.name(p.template.paidBy, settings) + " · " + Partnership.splitText(p.template.split, settings: settings))
        }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    private func rebuild() {
        lines = store.pendingRecurring.map { ReviewLine(pending: $0, amountText: amountString($0.template.amount), date: $0.date) }
    }

    private func save() {
        let items = lines.filter { $0.include }.compactMap { line -> (pending: PendingExpense, amount: Int, date: Date)? in
            guard let amount = parseAmount(line.amountText), amount > 0 else { return nil }
            return (line.pending, amount, line.date)
        }
        store.savePending(items)
        rebuild()
        if lines.isEmpty {
            dismiss()
        }
    }
}
