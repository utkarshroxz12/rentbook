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
        if existing != nil { return L("Edit payment", "Payment badlein") }
        return kind == .refund ? L("Refund to tenant", "Tenant ko wapas") : L("Record payment", "Payment record karein")
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
                    Button(L("Save", "Save karein")) { save() }
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
            MoneyField(title: kind == .refund ? L("Amount returned", "Wapas diya amount") : L("Amount received", "Mila amount"), text: $amountText)
            DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
            if existing?.method == .deposit {
                LabeledContent(L("Paid by", "Kisne diya"), value: PaymentMethod.deposit.label)
            } else {
                Picker(L("Paid by", "Kisne diya"), selection: $method) {
                    ForEach(PaymentMethod.selectable) { m in
                        Text(m.label).tag(m)
                    }
                }
            }
            TextField(L("Transaction or cheque number", "Transaction ya cheque number"), text: $reference)
                .textInputAutocapitalization(.characters)
            TextField(L("Note (optional)", "Note (optional)"), text: $note)
        } header: {
            Text(kind == .refund ? L("Refund", "Wapas") : L("Payment", "Payment"))
        } footer: {
            if kind == .refund {
                Text(L("Money you paid back to the tenant, for example rent paid twice by mistake. Deposit refunds go under Security deposit.", "Tenant ko wapas diya paisa, jaise galti se do baar diya rent. Deposit ka refund Security deposit mein karein."))
            } else if existing?.method == .deposit {
                Text(L("This was taken from the security deposit. A new amount or date changes the deposit entry too.", "Yeh security deposit se liya gaya tha. Naya amount ya tareekh deposit entry ko bhi badal dega."))
            }
        }
    }

    private func balanceText(_ l: TenantLedger) -> String {
        if l.net > 0 { return L("Owes ", "Baaki ") + Fmt.inr(l.net) }
        if l.net < 0 { return L("In credit ", "Credit mein ") + Fmt.inr(-l.net) }
        return L("Nothing owed", "Kuch baaki nahi")
    }

    @ViewBuilder
    private func allocationSection(_ base: TenantLedger) -> some View {
        let open = base.lines.filter { $0.outstanding > 0 }
        Section {
            Toggle(L("Choose which months this pays", "Chunein kaun se mahinon ka hai"), isOn: $manual)
            if manual {
                if open.isEmpty {
                    Text(L("Nothing is due. The payment will be kept as advance credit.", "Kuch baaki nahi. Payment advance credit mein rakha jayega."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(open) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.charge.title)
                                .font(.subheadline)
                            Text(L("Owes ", "Baaki ") + Fmt.inr(line.outstanding) + L(" · due ", " · tareekh ") + Fmt.date(line.charge.dueDate))
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
                Button(L("Fill oldest first", "Pehle purane bharein")) {
                    fillOldestFirst(base)
                }
                Text(allocationSummary(open))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Which months", "Kaun se mahine"))
        } footer: {
            Text(manual
                 ? L("Anything not assigned to a month settles the oldest dues; whatever is left becomes advance credit.", "Jo kisi mahine mein nahi laga woh purane baaki mein jayega; bacha hua advance credit banega.")
                 : L("Settles the oldest dues first. Anything extra is kept as advance credit and used for the next month automatically.", "Pehle purana baaki chukata hai. Zyada paisa advance credit mein rehta hai aur agle mahine apne aap lagta hai."))
        }
    }

    private func amountBinding(_ key: String) -> Binding<String> {
        Binding(get: { manualAmounts[key] ?? "" }, set: { manualAmounts[key] = $0 })
    }

    private func allocationSummary(_ open: [ChargeLine]) -> String {
        let total = parseAmount(amountText) ?? 0
        let assigned = open.reduce(0) { $0 + (parseAmount(manualAmounts[$1.charge.key] ?? "") ?? 0) }
        let left = total - assigned
        if left > 0 {
            return L("Assigned " + Fmt.inr(assigned) + ". The other " + Fmt.inr(left) + " goes to the oldest dues or advance credit.",
                     Fmt.inr(assigned) + " mahinon mein lage. Baaki " + Fmt.inr(left) + " purane baaki ya advance credit mein jayenge.")
        }
        if left < 0 {
            return L("Assigned " + Fmt.inr(assigned) + ", which is " + Fmt.inr(-left) + " more than the amount received.",
                     Fmt.inr(assigned) + " lagaye, jo mile amount se " + Fmt.inr(-left) + " zyada hai.")
        }
        return L("The whole amount is assigned.", "Poora amount lag gaya.")
    }

    @ViewBuilder
    private func previewSection(_ t: Tenant) -> some View {
        if let after = previewLedger(t) {
            let label = after.net > 0 ? L("Still owed", "Abhi bhi baaki") : (after.net < 0 ? L("Advance credit", "Advance credit") : "Balance")
            Section(L("After saving", "Save ke baad")) {
                LabeledContent(label, value: Fmt.inr(abs(after.net)))
                if let oldest = after.unpaidLines.first {
                    LabeledContent(L("Oldest unpaid", "Sabse purana baaki"), value: oldest.charge.title)
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
            Text(L("This payment was removed.", "Yeh payment hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ line: PaymentLine) -> some View {
        let p = line.payment
        let title: String = p.receiptNumber > 0 ? L("Receipt #\(p.receiptNumber)", "Raseed #\(p.receiptNumber)") : (p.kind == .refund ? L("Refund", "Wapas") : L("Payment", "Payment"))
        return List {
            summarySection(t, p)
            if !p.isReversed && p.kind == .payment {
                usedForSection(line)
            }
            AttachmentsSection(title: L("Proof of payment", "Payment ka saboot"), ids: p.attachmentIDs, category: "Payment proof") { id in
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
        .alert(L("Reverse this payment?", "Yeh payment wapas karein?"), isPresented: $askReverse) {
            TextField(L("Reason", "Kaaran"), text: $reverseReason)
            Button(L("Reverse", "Wapas karein"), role: .destructive) {
                store.reversePayment(paymentID, tenantID: tenantID, reason: reverseReason.trimmingCharacters(in: .whitespacesAndNewlines))
                reverseReason = ""
            }
            Button("Cancel", role: .cancel) {
                reverseReason = ""
            }
        } message: {
            Text(L("Use this for a payment entered by mistake. It stays in the history, crossed out, and no longer counts.", "Galti se daale payment ke liye. Yeh history mein kata hua rahega aur gina nahi jayega."))
        }
    }

    private func summarySection(_ t: Tenant, _ p: Payment) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.kind == .refund ? L("Refund to " + t.name, t.name + " ko wapas") : L("From " + t.name, t.name + " se"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(p.amount))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .strikethrough(p.isReversed)
                if p.isReversed {
                    Text(L("Reversed", "Wapas kiya") + (p.reversalReason.isEmpty ? "" : ": " + p.reversalReason))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
            LabeledContent(L("Date", "Tareekh"), value: Fmt.date(p.date))
            LabeledContent(L("Paid by", "Kisne diya"), value: p.method.label)
            if !p.reference.isEmpty {
                LabeledContent("Reference", value: p.reference)
            }
            if !p.note.isEmpty {
                Text(p.note)
            }
            if let edited = p.editedAt {
                LabeledContent(L("Last edited", "Aakhri badlav"), value: Fmt.dateTime(edited))
            }
        }
    }

    private func usedForSection(_ line: PaymentLine) -> some View {
        let balanceLabel: String = line.balanceAfter > 0 ? L("Balance after this payment", "Is payment ke baad baaki") : (line.balanceAfter < 0 ? L("Advance after this payment", "Is payment ke baad advance") : L("Balance after this payment", "Is payment ke baad baaki"))
        return Section {
            ForEach(Array(line.applications.enumerated()), id: \.offset) { item in
                LabeledContent(item.element.title, value: Fmt.inr(item.element.amount))
            }
            if line.unapplied > 0 {
                LabeledContent(L("Not used yet (advance credit)", "Abhi use nahi hua (advance credit)"), value: Fmt.inr(line.unapplied))
            }
            LabeledContent(balanceLabel, value: Fmt.inr(abs(line.balanceAfter)))
        } header: {
            Text(L("Used for", "Kis mein laga"))
        } footer: {
            if line.payment.manualAllocations != nil {
                Text(L("Months were chosen by hand when this payment was recorded.", "Payment record karte samay mahine khud chune gaye the."))
            }
        }
    }

    private func actionsSection(_ t: Tenant, _ line: PaymentLine) -> some View {
        Section {
            if line.payment.kind == .payment {
                Button {
                    shareReceipt(t, line)
                } label: {
                    Label(L("Share receipt as PDF", "Raseed PDF share karein"), systemImage: "doc.richtext")
                }
                Button {
                    sheet = .message(.receipt)
                } label: {
                    Label(L("Send receipt on WhatsApp", "Raseed WhatsApp par bhejein"), systemImage: "message")
                }
                if line.balanceAfter > 0 {
                    Button {
                        sheet = .message(.partialConfirmation)
                    } label: {
                        Label(L("Confirm part-payment on WhatsApp", "Aadha payment WhatsApp par confirm karein"), systemImage: "checkmark.message")
                    }
                }
            }
            Button {
                sheet = .edit
            } label: {
                Label(L("Edit payment", "Payment badlein"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                askReverse = true
            } label: {
                Label(L("Reverse payment", "Payment wapas karein"), systemImage: "arrow.uturn.backward")
            }
        } footer: {
            Text(L("Edits and reversals are recorded in Settings → Change history.", "Badlav aur wapsi Settings → Change history mein record hote hain."))
        }
    }

    private func shareReceipt(_ t: Tenant, _ line: PaymentLine) {
        if let url = PDFMaker.receipt(tenant: t, line: line, place: store.place(of: t), settings: store.settings) {
            sheet = .share(url)
        }
    }
}
