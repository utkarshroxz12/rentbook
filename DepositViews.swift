//  DepositViews.swift
//  Security deposit entries, deductions and refunds, using the deposit for
//  rent, and settling up when a tenant moves out.

import SwiftUI

enum DepositSheet: Identifiable {
    case entry(DepositEntryKind)
    case useForRent
    case share(URL)

    var id: String {
        switch self {
        case .entry(let kind): return "entry-" + kind.rawValue
        case .useForRent: return "use"
        case .share(let url): return "share-" + url.lastPathComponent
        }
    }
}

struct DepositView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var sheet: DepositSheet? = nil
    @State private var pendingUndo: DepositEntry? = nil

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
        let s = Ledger.deposit(of: t)
        let owed = store.ledger(of: tenantID)?.outstanding ?? 0
        return List {
            summarySection(s)
            entriesSection(t)
            actionsSection(t, held: s.held, owed: owed)
        }
        .navigationTitle("Security deposit")
        .confirmationDialog("Undo this entry?", isPresented: undoBinding, titleVisibility: .visible) {
            Button("Undo entry", role: .destructive) {
                if let entry = pendingUndo {
                    undo(entry, t)
                }
                pendingUndo = nil
            }
        } message: {
            Text(undoMessage)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .entry(let kind):
                DepositEntryFormView(tenantID: tenantID, kind: kind).environmentObject(store)
            case .useForRent:
                UseDepositFormView(tenantID: tenantID).environmentObject(store)
            case .share(let url):
                ShareSheet(items: [url])
            }
        }
    }

    private func summarySection(_ s: DepositSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Held now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(s.held))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .padding(.vertical, 4)
            LabeledContent("Received", value: Fmt.inr(s.received))
            LabeledContent("Added later", value: Fmt.inr(s.additional))
            LabeledContent("Deducted", value: Fmt.inr(s.deducted))
            LabeledContent("Refunded", value: Fmt.inr(s.refunded))
        } footer: {
            Text("The deposit is kept apart from rent. It only counts towards rent when you use it for dues.")
        }
    }

    private func entriesSection(_ t: Tenant) -> some View {
        Section {
            if t.deposits.isEmpty {
                Text("No deposit recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(t.deposits.sorted { $0.date > $1.date }) { entry in
                DepositEntryRow(entry: entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !entry.isReversed {
                            Button {
                                pendingUndo = entry
                            } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.red)
                        }
                    }
            }
        } header: {
            Text("Entries")
        } footer: {
            Text("Swipe left to undo an entry made by mistake. Undone entries stay in the list, crossed out.")
        }
    }

    private func actionsSection(_ t: Tenant, held: Int, owed: Int) -> some View {
        Section {
            Button {
                sheet = .entry(.received)
            } label: {
                Label("Record deposit received", systemImage: "plus")
            }
            Button {
                sheet = .entry(.additional)
            } label: {
                Label("Record an additional deposit", systemImage: "plus.circle")
            }
            Button {
                sheet = .entry(.deduction)
            } label: {
                Label("Deduct for damages or charges", systemImage: "minus.circle")
            }
            Button {
                sheet = .entry(.refund)
            } label: {
                Label("Refund deposit to the tenant", systemImage: "arrow.uturn.backward.circle")
            }
            if held > 0 && owed > 0 {
                Button {
                    sheet = .useForRent
                } label: {
                    Label("Use deposit to clear rent dues", systemImage: "arrow.right.circle")
                }
            }
            Button {
                if let url = PDFMaker.depositStatement(tenant: t, place: store.place(of: t), settings: store.settings) {
                    sheet = .share(url)
                }
            } label: {
                Label("Deposit statement (PDF)", systemImage: "doc.richtext")
            }
        }
    }

    private var undoMessage: String {
        guard let entry = pendingUndo else { return "" }
        if entry.linkedPaymentID != nil {
            return "This was used for rent, so the rent payment of " + Fmt.inr(entry.amount) + " is reversed too and that rent is owed again."
        }
        return entry.kind.label + " of " + Fmt.inr(entry.amount) + " no longer counts. It stays in the list, crossed out."
    }

    private func undo(_ entry: DepositEntry, _ t: Tenant) {
        if let paymentID = entry.linkedPaymentID {
            // Undoing the deduction also reverses the rent payment it paid for.
            store.reversePayment(paymentID, tenantID: t.id, reason: "Deposit adjustment undone")
            return
        }
        store.updateTenant(t.id, log: "Deposit entry undone", details: t.name + ": " + entry.kind.label + " " + Fmt.inr(entry.amount)) { tenant in
            if let i = tenant.deposits.firstIndex(where: { $0.id == entry.id }) {
                tenant.deposits[i].isReversed = true
            }
        }
    }
}

