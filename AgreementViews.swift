//  AgreementViews.swift
//  Rental agreements: dates, terms, status, documents and renewals.

import SwiftUI

func agreementColor(_ status: AgreementStatus) -> Color {
    switch status {
    case .upcoming: return .blue
    case .active, .open: return .green
    case .expiring: return .orange
    case .expired: return .red
    }
}

struct AgreementsView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var showingAdd = false

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        let list = t.agreements.sorted { $0.startDate > $1.startDate }
        return List {
            Section {
                if list.isEmpty {
                    Text(L("No agreement recorded yet.", "Abhi koi agreement record nahi."))
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { a in
                    NavigationLink(value: Route.agreement(t.id, a.id)) {
                        AgreementRow(agreement: a)
                    }
                }
            } footer: {
                Text(L("Add the agreement's dates and terms, and attach the signed copy. RentBook reminds you before it ends.", "Agreement ki tareekh aur sharten likhein, aur sign ki hui copy jodein. Khatam hone se pehle RentBook yaad dilayega."))
            }
            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label(L("Add an agreement", "Agreement jodein"), systemImage: "plus")
                }
            }
        }
        .navigationTitle("Agreements")
        .sheet(isPresented: $showingAdd) {
            AgreementFormView(tenantID: tenantID, existing: nil, renewalOf: nil).environmentObject(store)
        }
    }
}

struct AgreementRow: View {
    let agreement: Agreement

    var body: some View {
        let status = Agreements.status(agreement)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agreement.title.isEmpty ? L("Rental agreement", "Rent agreement") : agreement.title)
                Text(period)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TagLabel(text: status.label, color: agreementColor(status))
        }
    }

    private var period: String {
        Fmt.date(agreement.startDate) + L(" to ", " – ") + (agreement.endDate.map { Fmt.date($0) } ?? L("no end date", "koi end date nahi"))
    }
}

enum AgreementSheet: Identifiable {
    case edit
    case renew
    case message

    var id: Int {
        switch self {
        case .edit: return 0
        case .renew: return 1
        case .message: return 2
        }
    }
}

