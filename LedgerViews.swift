//  LedgerViews.swift
//  The tenant ledger (month by month and full history), extra charges,
//  discounts, waivers and corrections.

import SwiftUI

enum LedgerSheet: Identifiable {
    case adjust(String)
    case extraCharge
    case share(URL)

    var id: String {
        switch self {
        case .adjust(let key): return "adjust-" + key
        case .extraCharge: return "extra"
        case .share(let url): return "share-" + url.lastPathComponent
        }
    }
}

struct LedgerEntry: Identifiable {
    var id: String
    var date: Date
    var title: String
    var detail: String
    var debit: Int
    var credit: Int
    var balance = 0
    var paymentID: UUID? = nil
    var reversed = false
}

struct TenantLedgerView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID

    @State private var mode = 0
    @State private var showAllPaid = false
    @State private var sheet: LedgerSheet? = nil

    var body: some View {
        if let t = store.tenant(tenantID), let l = store.ledger(of: tenantID) {
            content(t, l)
        } else {
            Text("This tenant was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ l: TenantLedger) -> some View {
        List {
            Section {
                Picker("View", selection: $mode) {
                    Text("Months").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                TileGrid {
                    StatTile(title: "Billed so far", value: Fmt.inr(l.totalBilled))
                    StatTile(title: "Paid so far", value: Fmt.inr(l.totalPaid), tint: .green)
                    StatTile(title: "Outstanding", value: Fmt.inr(l.outstanding), tint: l.outstanding > 0 ? .orange : .primary)
                    StatTile(title: "Advance", value: Fmt.inr(l.credit))
                }
                if l.orphanAdjustments > 0 {
                    Text("\(l.orphanAdjustments) adjustment" + (l.orphanAdjustments == 1 ? " no longer matches a billed month" : "s no longer match a billed month") + ", probably because the tenancy dates changed. See Extra charges and discounts.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if mode == 0 {
                monthSections(t, l)
            } else {
                historySection(t, l)
            }
        }
        .navigationTitle("Ledger")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sheet = .extraCharge
                    } label: {
                        Label("Add a one-off charge", systemImage: "plus")
                    }
                    Button {
                        exportPDF(t)
                    } label: {
                        Label("Statement as PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        exportCSV(t)
                    } label: {
                        Label("Statement as spreadsheet (CSV)", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .adjust(let key):
                AdjustmentFormView(tenantID: tenantID, kind: .discount, presetKey: key).environmentObject(store)
            case .extraCharge:
                AdjustmentFormView(tenantID: tenantID, kind: .extraCharge, presetKey: nil).environmentObject(store)
            case .share(let url):
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private func monthSections(_ t: Tenant, _ l: TenantLedger) -> some View {
        let open = l.unpaidLines
        let paid = l.dueLines.filter { $0.outstanding == 0 }.reversed()
        let shownPaid = showAllPaid ? Array(paid) : Array(paid.prefix(12))
        Section {
            if open.isEmpty {
                Text("Nothing is owed right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(open) { line in
                Button {
                    sheet = .adjust(line.charge.key)
                } label: {
                    ChargeRow(line: line, asOf: l.asOf, graceDays: l.graceDays)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Open")
        } footer: {
            Text("Oldest first. Tap a month to give a discount, waive it, correct it or pay it.")
        }
        Section("Coming up") {
            ForEach(Array(l.upcomingLines.prefix(4))) { line in
                Button {
                    sheet = .adjust(line.charge.key)
                } label: {
                    ChargeRow(line: line, asOf: l.asOf, graceDays: l.graceDays)
                }
                .buttonStyle(.plain)
            }
        }
        if !shownPaid.isEmpty {
            Section("Paid") {
                ForEach(shownPaid) { line in
                    Button {
                        sheet = .adjust(line.charge.key)
                    } label: {
                        ChargeRow(line: line, asOf: l.asOf, graceDays: l.graceDays)
                    }
                    .buttonStyle(.plain)
                }
                if paid.count > 12 {
                    Button(showAllPaid ? "Show fewer" : "Show all paid months") {
                        showAllPaid.toggle()
                    }
                }
            }
        }
    }

    private func historySection(_ t: Tenant, _ l: TenantLedger) -> some View {
        let entries = LedgerHistory.entries(for: t, ledger: l)
        return Section {
            if entries.isEmpty {
                Text("No charges or payments yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                if let pid = entry.paymentID {
                    NavigationLink(value: Route.payment(tenantID, pid)) {
                        LedgerEntryRow(entry: entry)
                    }
                } else {
                    LedgerEntryRow(entry: entry)
                }
            }
        } header: {
            Text("Every charge and payment, newest first")
        } footer: {
            Text("Balance is what the tenant owed after each line. A minus sign means advance credit.")
        }
    }

    private func exportPDF(_ t: Tenant) {
        var filter = ReportFilter(from: t.startDate ?? DateMath.make(2000, 1, 1), to: Date())
        filter.tenantID = t.id
        let table = Reports.build(.tenantLedger, data: store.data, filter: filter)
        if let url = PDFMaker.report(table, landlord: store.settings.landlordName) {
            sheet = .share(url)
        }
    }

    private func exportCSV(_ t: Tenant) {
        var filter = ReportFilter(from: t.startDate ?? DateMath.make(2000, 1, 1), to: Date())
        filter.tenantID = t.id
        let table = Reports.build(.tenantLedger, data: store.data, filter: filter)
        let safeName = t.name.replacingOccurrences(of: "/", with: "-")
        // The byte-order mark helps Excel read the file as UTF-8.
        if let url = store.writeTemporary("\u{FEFF}" + table.csv, named: "Ledger " + safeName + ".csv") {
            sheet = .share(url)
        }
    }
}

enum LedgerHistory {
    /// Charges and payments with a running balance, newest first.
    static func entries(for t: Tenant, ledger l: TenantLedger) -> [LedgerEntry] {
        var items: [LedgerEntry] = []
        for line in l.dueLines where (line.charge.amount > 0 || line.charge.waived) && line.charge.kind != .refundExcess {
            let note = line.charge.notes.joined(separator: " · ")
            items.append(LedgerEntry(id: "c-" + line.charge.key, date: line.charge.dueDate, title: line.charge.title,
                                     detail: note, debit: line.charge.amount, credit: 0))
        }
        for p in t.payments {
            let day = DateMath.day(p.date)
            if p.isReversed {
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: "Reversed payment",
                                         detail: p.reversalReason, debit: 0, credit: 0, paymentID: p.id, reversed: true))
            } else if p.kind == .refund {
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: "Refund to tenant",
                                         detail: p.method.label, debit: p.amount, credit: 0, paymentID: p.id))
            } else {
                let receipt = p.receiptNumber > 0 ? "Receipt #\(p.receiptNumber) · " : ""
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: "Payment received",
                                         detail: receipt + p.method.label, debit: 0, credit: p.amount, paymentID: p.id))
            }
        }
        items.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.debit > b.debit
        }
        var balance = 0
        for i in items.indices {
            balance += items[i].debit - items[i].credit
            items[i].balance = balance
        }
        return items.reversed()
    }
}

struct LedgerEntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .strikethrough(entry.reversed)
                Text(Fmt.date(entry.date) + (entry.detail.isEmpty ? "" : " · " + entry.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if entry.credit > 0 {
                    Text("-" + Fmt.inr(entry.credit))
                        .foregroundStyle(.green)
                } else if entry.debit > 0 {
                    Text(Fmt.inr(entry.debit))
                }
                if !entry.reversed {
                    Text("Bal " + Fmt.inr(entry.balance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
    }
}

struct ChargeRow: View {
    let line: ChargeLine
    let asOf: Date
    let graceDays: Int

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.charge.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !line.charge.notes.isEmpty {
                    Text(line.charge.notes.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.inr(line.charge.amount))
                    .strikethrough(line.charge.waived)
                if line.paid > 0 && line.outstanding > 0 {
                    Text(Fmt.inr(line.outstanding) + " left")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
        }
        .contentShape(Rectangle())
    }

    private var isDue: Bool { line.charge.dueDate <= asOf }
    private var isOverdue: Bool { isDue && line.outstanding > 0 && DateMath.daysBetween(line.charge.dueDate, asOf) > graceDays }

    private var subtitle: String {
        var text = "Due " + Fmt.date(line.charge.dueDate)
        if line.paid > 0 { text += " · paid " + Fmt.inr(line.paid) }
        if isOverdue { text += " · \(DateMath.daysBetween(line.charge.dueDate, asOf)) days late" }
        return text
    }

    private var icon: String {
        if line.charge.waived { return "minus.circle" }
        if line.outstanding == 0 { return "checkmark.circle.fill" }
        if !isDue { return "clock" }
        if line.paid > 0 { return "circle.lefthalf.filled" }
        return "circle"
    }

    private var color: Color {
        if line.charge.waived { return .gray }
        if line.outstanding == 0 { return .green }
        if !isDue { return .gray }
        if isOverdue { return .red }
        return line.paid > 0 ? .orange : .blue
    }
}

// MARK: - Extra charges and discounts

enum ChargesSheet: Identifiable {
    case recurring(UUID?)
    case adjustment(AdjustmentKind)

    var id: String {
        switch self {
        case .recurring(let id): return "rc-" + (id?.uuidString ?? "new")
        case .adjustment(let kind): return "adj-" + kind.rawValue
        }
    }
}

struct ChargesView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var sheet: ChargesSheet? = nil
    @State private var pendingUndo: Adjustment? = nil

    private var undoBinding: Binding<Bool> {
        Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } })
    }

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text("This tenant was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        let oneOff = t.adjustments.filter { $0.kind == .extraCharge }.sorted { $0.date > $1.date }
        let changes = t.adjustments.filter { $0.kind != .extraCharge }.sorted { $0.date > $1.date }
        let horizon = DateMath.addMonths(12, to: Date())
        let titles = Dictionary(Ledger.charges(for: t, horizon: horizon).map { ($0.key, $0.title) }, uniquingKeysWith: { a, _ in a })
        return List {
            Section {
                ForEach(t.recurringCharges) { rc in
                    Button {
                        sheet = .recurring(rc.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rc.title.isEmpty ? "Charge" : rc.title)
                                Text(recurringPeriod(rc))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.inr(rc.amount) + " / month")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    sheet = .recurring(nil)
                } label: {
                    Label("Add a monthly charge (parking, maintenance…)", systemImage: "plus")
                }
            } header: {
                Text("Monthly extras")
            } footer: {
                Text("Billed with the rent every period, with the same part-month rules.")
            }

            Section {
                ForEach(oneOff) { a in
                    AdjustmentRow(adjustment: a, target: nil)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !a.isReversed {
                                Button {
                                    pendingUndo = a
                                } label: {
                                    Label("Cancel", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.red)
                            }
                        }
                }
                Button {
                    sheet = .adjustment(.extraCharge)
                } label: {
                    Label("Add a one-off charge", systemImage: "plus")
                }
            } header: {
                Text("One-off charges")
            }

            Section {
                ForEach(changes) { a in
                    AdjustmentRow(adjustment: a, target: a.periodKey.flatMap { titles[$0] })
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !a.isReversed {
                                Button {
                                    pendingUndo = a
                                } label: {
                                    Label("Undo", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.red)
                            }
                        }
                }
                Button {
                    sheet = .adjustment(.discount)
                } label: {
                    Label("Discount, waiver or correction", systemImage: "plus")
                }
            } header: {
                Text("Discounts, waivers and corrections")
            } footer: {
                Text("Swipe left to undo. Undone entries stay in the list, crossed out, for your records.")
            }
        }
        .navigationTitle("Extras and discounts")
        .confirmationDialog(undoTitle, isPresented: undoBinding, titleVisibility: .visible) {
            Button("Undo it", role: .destructive) {
                if let a = pendingUndo {
                    undo(a, t)
                }
                pendingUndo = nil
            }
        } message: {
            Text("The amount owed is worked out again without it. It stays in the list, crossed out.")
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .recurring(let id):
                RecurringChargeFormView(tenantID: tenantID, charge: t.recurringCharges.first { $0.id == id }).environmentObject(store)
            case .adjustment(let kind):
                AdjustmentFormView(tenantID: tenantID, kind: kind, presetKey: nil).environmentObject(store)
            }
        }
    }

    private var undoTitle: String {
        guard let a = pendingUndo else { return "Undo this?" }
        return a.kind == .extraCharge ? "Cancel this charge?" : "Undo this " + a.kind.label.lowercased() + "?"
    }

    private func recurringPeriod(_ rc: RecurringCharge) -> String {
        let from = rc.startDate.map { "From " + Fmt.date($0) } ?? "From the start of billing"
        let to = rc.endDate.map { " until " + Fmt.date($0) } ?? ""
        return from + to
    }

    private func undo(_ a: Adjustment, _ t: Tenant) {
        let what = a.kind.label + " " + Fmt.inr(abs(a.amount)) + (a.reason.isEmpty ? "" : " (" + a.reason + ")")
        store.updateTenant(t.id, log: "Adjustment undone", details: t.name + ": " + what) { tenant in
            if let i = tenant.adjustments.firstIndex(where: { $0.id == a.id }) {
                tenant.adjustments[i].isReversed = true
            }
        }
    }
}

struct AdjustmentRow: View {
    let adjustment: Adjustment
    let target: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .strikethrough(adjustment.isReversed)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if adjustment.kind != .waiver {
                Text(amountText)
                    .font(.subheadline)
                    .strikethrough(adjustment.isReversed)
            }
        }
    }

    private var title: String {
        switch adjustment.kind {
        case .extraCharge: return adjustment.title.isEmpty ? "Extra charge" : adjustment.title
        case .discount: return "Discount"
        case .waiver: return "Waived"
        case .correction: return "Correction"
        }
    }

    private var subtitle: String {
        var parts: [String] = [Fmt.date(adjustment.date)]
        if let target = target { parts.append(target) } else if adjustment.kind != .extraCharge { parts.append("Month no longer billed") }
        if !adjustment.reason.isEmpty { parts.append(adjustment.reason) }
        if adjustment.isReversed { parts.append("Undone") }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        switch adjustment.kind {
        case .discount: return "-" + Fmt.inr(abs(adjustment.amount))
        case .correction: return (adjustment.amount >= 0 ? "+" : "-") + Fmt.inr(abs(adjustment.amount))
        default: return Fmt.inr(adjustment.amount)
        }
    }
}