struct DepositEntryRow: View {
    let entry: DepositEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.label)
                    .strikethrough(entry.isReversed)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.subheadline)
                .strikethrough(entry.isReversed)
                .foregroundStyle(isIncoming ? Color.green : Color.primary)
        }
    }

    private var isIncoming: Bool {
        entry.kind == .received || entry.kind == .additional
    }

    private var amountText: String {
        (isIncoming ? "+" : "-") + Fmt.inr(entry.amount)
    }

    private var subtitle: String {
        var parts: [String] = [Fmt.date(entry.date)]
        if !entry.reason.isEmpty { parts.append(entry.reason) }
        if entry.isReversed { parts.append("undone") }
        return parts.joined(separator: " · ")
    }
}

struct DepositEntryFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    let kind: DepositEntryKind

    @State private var amountText = ""
    @State private var date = Date()
    @State private var reason = ""

    private var needsReason: Bool { kind == .deduction }
    private var reasonTitle: String { needsReason ? "Reason (required)" : "Note (optional)" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "Amount", text: $amountText)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField(reasonTitle, text: $reason)
                } footer: {
                    Text(takesOut ? footer + " Deposit held now: " + Fmt.inr(held) + "." : footer)
                }
            }
            .navigationTitle(kind.label)
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
        }
    }

    private var takesOut: Bool { kind == .deduction || kind == .refund }

    private var held: Int {
        guard let t = store.tenant(tenantID) else { return 0 }
        return Ledger.deposit(of: t).held
    }

    private var canSave: Bool {
        let amount = parseAmount(amountText) ?? 0
        let hasReason = !reason.trimmingCharacters(in: .whitespaces).isEmpty
        if takesOut && amount > held { return false }
        return amount > 0 && (!needsReason || hasReason)
    }

    private var footer: String {
        switch kind {
        case .received: return "The security deposit paid at the start of the tenancy."
        case .additional: return "Extra deposit paid later, for example when the rent went up."
        case .deduction: return "Money kept from the deposit, for example for damages. To use the deposit for unpaid rent, use “Use deposit to clear rent dues” instead."
        case .refund: return "Deposit money paid back to the tenant."
        }
    }

    private func save() {
        let amount = parseAmount(amountText) ?? 0
        let entry = DepositEntry(kind: kind, date: DateMath.day(date), amount: amount,
                                 reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
        let name = store.tenant(tenantID)?.name ?? ""
        store.updateTenant(tenantID, log: "Deposit: " + kind.label, details: name + ": " + Fmt.inr(amount)) { t in
            t.deposits.append(entry)
        }
        dismiss()
    }
}

