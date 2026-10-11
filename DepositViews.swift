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
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
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
        .confirmationDialog(L("Undo this entry?", "Yeh entry wapas lein?"), isPresented: undoBinding, titleVisibility: .visible) {
            Button(L("Undo entry", "Entry wapas lein"), role: .destructive) {
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
                Text(L("Held now", "Abhi jama"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(s.held))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .padding(.vertical, 4)
            LabeledContent(L("Received", "Mila"), value: Fmt.inr(s.received))
            LabeledContent(L("Added later", "Baad mein joda"), value: Fmt.inr(s.additional))
            LabeledContent(L("Deducted", "Kata"), value: Fmt.inr(s.deducted))
            LabeledContent(L("Refunded", "Wapas diya"), value: Fmt.inr(s.refunded))
        } footer: {
            Text(L("The deposit is kept apart from rent. It only counts towards rent when you use it for dues.", "Deposit rent se alag rakha jata hai. Yeh rent mein tabhi ginta hai jab aap ise baaki ke liye use karein."))
        }
    }

    private func entriesSection(_ t: Tenant) -> some View {
        Section {
            if t.deposits.isEmpty {
                Text(L("No deposit recorded yet.", "Abhi koi deposit record nahi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(t.deposits.sorted { $0.date > $1.date }) { entry in
                DepositEntryRow(entry: entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !entry.isReversed {
                            Button {
                                pendingUndo = entry
                            } label: {
                                Label(L("Undo", "Wapas lein"), systemImage: "arrow.uturn.backward")
                            }
                            .tint(.red)
                        }
                    }
            }
        } header: {
            Text("Entries")
        } footer: {
            Text(L("Swipe left to undo an entry made by mistake. Undone entries stay in the list, crossed out.", "Galti se bani entry wapas lene ke liye left swipe karein. Wapas li entries list mein kati hui rahti hain."))
        }
    }

    private func actionsSection(_ t: Tenant, held: Int, owed: Int) -> some View {
        Section {
            Button {
                sheet = .entry(.received)
            } label: {
                Label(L("Record deposit received", "Mila deposit record karein"), systemImage: "plus")
            }
            Button {
                sheet = .entry(.additional)
            } label: {
                Label(L("Record an additional deposit", "Aur deposit record karein"), systemImage: "plus.circle")
            }
            Button {
                sheet = .entry(.deduction)
            } label: {
                Label(L("Deduct for damages or charges", "Nuksaan ya charges ke liye katein"), systemImage: "minus.circle")
            }
            Button {
                sheet = .entry(.refund)
            } label: {
                Label(L("Refund deposit to the tenant", "Tenant ko deposit wapas karein"), systemImage: "arrow.uturn.backward.circle")
            }
            if held > 0 && owed > 0 {
                Button {
                    sheet = .useForRent
                } label: {
                    Label(L("Use deposit to clear rent dues", "Baaki rent deposit se chukayein"), systemImage: "arrow.right.circle")
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
            return L("This was used for rent, so the rent payment of " + Fmt.inr(entry.amount) + " is reversed too and that rent is owed again.",
                     "Yeh rent mein use hua tha, isliye " + Fmt.inr(entry.amount) + " ka rent payment bhi wapas hoga aur woh rent phir se baaki hoga.")
        }
        return L(entry.kind.label + " of " + Fmt.inr(entry.amount) + " no longer counts. It stays in the list, crossed out.",
                 entry.kind.label + " " + Fmt.inr(entry.amount) + " ab nahi ginega. Yeh list mein kata hua rahega.")
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
        if entry.isReversed { parts.append(L("undone", "wapas liya")) }
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
    private var reasonTitle: String { needsReason ? L("Reason (required)", "Kaaran (zaroori)") : "Note (optional)" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "Amount", text: $amountText)
                    DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
                    TextField(reasonTitle, text: $reason)
                } footer: {
                    Text(takesOut ? concat(footer, L(" Deposit held now: ", " Abhi jama deposit: "), Fmt.inr(held), ".") : footer)
                }
            }
            .navigationTitle(kind.label)
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
        case .received: return L("The security deposit paid at the start of the tenancy.", "Kirayedari ki shuruaat mein diya security deposit.")
        case .additional: return L("Extra deposit paid later, for example when the rent went up.", "Baad mein diya extra deposit, jaise rent badhne par.")
        case .deduction: return L("Money kept from the deposit, for example for damages. To use the deposit for unpaid rent, use “Use deposit to clear rent dues” instead.", "Deposit se rakha gaya paisa, jaise nuksaan ke liye. Baaki rent ke liye deposit use karna ho to “Baaki rent deposit se chukayein” use karein.")
        case .refund: return L("Deposit money paid back to the tenant.", "Tenant ko wapas diya deposit.")
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
                    LabeledContent(L("Deposit held", "Jama deposit"), value: Fmt.inr(held))
                    LabeledContent(L("Rent owed now", "Abhi baaki rent"), value: Fmt.inr(owed))
                }
                Section {
                    MoneyField(title: L("Use from deposit", "Deposit se lein"), text: $amountText)
                    DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text(L("This records a rent payment “From deposit” and takes the same amount out of the deposit. Undoing either one undoes both.", "Isse “Deposit se” rent payment record hota hai aur utna hi deposit se kat jata hai. Ek ko wapas lene se dono wapas ho jaate hain."))
                }
            }
            .navigationTitle(L("Use deposit for rent", "Deposit se rent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
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
    var utility = 0
}

/// A final meter reading at move-out and the bill it makes.
struct FinalMeterBill {
    var kind: MeterKind
    var previous: MeterReading
    var reading: Double
    var rate: Double
    var units: Double
    var amount: Int
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
    @State private var electricityText = ""
    @State private var waterText = ""
    @State private var keys: [KeyItem] = []
    @State private var condition = ""
    @State private var notes = ""
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            Form {
                if let t = store.tenant(tenantID) {
                    let bills = meterBills(t)
                    let p = preview(t, bills)
                    Section {
                        DatePicker(L("Move-out date", "Ghar chhodne ki tareekh"), selection: $moveOut, displayedComponents: .date)
                    } footer: {
                        Text(L("Rent stops on this date. The last month follows this tenant's part-month setting.",
                               "Is tareekh se rent band. Aakhri mahina tenant ki part-month setting ke hisaab se."))
                    }
                    metersSection(bills)
                    handoverSection
                    rentSection(p)
                    depositSection(p)
                    resultSection(p)
                    Section {
                        TextField(L("Notes for the settlement", "Hisaab ke notes"), text: $notes, axis: .vertical)
                            .lineLimit(1...4)
                    }
                }
            }
            .navigationTitle(L("Move out and settle", "Move out aur final hisaab"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Confirm", "Pakka karein")) { confirming = true }
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .confirmationDialog(L("Mark this tenant as moved out?", "Is tenant ko moved out mark karein?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(L("Move out and settle", "Move out aur hisaab karein")) { confirm() }
            } message: {
                Text(L("The entries shown are recorded and the tenant is marked as vacated. Everything stays in their history.",
                       "Dikhayi gayi entries record hongi aur tenant vacated mark hoga. Sab unki history mein rahega."))
            }
        }
    }

    private func prepare() {
        guard !prepared, let t = store.tenant(tenantID) else { return }
        prepared = true
        if let moveIn = store.handover(.moveIn, of: t) {
            keys = moveIn.keys.map { KeyItem(name: $0.name, count: $0.count, returned: $0.count) }
        }
    }

    private func meterBills(_ t: Tenant) -> [FinalMeterBill] {
        var out: [FinalMeterBill] = []
        let entries: [(MeterKind, String)] = [(.electricity, electricityText), (.water, waterText)]
        for (kind, text) in entries {
            guard let value = parseDecimal(text), value >= 0,
                  let previous = store.previousReading(kind, tenantID: t.id, before: moveOut) else { continue }
            let rate = Utilities.rate(kind, tenant: t, settings: store.settings)
            let units = max(0, value - previous.reading)
            out.append(FinalMeterBill(kind: kind, previous: previous, reading: value, rate: rate, units: units,
                                      amount: Utilities.bill(units: units, rate: rate)))
        }
        return out
    }

    private func adjustment(for bill: FinalMeterBill, day: Date) -> Adjustment {
        var a = Adjustment()
        a.kind = .extraCharge
        a.date = day
        a.amount = bill.amount
        a.title = Utilities.chargeTitle(bill.kind, from: bill.previous.reading, to: bill.reading, rate: bill.rate)
        a.reason = "Final reading at move-out"
        return a
    }

    private func metersSection(_ bills: [FinalMeterBill]) -> some View {
        Section {
            meterField(.electricity, $electricityText, bills)
            meterField(.water, $waterText, bills)
        } header: {
            Text(L("Final meter readings", "Aakhri meter reading"))
        } footer: {
            Text(L("The units used since the last reading are billed with the final rent, at the tenant's rate.",
                   "Pichhli reading se ab tak ke unit ka bill aakhri rent ke saath judega, tenant ke rate par."))
        }
    }

    @ViewBuilder
    private func meterField(_ kind: MeterKind, _ text: Binding<String>, _ bills: [FinalMeterBill]) -> some View {
        HStack {
            Text(kind.label)
            Spacer()
            TextField(L("Reading", "Reading"), text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
        if let b = bills.first(where: { $0.kind == kind }) {
            Text(concat(Fmt.number(b.units), L(" units × ₹", " unit × ₹"), Fmt.number(b.rate), " = ", Fmt.inr(b.amount),
                        (b.rate > 0 ? "" : L(" (set a rate in Electricity and water)", " (Bijli aur paani mein rate set karein)"))))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var handoverSection: some View {
        Section {
            ForEach($keys) { key in
                KeyReturnRow(key: key)
            }
            Button {
                keys.append(KeyItem(name: L("Key", "Chaabi"), count: 1, returned: 1))
            } label: {
                Label(L("Add a key", "Chaabi jodein"), systemImage: "plus")
            }
            TextField(L("Condition of the place when handed back", "Wapas milne par jagah ki halat"), text: $condition, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text(L("Keys and condition", "Chaabiyan aur halat"))
        } footer: {
            Text(L("Saved as the move-out handover. Add photos to it afterwards from the tenant's Move-in and move-out page.",
                   "Move-out handover ki tarah save hoga. Photo baad mein tenant ke Move-in aur move-out page se jodein."))
        }
    }

    private func rentSection(_ p: SettlementPreview) -> some View {
        Section(L("Rent", "Rent")) {
            LabeledContent(L("Owed up to move-out", "Move-out tak baaki"), value: Fmt.inr(p.owed))
            if p.utility > 0 {
                LabeledContent(L("Including electricity and water", "Isme bijli aur paani"), value: Fmt.inr(p.utility))
            }
            if p.credit > 0 {
                LabeledContent(L("Paid in advance", "Advance diya hua"), value: Fmt.inr(p.credit))
                Toggle(L("Return the advance to the tenant", "Advance tenant ko wapas karein"), isOn: $refundCredit)
            }
        }
    }

    private func depositSection(_ p: SettlementPreview) -> some View {
        Section(L("Security deposit", "Security deposit")) {
            LabeledContent(L("Held", "Jama hai"), value: Fmt.inr(p.held))
            MoneyField(title: L("Keep for damages", "Nuksaan ke liye rakhein"), text: $damagesText)
            if (parseAmount(damagesText) ?? 0) > 0 {
                TextField(L("Reason for keeping it", "Rakhne ka kaaran"), text: $damagesReason)
            }
            Toggle(L("Use the deposit for unpaid rent", "Baaki rent deposit se katein"), isOn: $useDeposit)
            Toggle(L("Refund what is left of the deposit", "Bacha deposit wapas karein"), isOn: $refundRest)
            if refundRest || (refundCredit && p.credit > 0) {
                Picker(L("Refund by", "Kaise wapas"), selection: $refundMethod) {
                    ForEach(PaymentMethod.selectable) { m in
                        Text(m.label).tag(m)
                    }
                }
            }
        }
    }

    private func resultSection(_ p: SettlementPreview) -> some View {
        Section(L("After settling", "Hisaab ke baad")) {
            if p.depositForRent > 0 {
                LabeledContent(L("Deposit used for rent", "Deposit se rent"), value: Fmt.inr(p.depositForRent))
            }
            LabeledContent(L("Rent still owed", "Rent ab bhi baaki"), value: Fmt.inr(p.remainingOwed))
            LabeledContent(L("Deposit refund", "Deposit wapas"), value: Fmt.inr(p.depositRefund))
            if p.depositLeft > 0 {
                LabeledContent(L("Deposit still held", "Deposit ab bhi jama"), value: Fmt.inr(p.depositLeft))
            }
            if refundCredit && p.credit > 0 {
                LabeledContent(L("Advance returned", "Advance wapas"), value: Fmt.inr(p.credit))
            }
        }
    }

    /// Works out the final position on a copy of the tenant with the move-out date set
    /// and the final meter bills added.
    private func preview(_ t: Tenant, _ bills: [FinalMeterBill]) -> SettlementPreview {
        var copy = t
        copy.endDate = DateMath.day(moveOut)
        copy.status = .vacated
        let day = DateMath.day(moveOut)
        for b in bills where b.amount > 0 {
            copy.adjustments.append(adjustment(for: b, day: day))
        }
        let asOf = max(DateMath.day(Date()), DateMath.addDays(40, to: DateMath.day(moveOut)))
        let ledger = Ledger.ledger(for: copy, asOf: asOf, graceDays: 0)
        var p = SettlementPreview()
        p.utility = bills.reduce(0) { $0 + $1.amount }
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
        let bills = meterBills(t)
        let p = preview(t, bills)
        let day = DateMath.day(moveOut)
        let reason = damagesReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let method = refundMethod
        var charges: [Adjustment] = []
        var readings: [MeterReading] = []
        for b in bills {
            var r = MeterReading(kind: b.kind, date: day, reading: b.reading, note: "Move-out")
            r.rate = b.rate
            if b.amount > 0 {
                let a = adjustment(for: b, day: day)
                r.chargeID = a.id
                r.billedAmount = b.amount
                charges.append(a)
            }
            readings.append(r)
        }
        var handover = Handover()
        handover.kind = .moveOut
        handover.date = day
        handover.electricityReading = parseDecimal(electricityText).flatMap { $0 >= 0 ? $0 : nil }
        handover.waterReading = parseDecimal(waterText).flatMap { $0 >= 0 ? $0 : nil }
        handover.condition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        handover.keys = keys.map { k in
            var key = k
            key.returned = min(max(0, k.returned), k.count)
            return key
        }
        let hasHandover = handover.electricityReading != nil || handover.waterReading != nil || !handover.keys.isEmpty
            || !handover.condition.isEmpty
        let record = FinalSettlement(date: day, rentOwed: p.owed, utilityCharges: p.utility,
                                     advanceReturned: refundCredit ? p.credit : 0, depositHeld: p.held, damages: p.damages,
                                     damagesReason: reason, depositUsedForRent: p.depositForRent, depositRefund: p.depositRefund,
                                     balanceDue: p.remainingOwed, refundMethod: method,
                                     notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        store.updateTenant(t.id, log: "Tenant moved out", details: t.name + " on " + Fmt.date(day)) { tenant in
            tenant.endDate = day
            tenant.status = .vacated
            if tenant.escalation != nil {
                Escalation.cancelSchedule(&tenant, note: "Tenant moved out")
            }
            tenant.adjustments += charges
            for r in readings where !tenant.meterReadings.contains(where: { $0.kind == r.kind && DateMath.day($0.date) == day }) {
                tenant.meterReadings.append(r)
            }
            if hasHandover {
                tenant.handovers.append(handover)
            }
            tenant.finalSettlement = record
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
