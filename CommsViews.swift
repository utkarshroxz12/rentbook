//  CommsViews.swift
//  WhatsApp messages, calls and notes, follow-ups and payment promises.
//  Messages open in WhatsApp ready to send; nothing is sent automatically.

import SwiftUI

enum CommsSheet: Identifiable {
    case message(MessageKind)
    case promise
    case log

    var id: String {
        switch self {
        case .message(let kind): return "message-" + kind.rawValue
        case .promise: return "promise"
        case .log: return "log"
        }
    }
}

enum MessageHelpers {
    /// The increase to mention in a notice: one applied recently or coming up,
    /// otherwise the next scheduled one.
    static func increase(for t: Tenant, asOf: Date = Date()) -> IncreaseProposal? {
        let history = t.rentHistory.sorted { $0.effectiveDate < $1.effectiveDate }
        if history.count >= 2 {
            let last = history[history.count - 1]
            let previous = history[history.count - 2]
            if DateMath.daysBetween(last.effectiveDate, asOf) <= 60 {
                return IncreaseProposal(date: DateMath.day(last.effectiveDate), from: previous.amount, to: last.amount,
                                        isDue: DateMath.day(last.effectiveDate) <= DateMath.day(asOf))
            }
        }
        return Escalation.next(for: t, asOf: asOf)
    }

    static func icon(_ kind: MessageKind) -> String {
        switch kind {
        case .politeReminder: return "bell"
        case .firmReminder: return "exclamationmark.bubble"
        case .partialConfirmation: return "checkmark.message"
        case .receipt: return "doc.text"
        case .increaseNotice: return "arrow.up.right.circle"
        case .renewal: return "arrow.triangle.2.circlepath"
        }
    }
}