/// Adds a one-off charge, or a discount, waiver or correction for one billed month.
struct AdjustmentFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    let presetKey: String?

    @State private var kind: AdjustmentKind
    @State private var chargeKey: String
    @State private var amountText = ""
    @State private var increase = true
    @State private var title = ""
    @State private var date = Date()
    @State private var reason = ""
    @State private var payThis = false
    @State private var pendingUndo: Adjustment? = nil

    init(tenantID: UUID, kind: AdjustmentKind, presetKey: String?) {
        self.tenantID = tenantID
        self.presetKey = presetKey
        _kind = State(initialValue: kind)
        _chargeKey = State(initialValue: presetKey ?? "")
    }

    private var tenant: Tenant? { store.tenant(tenantID) }

    private var ledger: TenantLedger? { store.ledger(of: tenantID) }

    private var selectedLine: ChargeLine? {
        ledger?.lines.first { $0.charge.key == chargeKey }
    }

    private var canSave: Bool {
        switch kind {
        case .extraCharge:
            return (parseAmount(amountText) ?? 0) > 0
        case .waiver:
            return !chargeKey.isEmpty
        case .discount, .correction:
            return !chargeKey.isEmpty && (parseAmount(amountText) ?? 0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let line = selectedLine, presetKey != nil {
                    chargeInfo(line)
                }
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(kindChoices) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    if kind == .extraCharge {
                        TextField("What is it for? e.g. Electricity bill", text: $title)
                        MoneyField(title: "Amount", text: $amountText)
                        DatePicker("Due on", selection: $date, displayedComponents: .date)
                    } else {
                        if presetKey == nil {
                            Picker("Month", selection: $chargeKey) {
                                Text("Choose").tag("")
                                ForEach(ledger?.lines ?? []) { line in
                                    Text(line.charge.title).tag(line.charge.key)
                                }
                            }
                        }
                        if kind == .correction {
                            Picker("Change", selection: $increase) {
                                Text("Increase").tag(true)
                                Text("Reduce").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                        if kind != .waiver {
                            MoneyField(title: "Amount", text: $amountText)
                        }
                    }
                    TextField("Reason (optional)", text: $reason)
                } footer: {
                    Text(footerText)
                }
                if let line = selectedLine, presetKey != nil, line.outstanding > 0 {
                    Section {
                        Button {
                            payThis = true
                        } label: {
                            Label("Record a payment for this month", systemImage: "indianrupeesign.circle")
                        }
                    }
                }
                existingSection
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .keyboardDoneButton()
            .sheet(isPresented: $payThis) {
                PaymentFormView(tenantID: tenantID, presetChargeKey: chargeKey).environmentObject(store)
            }
            .confirmationDialog("Undo this adjustment?", isPresented: undoBinding, titleVisibility: .visible) {
                Button("Undo it", role: .destructive) {
                    if let a = pendingUndo {
                        undo(a)
                    }
                    pendingUndo = nil
                }
            }
        }
    }

    private var undoBinding: Binding<Bool> {
        Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } })
    }

    private var screenTitle: String {
        kind == .extraCharge ? "One-off charge" : "Adjust a charge"
    }

    private var kindChoices: [AdjustmentKind] {
        presetKey == nil ? AdjustmentKind.allCases : [.discount, .waiver, .correction]
    }

    private var footerText: String {
        switch kind {
        case .extraCharge: return "Added to what the tenant owes on the due date."
        case .discount: return "Reduces the chosen month's charge."
        case .waiver: return "The chosen month's charge becomes zero."
        case .correction: return "Changes the chosen month's charge up or down."
        }
    }

    private func chargeInfo(_ line: ChargeLine) -> some View {
        Section(line.charge.title) {
            LabeledContent("Due", value: Fmt.date(line.charge.dueDate))
            LabeledContent("Billed", value: Fmt.inr(line.charge.baseAmount))
            if line.charge.amount != line.charge.baseAmount || line.charge.waived {
                LabeledContent("After adjustments", value: Fmt.inr(line.charge.amount))
            }
            LabeledContent("Paid", value: Fmt.inr(line.paid))
            LabeledContent("Still owed", value: Fmt.inr(line.outstanding))
            ForEach(line.charge.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var existingSection: some View {
        let list = (tenant?.adjustments ?? []).filter { !chargeKey.isEmpty && $0.periodKey == chargeKey && !$0.isReversed }
        if !list.isEmpty {
            Section("Already applied to this month") {
                ForEach(list) { a in
                    HStack {
                        AdjustmentRow(adjustment: a, target: selectedLine?.charge.title)
                        Button("Undo") {
                            pendingUndo = a
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func undo(_ a: Adjustment) {
        guard let t = tenant else { return }
        store.updateTenant(tenantID, log: "Adjustment undone", details: t.name + ": " + a.kind.label) { tenant in
            if let i = tenant.adjustments.firstIndex(where: { $0.id == a.id }) {
                tenant.adjustments[i].isReversed = true
            }
        }
    }

    private func save() {
        guard let t = tenant else { return }
        var a = Adjustment()
        a.kind = kind
        a.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = parseAmount(amountText) ?? 0
        switch kind {
        case .extraCharge:
            a.title = title.trimmingCharacters(in: .whitespaces)
            a.amount = amount
            a.date = DateMath.day(date)
        case .discount:
            a.periodKey = chargeKey
            a.amount = amount
            a.date = Date()
        case .waiver:
            a.periodKey = chargeKey
            a.date = Date()
        case .correction:
            a.periodKey = chargeKey
            a.amount = increase ? amount : -amount
            a.date = Date()
        }
        let target = selectedLine?.charge.title ?? a.title
        let details = t.name + ": " + kind.label + (kind == .waiver ? "" : " " + Fmt.inr(abs(a.amount))) + (target.isEmpty ? "" : " · " + target)
        store.updateTenant(tenantID, log: kind == .extraCharge ? "Charge added" : "Rent adjusted", details: details) { tenant in
            tenant.adjustments.append(a)
        }
        dismiss()
    }
}

struct RecurringChargeFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    private let existing: RecurringCharge?

    @State private var title: String
    @State private var amountText: String
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var changeFrom: Date
    @State private var confirmDelete = false

    init(tenantID: UUID, charge: RecurringCharge?) {
        self.tenantID = tenantID
        existing = charge
        _title = State(initialValue: charge?.title ?? "Maintenance")
        _amountText = State(initialValue: amountString(charge?.amount ?? 0))
        _startDate = State(initialValue: charge?.startDate)
        _endDate = State(initialValue: charge?.endDate)
        _changeFrom = State(initialValue: DateMath.monthStart(DateMath.addMonths(1, to: Date())))
    }

    private var amountChanged: Bool {
        guard let old = existing, let amount = parseAmount(amountText) else { return false }
        return amount != old.amount
    }

    private var oldAmountText: String { Fmt.inr(existing?.amount ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Parking", text: $title)
                    MoneyField(title: "Amount per month", text: $amountText)
                }
                if amountChanged {
                    Section {
                        DatePicker("New amount from", selection: $changeFrom, displayedComponents: .date)
                    } footer: {
                        Text("Months due before this date keep " + oldAmountText + ". To correct the amount for every month, choose the day billing started.")
                    }
                }
                Section {
                    OptionalDatePicker(title: "Starts on a later date", date: $startDate)
                    OptionalDatePicker(title: "Stops on a date", date: $endDate)
                } footer: {
                    Text("A charge is billed for a month when it is in force on that month's due date. To end it, set a stop date; months already billed stay as they were.")
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete this charge", systemImage: "trash")
                        }
                    } footer: {
                        Text("Deleting removes it from past months too. Use a stop date instead to keep the history.")
                    }
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
            .confirmationDialog("Delete this monthly charge?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    private var screenTitle: String {
        existing == nil ? "Monthly charge" : "Edit monthly charge"
    }

    private func save() {
        if let old = existing, amountChanged, splitNeeded(old) {
            saveNewAmount(old)
            return
        }
        var rc = existing ?? RecurringCharge()
        rc.title = title.trimmingCharacters(in: .whitespaces)
        rc.amount = parseAmount(amountText) ?? 0
        rc.startDate = startDate.map { DateMath.day($0) }
        rc.endDate = endDate.map { DateMath.day($0) }
        let name = store.tenant(tenantID)?.name ?? ""
        store.updateTenant(tenantID, log: existing == nil ? "Monthly charge added" : "Monthly charge changed",
                           details: name + ": " + rc.title + " " + Fmt.inr(rc.amount)) { t in
            if let i = t.recurringCharges.firstIndex(where: { $0.id == rc.id }) {
                t.recurringCharges[i] = rc
            } else {
                t.recurringCharges.append(rc)
            }
        }
        dismiss()
    }

    /// A new amount from a date: the old charge ends the day before and a new one starts,
    /// so months already billed keep the old amount.
    private func splitNeeded(_ old: RecurringCharge) -> Bool {
        let t = store.tenant(tenantID)
        guard let begin = old.startDate ?? t?.billingStartDate ?? t?.startDate else { return true }
        return DateMath.day(changeFrom) > DateMath.day(begin)
    }

    private func saveNewAmount(_ old: RecurringCharge) {
        let from = DateMath.day(changeFrom)
        let name = title.trimmingCharacters(in: .whitespaces)
        let amount = parseAmount(amountText) ?? 0
        var ended = old
        ended.title = name
        ended.endDate = DateMath.addDays(-1, to: from)
        var next = RecurringCharge()
        next.title = name
        next.amount = amount
        next.startDate = from
        next.endDate = endDate.map { DateMath.day($0) }
        let tenantName = store.tenant(tenantID)?.name ?? ""
        let details = tenantName + ": " + name + " " + Fmt.inr(old.amount) + " → " + Fmt.inr(amount) + " from " + Fmt.date(from)
        store.updateTenant(tenantID, log: "Monthly charge changed", details: details) { t in
            if let i = t.recurringCharges.firstIndex(where: { $0.id == old.id }) {
                t.recurringCharges[i] = ended
            }
            t.recurringCharges.append(next)
        }
        dismiss()
    }

    private func delete() {
        guard let rc = existing else { return }
        let name = store.tenant(tenantID)?.name ?? ""
        store.updateTenant(tenantID, log: "Monthly charge deleted", details: name + ": " + rc.title) { t in
            t.recurringCharges.removeAll { $0.id == rc.id }
        }
        dismiss()
    }
}