struct UseDepositFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var prepared = false

    private var held: Int {
        guard let t = store.tenant(tenantID) else { return 0 }
        return Ledger.deposit(of: t).held
    }

    private var owed: Int {
        store.ledger(of: tenantID)?.outstanding ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Deposit held", value: Fmt.inr(held))
                    LabeledContent("Rent owed now", value: Fmt.inr(owed))
                }
                Section {
                    MoneyField(title: "Use from deposit", text: $amountText)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("This records a rent payment “From deposit” and takes the same amount out of the deposit. Undoing either one undoes both.")
                }
            }
            .navigationTitle("Use deposit for rent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
        }
    }

    private var isValid: Bool {
        let amount = parseAmount(amountText) ?? 0
        return amount > 0 && amount <= held
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let suggestion = min(held, owed)
        amountText = suggestion > 0 ? String(suggestion) : ""
    }

    private func save() {
        store.applyDepositToRent(tenantID: tenantID, amount: parseAmount(amountText) ?? 0, date: DateMath.day(date),
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Move out and settle

struct SettlementPreview {
    var owed = 0
    var credit = 0
    var held = 0
    var damages = 0
    var depositForRent = 0
    var remainingOwed = 0
    var depositRefund = 0
    var depositLeft = 0
}

struct SettlementView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var moveOut = Date()
    @State private var damagesText = ""
    @State private var damagesReason = ""
    @State private var useDeposit = true
    @State private var refundRest = true
    @State private var refundCredit = true
    @State private var refundMethod: PaymentMethod = .bank
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                if let t = store.tenant(tenantID) {
                    let p = preview(t)
                    Section {
                        DatePicker("Move-out date", selection: $moveOut, displayedComponents: .date)
                    } footer: {
                        Text("Rent stops on this date. The last month follows this tenant's part-month setting.")
                    }
                    rentSection(p)
                    depositSection(p)
                    resultSection(p)
                }
            }
            .navigationTitle("Move out and settle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirming = true }
                }
            }
            .keyboardDoneButton()
            .confirmationDialog("Mark this tenant as moved out?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Move out and settle") { confirm() }
            } message: {
                Text("The entries shown are recorded and the tenant is marked as vacated. Everything stays in their history.")
            }
        }
    }

    private func rentSection(_ p: SettlementPreview) -> some View {
        Section("Rent") {
            LabeledContent("Owed up to move-out", value: Fmt.inr(p.owed))
            if p.credit > 0 {
                LabeledContent("Paid in advance", value: Fmt.inr(p.credit))
                Toggle("Return the advance to the tenant", isOn: $refundCredit)
            }
        }
    }

    private func depositSection(_ p: SettlementPreview) -> some View {
        Section("Security deposit") {
            LabeledContent("Held", value: Fmt.inr(p.held))
            MoneyField(title: "Keep for damages", text: $damagesText)
            if (parseAmount(damagesText) ?? 0) > 0 {
                TextField("Reason for keeping it", text: $damagesReason)
            }
            Toggle("Use the deposit for unpaid rent", isOn: $useDeposit)
            Toggle("Refund what is left of the deposit", isOn: $refundRest)
            if refundRest || (refundCredit && p.credit > 0) {
                Picker("Refund by", selection: $refundMethod) {
                    ForEach(PaymentMethod.selectable) { m in
                        Text(m.label).tag(m)
                    }
                }
            }
        }
    }

    private func resultSection(_ p: SettlementPreview) -> some View {
        Section("After settling") {
            if p.depositForRent > 0 {
                LabeledContent("Deposit used for rent", value: Fmt.inr(p.depositForRent))
            }
            LabeledContent("Rent still owed", value: Fmt.inr(p.remainingOwed))
            LabeledContent("Deposit refund", value: Fmt.inr(p.depositRefund))
            if p.depositLeft > 0 {
                LabeledContent("Deposit still held", value: Fmt.inr(p.depositLeft))
            }
            if refundCredit && p.credit > 0 {
                LabeledContent("Advance returned", value: Fmt.inr(p.credit))
            }
        }
    }

    /// Works out the final position on a copy of the tenant with the move-out date set.
    private func preview(_ t: Tenant) -> SettlementPreview {
        var copy = t
        copy.endDate = DateMath.day(moveOut)
        copy.status = .vacated
        let asOf = max(DateMath.day(Date()), DateMath.addDays(40, to: DateMath.day(moveOut)))
        let ledger = Ledger.ledger(for: copy, asOf: asOf, graceDays: 0)
        var p = SettlementPreview()
        p.owed = max(0, ledger.net)
        p.credit = max(0, -ledger.net)
        p.held = max(0, Ledger.deposit(of: t).held)
        p.damages = min(parseAmount(damagesText) ?? 0, p.held)
        let available = p.held - p.damages
        p.depositForRent = useDeposit ? min(available, p.owed) : 0
        p.remainingOwed = p.owed - p.depositForRent
        p.depositRefund = refundRest ? available - p.depositForRent : 0
        p.depositLeft = available - p.depositForRent - p.depositRefund
        return p
    }

    private func confirm() {
        guard let t = store.tenant(tenantID) else { return }
        let p = preview(t)
        let day = DateMath.day(moveOut)
        let reason = damagesReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let method = refundMethod
        store.updateTenant(t.id, log: "Tenant moved out", details: t.name + " on " + Fmt.date(day)) { tenant in
            tenant.endDate = day
            tenant.status = .vacated
            if tenant.escalation != nil {
                Escalation.cancelSchedule(&tenant, note: "Tenant moved out")
            }
            if p.damages > 0 {
                tenant.deposits.append(DepositEntry(kind: .deduction, date: day, amount: p.damages,
                                                    reason: reason.isEmpty ? "Kept for damages" : reason))
            }
            if p.depositRefund > 0 {
                tenant.deposits.append(DepositEntry(kind: .refund, date: day, amount: p.depositRefund,
                                                    reason: "Refunded at move-out by " + method.label))
            }
        }
        if p.depositForRent > 0 {
            store.applyDepositToRent(tenantID: t.id, amount: p.depositForRent, date: day,
                                     note: "Settled from the deposit at move-out")
        }
        if refundCredit && p.credit > 0 {
            var refund = Payment()
            refund.kind = .refund
            refund.amount = p.credit
            refund.date = day
            refund.method = method
            refund.note = "Advance rent returned at move-out"
            store.recordPayment(refund, tenantID: t.id)
        }
        dismiss()
    }
}