struct AgreementDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    let agreementID: UUID

    @State private var sheet: AgreementSheet? = nil
    @State private var askDelete = false

    var body: some View {
        if let t = store.tenant(tenantID), let a = t.agreements.first(where: { $0.id == agreementID }) {
            content(t, a)
        } else {
            Text(L("This agreement was removed.", "Yeh agreement hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ a: Agreement) -> some View {
        List {
            summarySection(t, a)
            termsSection(a)
            AttachmentsSection(title: L("Signed agreement and papers", "Sign kiya agreement aur kaagaz"), ids: a.attachmentIDs, category: "Agreement") { id in
                store.updateTenant(t.id) { tenant in
                    if let i = tenant.agreements.firstIndex(where: { $0.id == agreementID }) {
                        tenant.agreements[i].attachmentIDs.append(id)
                    }
                }
            }
            actionsSection
        }
        .attachmentHost()
        .navigationTitle(a.title.isEmpty ? "Agreement" : a.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("Edit", "Badlein")) { sheet = .edit }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .edit:
                AgreementFormView(tenantID: tenantID, existing: a, renewalOf: nil).environmentObject(store)
            case .renew:
                AgreementFormView(tenantID: tenantID, existing: nil, renewalOf: a).environmentObject(store)
            case .message:
                MessageComposerView(tenantID: tenantID, kind: .renewal, agreementID: agreementID).environmentObject(store)
            }
        }
        .confirmationDialog(L("Delete this agreement?", "Yeh agreement delete karein?"), isPresented: $askDelete, titleVisibility: .visible) {
            Button(L("Delete agreement", "Agreement delete karein"), role: .destructive) {
                delete(t, a)
            }
        } message: {
            Text(L("Its dates and terms are removed. Any attached papers are kept under the tenant's ID and documents.", "Iski tareekh aur sharten hat jayengi. Jude kaagaz tenant ke ID aur documents mein rahenge."))
        }
    }

    private func summarySection(_ t: Tenant, _ a: Agreement) -> some View {
        let status = Agreements.status(a)
        return Section {
            HStack {
                Text(t.name)
                    .font(.headline)
                Spacer()
                TagLabel(text: status.label, color: agreementColor(status))
            }
            LabeledContent(L("Starts", "Shuru"), value: Fmt.date(a.startDate))
            LabeledContent(L("Ends", "Khatam"), value: a.endDate.map { Fmt.date($0) } ?? L("No end date", "Koi end date nahi"))
            if let end = a.endDate {
                LabeledContent(daysLabel(end), value: daysValue(end))
            }
            LabeledContent(L("Remind me", "Yaad dilayein"), value: L("\(a.reminderDays) days before it ends", "Khatam hone se \(a.reminderDays) din pehle"))
        }
    }

    private func daysLabel(_ end: Date) -> String {
        DateMath.daysBetween(Date(), end) >= 0 ? L("Days left", "Din baaki") : L("Ended", "Khatam ho gaya")
    }

    private func daysValue(_ end: Date) -> String {
        let days = DateMath.daysBetween(Date(), end)
        return days >= 0 ? "\(days)" : L("\(-days) days ago", "\(-days) din pehle")
    }

    private func termsSection(_ a: Agreement) -> some View {
        Section(L("Terms", "Sharten")) {
            termRow(L("Notice period", "Notice period"), a.noticePeriod)
            termRow(L("Renewal terms", "Renewal ki sharten"), a.renewalTerms)
            termRow(L("Rent increase clause", "Rent badhotri ki shart"), a.escalationClause)
            termRow(L("Deposit terms", "Deposit ki sharten"), a.depositTerms)
            termRow("Notes", a.notes)
        }
    }

    @ViewBuilder
    private func termRow(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                sheet = .renew
            } label: {
                Label(L("Renew agreement", "Agreement renew karein"), systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                sheet = .message
            } label: {
                Label(L("Ask about renewal on WhatsApp", "WhatsApp par renewal ke baare mein poochein"), systemImage: "message")
            }
            Button(role: .destructive) {
                askDelete = true
            } label: {
                Label(L("Delete agreement", "Agreement delete karein"), systemImage: "trash")
            }
        } footer: {
            Text(L("Renewing adds a new agreement that starts when this one ends, and keeps this one in the history.", "Renew karne se naya agreement judega jo iske khatam hone par shuru hoga, aur yeh history mein rahega."))
        }
    }

    private func delete(_ t: Tenant, _ a: Agreement) {
        let files = a.attachmentIDs
        let details = t.name + ": " + Fmt.date(a.startDate) + L(" to ", " – ") + (a.endDate.map { Fmt.date($0) } ?? L("no end date", "koi end date nahi"))
        store.updateTenant(t.id, log: "Agreement deleted", details: details) { tenant in
            tenant.agreements.removeAll { $0.id == a.id }
            // Signed copies are kept with the tenant's documents rather than deleted.
            for id in files where !tenant.documentIDs.contains(id) {
                tenant.documentIDs.append(id)
            }
        }
        dismiss()
    }
}

// MARK: - Add, edit or renew

