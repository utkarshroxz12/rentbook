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
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ l: TenantLedger) -> some View {
        List {
            Section {
                Picker(L("View", "Dekhein"), selection: $mode) {
                    Text(L("Months", "Mahine")).tag(0)
                    Text(L("History", "History")).tag(1)
                }
                .pickerStyle(.segmented)
                TileGrid {
                    StatTile(title: L("Billed so far", "Ab tak bana"), value: Fmt.inr(l.totalBilled))
                    StatTile(title: L("Paid so far", "Ab tak diya"), value: Fmt.inr(l.totalPaid), tint: .green)
                    StatTile(title: L("Outstanding", "Baaki"), value: Fmt.inr(l.outstanding), tint: l.outstanding > 0 ? .orange : .primary)
                    StatTile(title: L("Advance", "Advance"), value: Fmt.inr(l.credit))
                }
                if l.orphanAdjustments > 0 {
                    Text(L("\(l.orphanAdjustments) adjustment" + (l.orphanAdjustments == 1 ? " no longer matches a billed month" : "s no longer match a billed month")
                           + ", probably because the tenancy dates changed. See Extra charges and discounts.",
                           "\(l.orphanAdjustments) adjustment ab kisi bane mahine se mel nahi khate, shayad kirayedari ki tareekh badli hai. Extra charges aur chhoot dekhein."))
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
        .navigationTitle(L("Ledger", "Ledger"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sheet = .extraCharge
                    } label: {
                        Label(L("Add a one-off charge", "Ek baar ka charge jodein"), systemImage: "plus")
                    }
                    Button {
                        exportPDF(t)
                    } label: {
                        Label(L("Statement as PDF", "Statement PDF mein"), systemImage: "doc.richtext")
                    }
                    Button {
                        exportCSV(t)
                    } label: {
                        Label(L("Statement as spreadsheet (CSV)", "Statement spreadsheet (CSV) mein"), systemImage: "tablecells")
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
                Text(L("Nothing is owed right now.", "Abhi kuch baaki nahi."))
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
            Text(L("Open", "Baaki"))
        } footer: {
            Text(L("Oldest first. Tap a month to give a discount, waive it, correct it or pay it.", "Purane pehle. Chhoot dene, maaf karne, theek karne ya payment ke liye mahine par tap karein."))
        }
        Section(L("Coming up", "Aane wale")) {
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
                    Button(showAllPaid ? L("Show fewer", "Kam dikhayein") : L("Show all paid months", "Saare paid mahine dikhayein")) {
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
                Text(L("No charges or payments yet.", "Abhi koi charge ya payment nahi."))
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
            Text(L("Every charge and payment, newest first", "Har charge aur payment, naye pehle"))
        } footer: {
            Text(L("Balance is what the tenant owed after each line. A minus sign means advance credit.", "Balance batata hai har line ke baad tenant par kitna baaki tha. Minus matlab advance credit."))
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
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: L("Reversed payment", "Wapas kiya payment"),
                                         detail: p.reversalReason, debit: 0, credit: 0, paymentID: p.id, reversed: true))
            } else if p.kind == .refund {
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: L("Refund to tenant", "Tenant ko wapas"),
                                         detail: p.method.label, debit: p.amount, credit: 0, paymentID: p.id))
            } else {
                let receipt = p.receiptNumber > 0 ? L("Receipt #\(p.receiptNumber) · ", "Raseed #\(p.receiptNumber) · ") : ""
                items.append(LedgerEntry(id: "p-" + p.id.uuidString, date: day, title: L("Payment received", "Payment mila"),
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
                    Text(Fmt.inr(line.outstanding) + L(" left", " baaki"))
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
        var text = L("Due ", "Tareekh ") + Fmt.date(line.charge.dueDate)
        if line.paid > 0 { text += L(" · paid " + Fmt.inr(line.paid), " · " + Fmt.inr(line.paid) + " diya") }
        let late = DateMath.daysBetween(line.charge.dueDate, asOf)
        if isOverdue { text += L(" · \(late) days late", " · \(late) din der") }
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
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
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
                            Text(Fmt.inr(rc.amount) + L(" / month", " / mahina"))
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    sheet = .recurring(nil)
                } label: {
                    Label(L("Add a monthly charge (parking, maintenance…)", "Mahine ka charge jodein (parking, maintenance…)"), systemImage: "plus")
                }
            } header: {
                Text(L("Monthly extras", "Mahine ke extra"))
            } footer: {
                Text(L("Billed with the rent every period, with the same part-month rules.", "Har baar rent ke saath banta hai, wahi part-month rules ke saath."))
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
                    Label(L("Add a one-off charge", "Ek baar ka charge jodein"), systemImage: "plus")
                }
            } header: {
                Text(L("One-off charges", "Ek baar ke charges"))
            }

            Section {
                ForEach(changes) { a in
                    AdjustmentRow(adjustment: a, target: a.periodKey.flatMap { titles[$0] })
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !a.isReversed {
                                Button {
                                    pendingUndo = a
                                } label: {
                                    Label(L("Undo", "Wapas lein"), systemImage: "arrow.uturn.backward")
                                }
                                .tint(.red)
                            }
                        }
                }
                Button {
                    sheet = .adjustment(.discount)
                } label: {
                    Label(L("Discount, waiver or correction", "Chhoot, maafi ya sudhaar"), systemImage: "plus")
                }
            } header: {
                Text(L("Discounts, waivers and corrections", "Chhoot, maafi aur sudhaar"))
            } footer: {
                Text(L("Swipe left to undo. Undone entries stay in the list, crossed out, for your records.", "Wapas lene ke liye left swipe karein. Wapas li entries record ke liye list mein kati hui rehti hain."))
            }
        }
        .navigationTitle(L("Extras and discounts", "Extra aur chhoot"))
        .confirmationDialog(undoTitle, isPresented: undoBinding, titleVisibility: .visible) {
            Button(L("Undo it", "Wapas lein"), role: .destructive) {
                if let a = pendingUndo {
                    undo(a, t)
                }
                pendingUndo = nil
            }
        } message: {
            Text(L("The amount owed is worked out again without it. It stays in the list, crossed out.", "Iske bina baaki dobara nikala jayega. Yeh list mein kata hua rahega."))
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
        guard let a = pendingUndo else { return L("Undo this?", "Ise wapas lein?") }
        return a.kind == .extraCharge ? L("Cancel this charge?", "Yeh charge radd karein?")
            : L("Undo this " + a.kind.label.lowercased() + "?", a.kind.label + " wapas lein?")
    }

    private func recurringPeriod(_ rc: RecurringCharge) -> String {
        let from = rc.startDate.map { L("From " + Fmt.date($0), Fmt.date($0) + " se") } ?? L("From the start of billing", "Billing ki shuruaat se")
        let to = rc.endDate.map { L(" until " + Fmt.date($0), ", " + Fmt.date($0) + " tak") } ?? ""
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
        case .discount: return L("Discount", "Chhoot")
        case .waiver: return L("Waived", "Maaf kiya")
        case .correction: return L("Correction", "Sudhaar")
        }
    }

    private var subtitle: String {
        var parts: [String] = [Fmt.date(adjustment.date)]
        if let target = target { parts.append(target) } else if adjustment.kind != .extraCharge { parts.append(L("Month no longer billed", "Yeh mahina ab nahi banta")) }
        if !adjustment.reason.isEmpty { parts.append(adjustment.reason) }
        if adjustment.isReversed { parts.append(L("Undone", "Wapas liya")) }
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
                    Picker(L("Type", "Kism"), selection: $kind) {
                        ForEach(kindChoices) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    if kind == .extraCharge {
                        TextField(L("What is it for? e.g. Electricity bill", "Kis cheez ka? jaise Bijli bill"), text: $title)
                        MoneyField(title: "Amount", text: $amountText)
                        DatePicker(L("Due on", "Kab dena hai"), selection: $date, displayedComponents: .date)
                    } else {
                        if presetKey == nil {
                            Picker(L("Month", "Mahina"), selection: $chargeKey) {
                                Text(L("Choose", "Chunein")).tag("")
                                ForEach(ledger?.lines ?? []) { line in
                                    Text(line.charge.title).tag(line.charge.key)
                                }
                            }
                        }
                        if kind == .correction {
                            Picker(L("Change", "Badlav"), selection: $increase) {
                                Text(L("Increase", "Badhayein")).tag(true)
                                Text(L("Reduce", "Ghatayein")).tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                        if kind != .waiver {
                            MoneyField(title: "Amount", text: $amountText)
                        }
                    }
                    TextField(L("Reason (optional)", "Kaaran (optional)"), text: $reason)
                } footer: {
                    Text(footerText)
                }
                if let line = selectedLine, presetKey != nil, line.outstanding > 0 {
                    Section {
                        Button {
                            payThis = true
                        } label: {
                            Label(L("Record a payment for this month", "Is mahine ka payment record karein"), systemImage: "indianrupeesign.circle")
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
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(!canSave)
                }
            }
            .keyboardDoneButton()
            .sheet(isPresented: $payThis) {
                PaymentFormView(tenantID: tenantID, presetChargeKey: chargeKey).environmentObject(store)
            }
            .confirmationDialog(L("Undo this adjustment?", "Yeh adjustment wapas lein?"), isPresented: undoBinding, titleVisibility: .visible) {
                Button(L("Undo it", "Wapas lein"), role: .destructive) {
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
        kind == .extraCharge ? L("One-off charge", "Ek baar ka charge") : L("Adjust a charge", "Charge badlein")
    }

    private var kindChoices: [AdjustmentKind] {
        presetKey == nil ? AdjustmentKind.allCases : [.discount, .waiver, .correction]
    }

    private var footerText: String {
        switch kind {
        case .extraCharge: return L("Added to what the tenant owes on the due date.", "Due date par tenant ke baaki mein judega.")
        case .discount: return L("Reduces the chosen month's charge.", "Chune mahine ka charge kam karta hai.")
        case .waiver: return L("The chosen month's charge becomes zero.", "Chune mahine ka charge zero ho jata hai.")
        case .correction: return L("Changes the chosen month's charge up or down.", "Chune mahine ka charge badhata ya ghatata hai.")
        }
    }

    private func chargeInfo(_ line: ChargeLine) -> some View {
        Section(line.charge.title) {
            LabeledContent(L("Due", "Dena hai"), value: Fmt.date(line.charge.dueDate))
            LabeledContent(L("Billed", "Bill"), value: Fmt.inr(line.charge.baseAmount))
            if line.charge.amount != line.charge.baseAmount || line.charge.waived {
                LabeledContent(L("After adjustments", "Adjustment ke baad"), value: Fmt.inr(line.charge.amount))
            }
            LabeledContent("Paid", value: Fmt.inr(line.paid))
            LabeledContent(L("Still owed", "Abhi bhi baaki"), value: Fmt.inr(line.outstanding))
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
            Section(L("Already applied to this month", "Is mahine par pehle se laga")) {
                ForEach(list) { a in
                    HStack {
                        AdjustmentRow(adjustment: a, target: selectedLine?.charge.title)
                        Button(L("Undo", "Wapas lein")) {
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
                    TextField(L("Name, e.g. Parking", "Naam, jaise Parking"), text: $title)
                    MoneyField(title: L("Amount per month", "Har mahine ka amount"), text: $amountText)
                }
                if amountChanged {
                    Section {
                        DatePicker(L("New amount from", "Naya amount kab se"), selection: $changeFrom, displayedComponents: .date)
                    } footer: {
                        Text(L("Months due before this date keep " + oldAmountText + ". To correct the amount for every month, choose the day billing started.",
                               "Is tareekh se pehle ke mahine " + oldAmountText + " par rahenge. Har mahine ka amount theek karna ho to billing shuru hone ki tareekh chunein."))
                    }
                }
                Section {
                    OptionalDatePicker(title: L("Starts on a later date", "Baad ki tareekh se shuru"), date: $startDate)
                    OptionalDatePicker(title: L("Stops on a date", "Kisi tareekh par band"), date: $endDate)
                } footer: {
                    Text(L("A charge is billed for a month when it is in force on that month's due date. To end it, set a stop date; months already billed stay as they were.", "Charge us mahine banta hai jab woh mahine ki due date par lagu ho. Band karne ke liye stop date daalein; bane hue mahine waise hi rahenge."))
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(L("Delete this charge", "Yeh charge delete karein"), systemImage: "trash")
                        }
                    } footer: {
                        Text(L("Deleting removes it from past months too. Use a stop date instead to keep the history.", "Delete karne se pichhle mahinon se bhi hat jayega. History rakhni ho to stop date use karein."))
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
                    Button(L("Save", "Save karein")) { save() }
                        .disabled((parseAmount(amountText) ?? 0) <= 0)
                }
            }
            .keyboardDoneButton()
            .confirmationDialog(L("Delete this monthly charge?", "Yeh mahine ka charge delete karein?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    private var screenTitle: String {
        existing == nil ? L("Monthly charge", "Mahine ka charge") : L("Edit monthly charge", "Mahine ka charge badlein")
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