struct CommunicationView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var sheet: CommsSheet? = nil
    @State private var pendingDelete: UUID? = nil

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func content(_ t: Tenant) -> some View {
        let logs = t.contacts.sorted { $0.date > $1.date }
        let followUps = logs.filter { !$0.followUpDone && $0.followUpDate != nil }
        return List {
            messagesSection(t)
            if !followUps.isEmpty {
                followUpSection(t, followUps)
            }
            promisesSection(t)
            logSection(logs)
        }
        .navigationTitle(L("Messages", "Messages"))
        .sheet(item: $sheet) { which in
            switch which {
            case .message(let kind):
                MessageComposerView(tenantID: tenantID, kind: kind).environmentObject(store)
            case .promise:
                PromiseFormView(tenantID: tenantID).environmentObject(store)
            case .log:
                ContactLogForm(tenantID: tenantID).environmentObject(store)
            }
        }
        .confirmationDialog(L("Delete this entry?", "Yeh entry delete karein?"), isPresented: deleteBinding, titleVisibility: .visible) {
            Button(L("Delete entry", "Entry delete karein"), role: .destructive) {
                if let id = pendingDelete {
                    deleteLog(id, t)
                }
                pendingDelete = nil
            }
        }
    }

    private func balanceNote(_ t: Tenant) -> String {
        guard let l = store.ledger(of: t.id) else { return "" }
        if l.net > 0 { return L(t.name + " owes " + Fmt.inr(l.net) + ".", t.name + " par " + Fmt.inr(l.net) + " baaki hai.") }
        if l.net < 0 { return L(t.name + " is " + Fmt.inr(-l.net) + " in credit.", t.name + " ka " + Fmt.inr(-l.net) + " credit hai.") }
        return L("Nothing is owed right now.", "Abhi kuch baaki nahi.")
    }

    private func messagesSection(_ t: Tenant) -> some View {
        Section {
            ForEach(MessageKind.allCases) { kind in
                Button {
                    sheet = .message(kind)
                } label: {
                    Label(kind.label, systemImage: MessageHelpers.icon(kind))
                }
            }
        } header: {
            Text(L("Send on WhatsApp", "WhatsApp par bhejein"))
        } footer: {
            Text(balanceNote(t))
        }
    }

    private func followUpSection(_ t: Tenant, _ items: [ContactLog]) -> some View {
        Section(L("Follow-ups", "Follow-up")) {
            ForEach(items) { log in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.note.isEmpty ? log.kind.label : log.note)
                        Text(L("Follow up on ", "Follow up: ") + Fmt.date(log.followUpDate ?? log.date))
                            .font(.caption)
                            .foregroundStyle(isLate(log) ? Color.red : Color.secondary)
                    }
                    Spacer()
                    Button(L("Done", "Ho gaya")) {
                        markDone(log.id, t)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func isLate(_ log: ContactLog) -> Bool {
        guard let d = log.followUpDate else { return false }
        return DateMath.day(d) <= DateMath.day(Date())
    }

    private func promisesSection(_ t: Tenant) -> some View {
        let promises = t.promises.sorted { $0.promisedDate > $1.promisedDate }
        return Section {
            ForEach(promises) { p in
                PromiseRow(promise: p, status: Promises.status(p, of: t))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !p.isCancelled {
                            Button {
                                cancelPromise(p.id, t)
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                            }
                            .tint(.gray)
                        }
                    }
            }
            Button {
                sheet = .promise
            } label: {
                Label(L("Record a payment promise", "Payment ka vaada record karein"), systemImage: "hand.raised")
            }
        } header: {
            Text(L("Payment promises", "Payment ke vaade"))
        } footer: {
            Text(L("A promise counts as kept when the promised amount is paid by the promised day. Swipe left to cancel one.", "Vaada pura mana jata hai jab vaade ka amount vaade ki tareekh tak mil jaye. Radd karne ke liye left swipe karein."))
        }
    }

    private func logSection(_ logs: [ContactLog]) -> some View {
        Section {
            if logs.isEmpty {
                Text(L("Nothing recorded yet.", "Abhi kuch record nahi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(logs) { log in
                ContactLogRow(log: log)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDelete = log.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
            Button {
                sheet = .log
            } label: {
                Label(L("Add a call or note", "Call ya note jodein"), systemImage: "square.and.pencil")
            }
        } header: {
            Text(L("Contact history", "Baat-cheet ki history"))
        } footer: {
            Text(L("Messages opened in WhatsApp from RentBook are added here automatically.", "RentBook se WhatsApp mein khole message yahan apne aap jud jaate hain."))
        }
    }

    private func markDone(_ id: UUID, _ t: Tenant) {
        store.updateTenant(t.id) { tenant in
            if let i = tenant.contacts.firstIndex(where: { $0.id == id }) {
                tenant.contacts[i].followUpDone = true
            }
        }
    }

    private func cancelPromise(_ id: UUID, _ t: Tenant) {
        store.updateTenant(t.id, log: "Payment promise cancelled", details: t.name) { tenant in
            if let i = tenant.promises.firstIndex(where: { $0.id == id }) {
                tenant.promises[i].isCancelled = true
            }
        }
    }

    private func deleteLog(_ id: UUID, _ t: Tenant) {
        store.updateTenant(t.id) { tenant in
            tenant.contacts.removeAll { $0.id == id }
        }
    }
}

struct ContactLogRow: View {
    let log: ContactLog

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(log.kind.label)
                Spacer()
                Text(Fmt.date(log.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !log.note.isEmpty {
                Text(log.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let follow = log.followUpDate {
                Text((log.followUpDone ? L("Followed up · was due ", "Follow up ho gaya · tareekh thi ") : L("Follow up on ", "Follow up: ")) + Fmt.date(follow))
                    .font(.caption2)
                    .foregroundStyle(log.followUpDone ? Color.green : Color.orange)
            }
        }
    }
}

// MARK: - Writing a message

struct MessageComposerView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let tenantID: UUID
    let paymentID: UUID?
    let agreementID: UUID?

    @State private var kind: MessageKind
    @State private var deadline: Date
    @State private var text = ""
    @State private var followUp = false
    @State private var followUpDate: Date
    @State private var prepared = false
    @State private var showShare = false
    @State private var copied = false
    @State private var language: AppLanguage = Lang.current

    init(tenantID: UUID, kind: MessageKind, paymentID: UUID? = nil, agreementID: UUID? = nil) {
        self.tenantID = tenantID
        self.paymentID = paymentID
        self.agreementID = agreementID
        let today = DateMath.day(Date())
        _kind = State(initialValue: kind)
        _deadline = State(initialValue: DateMath.addDays(3, to: today))
        _followUpDate = State(initialValue: DateMath.addDays(4, to: today))
    }

    private var usesDeadline: Bool {
        kind == .politeReminder || kind == .firmReminder || kind == .partialConfirmation
    }

    private var copyTitle: String { copied ? L("Copied", "Copy ho gaya") : L("Copy text", "Text copy karein") }

    var body: some View {
        NavigationStack {
            Form {
                if let t = store.tenant(tenantID) {
                    Section {
                        Picker(L("Message", "Message"), selection: $kind) {
                            ForEach(MessageKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        if usesDeadline {
                            DatePicker(L("Pay by", "Kab tak dena hai"), selection: $deadline, displayedComponents: .date)
                        }
                        Picker(L("Language", "Bhasha"), selection: $language) {
                            ForEach(AppLanguage.allCases) { l in
                                Text(l.label).tag(l)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        TextEditor(text: $text)
                            .frame(minHeight: 220)
                        Button(L("Start again from the template", "Template se dobara shuru karein")) {
                            regenerate()
                        }
                    } header: {
                        Text(L("Message", "Message"))
                    } footer: {
                        Text(L("Edit the text as you like before sending.", "Bhejne se pehle text badal sakte hain."))
                    }
                    Section {
                        Toggle(L("Remind me to follow up", "Follow up yaad dilayein"), isOn: $followUp)
                        if followUp {
                            DatePicker(L("Follow up on", "Follow up kab"), selection: $followUpDate, displayedComponents: .date)
                        }
                    }
                    sendSection(t)
                }
            }
            .navigationTitle(L("Message", "Message"))
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
            .onChange(of: kind) { _ in
                regenerate()
            }
            .onChange(of: deadline) { _ in
                regenerate()
            }
            .onChange(of: language) { _ in
                regenerate()
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [text])
            }
        }
    }

    private func sendSection(_ t: Tenant) -> some View {
        Section {
            if let url = Messages.whatsappURL(phone: t.phone, text: text) {
                Button {
                    send(t, url)
                } label: {
                    Label(L("Open in WhatsApp", "WhatsApp mein kholein"), systemImage: "paperplane.fill")
                }
            } else {
                Text(t.phone.isEmpty ? L("Add a mobile number to this tenant to send on WhatsApp.", "WhatsApp par bhejne ke liye is tenant ka mobile number jodein.") : L("This mobile number doesn't look right for WhatsApp. Check it in the tenant's details.", "Yeh mobile number WhatsApp ke liye sahi nahi lagta. Tenant ki details mein check karein."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                copy(t)
            } label: {
                Label(copyTitle, systemImage: "doc.on.doc")
            }
            Button {
                showShare = true
            } label: {
                Label(L("Share another way", "Kisi aur tarah share karein"), systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text(L("WhatsApp opens with the message ready. Check it there and tap send.", "WhatsApp message ke saath khulega. Wahan check karke send dabayein."))
        }
    }

    private func context(_ t: Tenant) -> MessageContext {
        let ledger = store.freshLedger(for: t)
        var c = MessageContext(tenant: t, place: store.place(of: t), ledger: ledger, deadline: deadline,
                               landlord: store.settings.landlordName)
        if let pid = paymentID {
            c.payment = ledger.payments.first { $0.payment.id == pid }
        } else {
            c.payment = ledger.payments.last { !$0.payment.isReversed && $0.payment.kind == .payment }
        }
        c.increase = MessageHelpers.increase(for: t)
        if let aid = agreementID {
            c.agreement = t.agreements.first { $0.id == aid }
        } else {
            c.agreement = Agreements.current(of: t)
        }
        return c
    }

    private func regenerate() {
        guard let t = store.tenant(tenantID) else { return }
        text = Messages.compose(kind, context(t), language: language)
        copied = false
    }

    private func logContact(_ t: Tenant, how: String) {
        let follow: Date? = followUp ? DateMath.day(followUpDate) : nil
        let entry = ContactLog(date: Date(), kind: kind.contactKind, note: kind.label + " · " + how, followUpDate: follow)
        store.updateTenant(t.id) { tenant in
            tenant.contacts.append(entry)
        }
    }

    private func send(_ t: Tenant, _ url: URL) {
        logContact(t, how: "WhatsApp")
        openURL(url)
        dismiss()
    }

    private func copy(_ t: Tenant) {
        UIPasteboard.general.string = text
        if !copied {
            logContact(t, how: "copied")
        }
        copied = true
    }
}

// MARK: - Promises and notes

struct PromiseFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var amountText = ""
    @State private var date = DateMath.addDays(7, to: DateMath.day(Date()))
    @State private var note = ""
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: L("Amount promised", "Vaade ka amount"), text: $amountText)
                    DatePicker(L("Will pay by", "Kab tak dega"), selection: $date, in: DateMath.day(Date())..., displayedComponents: .date)
                    TextField(L("Note, e.g. after salary", "Note, jaise salary ke baad"), text: $note)
                } footer: {
                    Text(L("RentBook reminds you on that day and marks the promise kept or missed from the payments you record.", "RentBook us din yaad dilayega aur aapke record kiye payment se vaada pura ya toota mark karega."))
                }
            }
            .navigationTitle(L("Payment promise", "Payment ka vaada"))
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
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let owed = store.ledger(of: tenantID)?.net ?? 0
        amountText = owed > 0 ? String(owed) : ""
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0 else { return }
        let promise = PaymentPromise(madeOn: DateMath.day(Date()), promisedDate: DateMath.day(date), amount: amount,
                                     note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        let name = store.tenant(tenantID)?.name ?? ""
        store.updateTenant(tenantID, log: "Payment promise recorded",
                           details: name + ": " + Fmt.inr(amount) + " by " + Fmt.date(promise.promisedDate)) { t in
            t.promises.append(promise)
        }
        dismiss()
    }
}

struct ContactLogForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var kind: ContactKind = .call
    @State private var date = Date()
    @State private var note = ""
    @State private var followUp: Date? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Type", "Kism"), selection: $kind) {
                        ForEach(ContactKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    DatePicker(L("When", "Kab"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField(L("What was said or agreed", "Kya baat hui ya kya tay hua"), text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    OptionalDatePicker(title: L("Follow up later", "Baad mein follow up"), date: $followUp)
                } footer: {
                    Text(L("Follow-ups appear on the home screen and as a reminder on the day.", "Follow-up home screen par aur us din reminder ki tarah dikhte hain."))
                }
            }
            .navigationTitle(L("Call or note", "Call ya note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                }
            }
        }
    }

    private func save() {
        let entry = ContactLog(date: date, kind: kind, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                               followUpDate: followUp.map { DateMath.day($0) })
        store.updateTenant(tenantID) { t in
            t.contacts.append(entry)
        }
        dismiss()
    }
}