struct AgreementFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    private let existing: Agreement?
    private let renewalOf: Agreement?

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date?
    @State private var noticePeriod: String
    @State private var renewalTerms: String
    @State private var escalationClause: String
    @State private var depositTerms: String
    @State private var notes: String
    @State private var reminderDays: Int
    @State private var newRentText = ""
    @State private var prepared = false

    init(tenantID: UUID, existing: Agreement?, renewalOf: Agreement?) {
        self.tenantID = tenantID
        self.existing = existing
        self.renewalOf = renewalOf
        let base = existing ?? renewalOf ?? Agreement()
        _title = State(initialValue: base.title)
        _noticePeriod = State(initialValue: base.noticePeriod)
        _renewalTerms = State(initialValue: base.renewalTerms)
        _escalationClause = State(initialValue: base.escalationClause)
        _depositTerms = State(initialValue: base.depositTerms)
        _notes = State(initialValue: existing?.notes ?? "")
        _reminderDays = State(initialValue: base.reminderDays)
        if let old = renewalOf {
            let oldEnd = old.endDate ?? DateMath.day(Date())
            let start = DateMath.addDays(1, to: DateMath.day(oldEnd))
            var months = 11
            if let end = old.endDate {
                let length = rbCalendar.dateComponents([.month], from: DateMath.day(old.startDate), to: DateMath.addDays(1, to: DateMath.day(end))).month ?? 11
                months = max(1, length)
            }
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: DateMath.addDays(-1, to: DateMath.addMonths(months, to: start)))
        } else if let a = existing {
            _startDate = State(initialValue: a.startDate)
            _endDate = State(initialValue: a.endDate)
        } else {
            let start = DateMath.day(Date())
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: DateMath.addDays(-1, to: DateMath.addMonths(11, to: start)))
        }
    }

    private var screenTitle: String {
        if existing != nil { return L("Edit agreement", "Agreement badlein") }
        return renewalOf != nil ? L("Renew agreement", "Agreement renew karein") : L("New agreement", "Naya agreement")
    }

    private var remindText: String { L("Remind me \(reminderDays) days before it ends", "Khatam hone se \(reminderDays) din pehle yaad dilayein") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Title, e.g. Rental agreement 2026", "Naam, jaise Rent agreement 2026"), text: $title)
                    DatePicker(L("Starts on", "Shuru hone ki tareekh"), selection: $startDate, displayedComponents: .date)
                    OptionalDatePicker(title: L("Has an end date", "End date hai"), date: $endDate)
                    Stepper(remindText, value: $reminderDays, in: 0...120, step: 5)
                }
                if renewalOf != nil {
                    Section {
                        MoneyField(title: L("New monthly rent", "Naya mahine ka rent"), text: $newRentText)
                    } header: {
                        Text("Rent")
                    } footer: {
                        Text(L("Leave empty to keep the current rent. A new amount applies to rent due from the start date, and the next scheduled increase is counted from then.", "Abhi ka rent rakhne ke liye khaali chhodein. Naya amount shuru ki tareekh se lagega, aur agli badhotri bhi tab se gini jayegi."))
                    }
                }
                Section(L("Terms", "Sharten")) {
                    TextField(L("Notice period, e.g. 1 month", "Notice period, jaise 1 mahina"), text: $noticePeriod)
                    TextField(L("Renewal terms", "Renewal ki sharten"), text: $renewalTerms, axis: .vertical)
                        .lineLimit(1...4)
                    TextField(L("Rent increase clause", "Rent badhotri ki shart"), text: $escalationClause, axis: .vertical)
                        .lineLimit(1...4)
                    TextField(L("Deposit terms", "Deposit ki sharten"), text: $depositTerms, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }
                if existing == nil {
                    Section {
                        Text(L("Attach the signed copy after saving: open the agreement and tap Add photo or Add PDF.", "Save karne ke baad sign ki copy jodein: agreement kholein aur Photo jodein ya PDF jodein dabayein."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .disabled(!datesValid)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
        }
    }

    private var datesValid: Bool {
        guard let end = endDate else { return true }
        return DateMath.day(end) >= DateMath.day(startDate)
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if existing == nil && renewalOf == nil {
            reminderDays = store.settings.agreementDaysBefore
            if let t = store.tenant(tenantID), let start = t.startDate, t.agreements.isEmpty {
                startDate = start
                endDate = DateMath.addDays(-1, to: DateMath.addMonths(11, to: start))
            }
        }
    }

    private func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let t = store.tenant(tenantID) else { return }
        var a = existing ?? Agreement()
        a.title = clean(title).isEmpty ? L("Rental agreement", "Rent agreement") : clean(title)
        a.startDate = DateMath.day(startDate)
        a.endDate = endDate.map { DateMath.day($0) }
        a.noticePeriod = clean(noticePeriod)
        a.renewalTerms = clean(renewalTerms)
        a.escalationClause = clean(escalationClause)
        a.depositTerms = clean(depositTerms)
        a.notes = clean(notes)
        a.reminderDays = reminderDays
        let saved = a
        let period = Fmt.date(saved.startDate) + L(" to ", " – ") + (saved.endDate.map { Fmt.date($0) } ?? L("no end date", "koi end date nahi"))
        let action: String
        if existing != nil {
            action = "Agreement updated"
        } else {
            action = renewalOf != nil ? "Agreement renewed" : "Agreement added"
        }
        let newRent = renewalOf != nil ? (parseAmount(newRentText) ?? 0) : 0
        let current = Ledger.rent(of: t, on: DateMath.addDays(-1, to: saved.startDate))
        let rentChanged = newRent > 0 && newRent != current
        let details = t.name + ": " + period + (rentChanged ? " · rent " + Fmt.inr(current) + " → " + Fmt.inr(newRent) : "")
        store.updateTenant(tenantID, log: action, details: details) { tenant in
            if let i = tenant.agreements.firstIndex(where: { $0.id == saved.id }) {
                tenant.agreements[i] = saved
            } else {
                tenant.agreements.append(saved)
            }
            if rentChanged {
                // A new rent at renewal also restarts the increase schedule from the start date.
                RentChanges.apply(&tenant, newRent: newRent, effective: saved.startDate, reason: "Agreement renewed", scheduledFor: nil)
            }
        }
        dismiss()
    }
}
