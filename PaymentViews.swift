//  PaymentViews.swift
//  Recording, editing and reversing payments and refunds; payment receipts.

import SwiftUI

struct PaymentFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    private let existing: Payment?
    private let kind: PaymentKind
    private let presetChargeKey: String?

    @State private var amountText = ""
    @State private var date = Date()
    @State private var method: PaymentMethod = .upi
    @State private var reference = ""
    @State private var note = ""
    @State private var manual = false
    @State private var manualAmounts: [String: String] = [:]
    @State private var prepared = false

    init(tenantID: UUID, existing: Payment? = nil, kind: PaymentKind = .payment, presetChargeKey: String? = nil) {
        self.tenantID = tenantID
        self.existing = existing
        self.kind = existing?.kind ?? kind
        self.presetChargeKey = presetChargeKey
    }

    private var screenTitle: String {
        if existing != nil { return "Edit payment" }
        return kind == .refund ? "Refund to tenant" : "Record payment"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let t = store.tenant(tenantID) {
                    let base = baseLedger(t)
                    Section {
                        LabeledContent(t.name, value: balanceText(base))
                    }
                    detailsSection
                    if kind == .payment {
                        allocationSection(base)
                    }
                    previewSection(t)
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
            .onAppear(perform: prepare)
            .onChange(of: manual) { on in
                if on && manualAmounts.isEmpty, let t = store.tenant(tenantID) {
                    fillOldestFirst(baseLedger(t))
                }
            }
        }
    }

    private var canSave: Bool {
        let amount = parseAmount(amountText) ?? 0
        guard amount > 0 else { return false }
        if let p = existing, p.method == .deposit, let t = store.tenant(tenantID) {
            // Can't take more from the deposit than it holds.
            return amount <= Ledger.deposit(of: t).held + p.amount
        }
        return true
    }

    private var detailsSection: some View {
        Section {
            MoneyField(title: kind == .refund ? "Amount returned" : "Amount received", text: $amountText)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            if existing?.method == .deposit {
                LabeledContent("Paid by", value: PaymentMethod.deposit.label)
            } else {
                Picker("Paid by", selection: $method) {
                    ForEach(PaymentMethod.selectable) { m in
                        Text(m.label).tag(m)
                    }
                }
            }
            TextField("Transaction or cheque number", text: $reference)
                .textInputAutocapitalization(.characters)
            TextField("Note (optional)", text: $note)
        } header: {
            Text(kind == .refund ? "Refund" : "Payment")
        } footer: {
            if kind == .refund {
                Text("Money you paid back to the tenant, for example rent paid twice by mistake. Deposit refunds go under Security deposit.")
            } else if existing?.method == .deposit {
                Text("This was taken from the security deposit. A new amount or date changes the deposit entry too.")
            }
        }
    }

    private func balanceText(_ l: TenantLedger) -> String {
        if l.net > 0 { return "Owes " + Fmt.inr(l.net) }
        if l.net < 0 { return "In credit " + Fmt.inr(-l.net) }
        return "Nothing owed"
    }

    @ViewBuilder
    private func allocationSection(_ base: TenantLedger) -> some View {
        let open = base.lines.filter { $0.outstanding > 0 }
        Section {
            Toggle("Choose which months this pays", isOn: $manual)
            if manual {
                if open.isEmpty {
                    Text("Nothing is due. The payment will be kept as advance credit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(open) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.charge.title)
                                .font(.subheadline)
                            Text("Owes " + Fmt.inr(line.outstanding) + " · due " + Fmt.date(line.charge.dueDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("0", text: amountBinding(line.charge.key))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                    }
                }
                Button("Fill oldest first") {
                    fillOldestFirst(base)
                }
                Text(allocationSummary(open))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Which months")
        } footer: {
            Text(manual
                 ? "Anything not assigned to a month settles the oldest dues; whatever is left becomes advance credit."
                 : "Settles the oldest dues first. Anything extra is kept as advance credit and used for the next month automatically.")
        }
    }

    private func amountBinding(_ key: String) -> Binding<String> {
        Binding(get: { manualAmounts[key] ?? "" }, set: { manualAmounts[key] = $0 })
    }

    private func allocationSummary(_ open: [ChargeLine]) -> String {
        let total = parseAmount(amountText) ?? 0
        let assigned = open.reduce(0) { $0 + (parseAmount(manualAmounts[$1.charge.key] ?? "") ?? 0) }
        let left = total - assigned
        if left > 0 { return "Assigned " + Fmt.inr(assigned) + ". The other " + Fmt.inr(left) + " goes to the oldest dues or advance credit." }
        if left < 0 { return "Assigned " + Fmt.inr(assigned) + ", which is " + Fmt.inr(-left) + " more than the amount received." }
        return "The whole amount is assigned."
    }

    @ViewBuilder
    private func previewSection(_ t: Tenant) -> some View {
        if let after = previewLedger(t) {
            let label = after.net > 0 ? "Still owed" : (after.net < 0 ? "Advance credit" : "Balance")
            Section("After saving") {
                LabeledContent(label, value: Fmt.inr(abs(after.net)))
                if let oldest = after.unpaidLines.first {
                    LabeledContent("Oldest unpaid", value: oldest.charge.title)
                }
            }
        }
    }

    // MARK: Working it out

    private func baseLedger(_ t: Tenant) -> TenantLedger {
        var copy = t
        if let p = existing {
            copy.payments.removeAll { $0.id == p.id }
        }
        return store.freshLedger(for: copy)
    }

    private func previewLedger(_ t: Tenant) -> TenantLedger? {
        guard let amount = parseAmount(amountText), amount > 0 else { return nil }
        var copy = t
        if let p = existing {
            copy.payments.removeAll { $0.id == p.id }
        }
        copy.payments.append(buildPayment(amount: amount, base: baseLedger(t)))
        return store.freshLedger(for: copy)
    }

    private func fillOldestFirst(_ base: TenantLedger) {
        let total = parseAmount(amountText) ?? 0
        let suggestion = Ledger.suggestAllocation(amount: total, lines: base.lines)
        var texts: [String: String] = [:]
        for (key, value) in suggestion {
            texts[key] = String(value)
        }
        manualAmounts = texts
    }

    private func buildPayment(amount: Int, base: TenantLedger) -> Payment {
        var p = existing ?? Payment()
        p.kind = kind
        p.amount = amount
        p.date = date
        p.method = method
        p.reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        p.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .payment && manual {
            var allocations: [Allocation] = []
            for line in base.lines where line.outstanding > 0 {
                if let value = parseAmount(manualAmounts[line.charge.key] ?? ""), value > 0 {
                    allocations.append(Allocation(chargeKey: line.charge.key, amount: value))
                }
            }
            p.manualAllocations = allocations.isEmpty ? nil : allocations
        } else {
            p.manualAllocations = nil
        }
        return p
    }

    private func prepare() {
        guard !prepared, let t = store.tenant(tenantID) else { return }
        prepared = true
        let base = baseLedger(t)
        if let p = existing {
            amountText = String(p.amount)
            date = p.date
            method = p.method
            reference = p.reference
            note = p.note
            if let chosen = p.manualAllocations {
                manual = true
                var texts: [String: String] = [:]
                for a in chosen {
                    texts[a.chargeKey] = String(a.amount)
                }
                manualAmounts = texts
            }
            return
        }
        method = t.preferredMethod ?? .upi
        if kind == .refund {
            amountText = base.credit > 0 ? String(base.credit) : ""
            return
        }
        if let key = presetChargeKey, let line = base.lines.first(where: { $0.charge.key == key }) {
            amountText = String(line.outstanding)
            manualAmounts = [key: String(line.outstanding)]
            manual = true
            return
        }
        let suggested = base.net > 0 ? base.net : Ledger.currentRent(of: t)
        amountText = suggested > 0 ? String(suggested) : ""
        if !store.settings.autoAllocate {
            manual = true
            fillOldestFirst(base)
        }
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0, let t = store.tenant(tenantID) else { return }
        let p = buildPayment(amount: amount, base: baseLedger(t))
        if existing != nil {
            store.editPayment(p, tenantID: tenantID)
        } else {
            store.recordPayment(p, tenantID: tenantID)
        }
        dismiss()
    }
}

// MARK: - Payment details and receipt

enum PaymentSheet: Identifiable {
    case edit
    case message(MessageKind)
    case share(URL)

    var id: String {
        switch self {
        case .edit: return "edit"
        case .message(let kind): return "message-" + kind.rawValue
        case .share(let url): return "share-" + url.lastPathComponent
        }
    }
}

struct PaymentDetailView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    let paymentID: UUID

    @State private var sheet: PaymentSheet? = nil
    @State private var askReverse = false
    @State private var reverseReason = ""

    var body: some View {
        if let t = store.tenant(tenantID), let l = store.ledger(of: tenantID),
           let line = l.payments.first(where: { $0.payment.id == paymentID }) {
            content(t, line)
        } else {
            Text("This payment was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ line: PaymentLine) -> some View {
        let p = line.payment
        let title: String = p.receiptNumber > 0 ? "Receipt #\(p.receiptNumber)" : (p.kind == .refund ? "Refund" : "Payment")
        return List {
            summarySection(t, p)
            if !p.isReversed && p.kind == .payment {
                usedForSection(line)
            }
            AttachmentsSection(title: "Proof of payment", ids: p.attachmentIDs, category: "Payment proof") { id in
                store.updateTenant(tenantID) { tenant in
                    if let i = tenant.payments.firstIndex(where: { $0.id == paymentID }) {
                        tenant.payments[i].attachmentIDs.append(id)
                    }
                }
            }
            if !p.isReversed {
                actionsSection(t, line)
            }
        }
        .attachmentHost()
        .navigationTitle(title)
        .sheet(item: $sheet) { which in
            switch which {
            case .edit:
                PaymentFormView(tenantID: tenantID, existing: p).environmentObject(store)
            case .message(let kind):
                MessageComposerView(tenantID: tenantID, kind: kind, paymentID: paymentID).environmentObject(store)
            case .share(let url):
                ShareSheet(items: [url])
            }
        }
        .alert("Reverse this payment?", isPresented: $askReverse) {
            TextField("Reason", text: $reverseReason)
            Button("Reverse", role: .destructive) {
                store.reversePayment(paymentID, tenantID: tenantID, reason: reverseReason.trimmingCharacters(in: .whitespacesAndNewlines))
                reverseReason = ""
            }
            Button("Cancel", role: .cancel) {
                reverseReason = ""
            }
        } message: {
            Text("Use this for a payment entered by mistake. It stays in the history, crossed out, and no longer counts.")
        }
    }

    private func summarySection(_ t: Tenant, _ p: Payment) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.kind == .refund ? "Refund to " + t.name : "From " + t.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(p.amount))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .strikethrough(p.isReversed)
                if p.isReversed {
                    Text("Reversed" + (p.reversalReason.isEmpty ? "" : ": " + p.reversalReason))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Date", value: Fmt.date(p.date))
            LabeledContent("Paid by", value: p.method.label)
            if !p.reference.isEmpty {
                LabeledContent("Reference", value: p.reference)
            }
            if !p.note.isEmpty {
                Text(p.note)
            }
            if let edited = p.editedAt {
                LabeledContent("Last edited", value: Fmt.dateTime(edited))
            }
        }
    }

    private func usedForSection(_ line: PaymentLine) -> some View {
        let balanceLabel: String = line.balanceAfter > 0 ? "Balance after this payment" : (line.balanceAfter < 0 ? "Advance after this payment" : "Balance after this payment")
        return Section {
            ForEach(Array(line.applications.enumerated()), id: \.offset) { item in
                LabeledContent(item.element.title, value: Fmt.inr(item.element.amount))
            }
            if line.unapplied > 0 {
                LabeledContent("Not used yet (advance credit)", value: Fmt.inr(line.unapplied))
            }
            LabeledContent(balanceLabel, value: Fmt.inr(abs(line.balanceAfter)))
        } header: {
            Text("Used for")
        } footer: {
            if line.payment.manualAllocations != nil {
                Text("Months were chosen by hand when this payment was recorded.")
            }
        }
    }

    private func actionsSection(_ t: Tenant, _ line: PaymentLine) -> some View {
        Section {
            if line.payment.kind == .payment {
                Button {
                    shareReceipt(t, line)
                } label: {
                    Label("Share receipt as PDF", systemImage: "doc.richtext")
                }
                Button {
                    sheet = .message(.receipt)
                } label: {
                    Label("Send receipt on WhatsApp", systemImage: "message")
                }
                if line.balanceAfter > 0 {
                    Button {
                        sheet = .message(.partialConfirmation)
                    } label: {
                        Label("Confirm part-payment on WhatsApp", systemImage: "checkmark.message")
                    }
                }
            }
            Button {
                sheet = .edit
            } label: {
                Label("Edit payment", systemImage: "pencil")
            }
            Button(role: .destructive) {
                askReverse = true
            } label: {
                Label("Reverse payment", systemImage: "arrow.uturn.backward")
            }
        } footer: {
            Text("Edits and reversals are recorded in Settings → Change history.")
        }
    }

    private func shareReceipt(_ t: Tenant, _ line: PaymentLine) {
        if let url = PDFMaker.receipt(tenant: t, line: line, place: store.place(of: t), settings: store.settings) {
            sheet = .share(url)
        }
    }
}
