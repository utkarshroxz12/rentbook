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
            Text("This tenant was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        let list = t.agreements.sorted { $0.startDate > $1.startDate }
        return List {
            Section {
                if list.isEmpty {
                    Text("No agreement recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { a in
                    NavigationLink(value: Route.agreement(t.id, a.id)) {
                        AgreementRow(agreement: a)
                    }
                }
            } footer: {
                Text("Add the agreement's dates and terms, and attach the signed copy. RentBook reminds you before it ends.")
            }
            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add an agreement", systemImage: "plus")
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
                Text(agreement.title.isEmpty ? "Rental agreement" : agreement.title)
                Text(period)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TagLabel(text: status.label, color: agreementColor(status))
        }
    }

    private var period: String {
        Fmt.date(agreement.startDate) + " to " + (agreement.endDate.map { Fmt.date($0) } ?? "no end date")
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
            Text("This agreement was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ a: Agreement) -> some View {
        List {
            summarySection(t, a)
            termsSection(a)
            AttachmentsSection(title: "Signed agreement and papers", ids: a.attachmentIDs, category: "Agreement") { id in
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
                Button("Edit") { sheet = .edit }
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
        .confirmationDialog("Delete this agreement?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete agreement", role: .destructive) {
                delete(t, a)
            }
        } message: {
            Text("Its dates and terms are removed. Any attached papers are kept under the tenant's ID and documents.")
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
            LabeledContent("Starts", value: Fmt.date(a.startDate))
            LabeledContent("Ends", value: a.endDate.map { Fmt.date($0) } ?? "No end date")
            if let end = a.endDate {
                LabeledContent(daysLabel(end), value: daysValue(end))
            }
            LabeledContent("Remind me", value: "\(a.reminderDays) days before it ends")
        }
    }

    private func daysLabel(_ end: Date) -> String {
        DateMath.daysBetween(Date(), end) >= 0 ? "Days left" : "Ended"
    }

    private func daysValue(_ end: Date) -> String {
        let days = DateMath.daysBetween(Date(), end)
        return days >= 0 ? "\(days)" : "\(-days) days ago"
    }

    private func termsSection(_ a: Agreement) -> some View {
        Section("Terms") {
            termRow("Notice period", a.noticePeriod)
            termRow("Renewal terms", a.renewalTerms)
            termRow("Rent increase clause", a.escalationClause)
            termRow("Deposit terms", a.depositTerms)
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
                Label("Renew agreement", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                sheet = .message
            } label: {
                Label("Ask about renewal on WhatsApp", systemImage: "message")
            }
            Button(role: .destructive) {
                askDelete = true
            } label: {
                Label("Delete agreement", systemImage: "trash")
            }
        } footer: {
            Text("Renewing adds a new agreement that starts when this one ends, and keeps this one in the history.")
        }
    }

    private func delete(_ t: Tenant, _ a: Agreement) {
        let files = a.attachmentIDs
        let details = t.name + ": " + Fmt.date(a.startDate) + " to " + (a.endDate.map { Fmt.date($0) } ?? "no end date")
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
        if existing != nil { return "Edit agreement" }
        return renewalOf != nil ? "Renew agreement" : "New agreement"
    }

    private var remindText: String { "Remind me \(reminderDays) days before it ends" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Rental agreement 2026", text: $title)
                    DatePicker("Starts on", selection: $startDate, displayedComponents: .date)
                    OptionalDatePicker(title: "Has an end date", date: $endDate)
                    Stepper(remindText, value: $reminderDays, in: 0...120, step: 5)
                }
                if renewalOf != nil {
                    Section {
                        MoneyField(title: "New monthly rent", text: $newRentText)
                    } header: {
                        Text("Rent")
                    } footer: {
                        Text("Leave empty to keep the current rent. A new amount applies to rent due from the start date, and the next scheduled increase is counted from then.")
                    }
                }
                Section("Terms") {
                    TextField("Notice period, e.g. 1 month", text: $noticePeriod)
                    TextField("Renewal terms", text: $renewalTerms, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Rent increase clause", text: $escalationClause, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Deposit terms", text: $depositTerms, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }
                if existing == nil {
                    Section {
                        Text("Attach the signed copy after saving: open the agreement and tap Add photo or Add PDF.")
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
                    Button("Save") { save() }
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
        a.title = clean(title).isEmpty ? "Rental agreement" : clean(title)
        a.startDate = DateMath.day(startDate)
        a.endDate = endDate.map { DateMath.day($0) }
        a.noticePeriod = clean(noticePeriod)
        a.renewalTerms = clean(renewalTerms)
        a.escalationClause = clean(escalationClause)
        a.depositTerms = clean(depositTerms)
        a.notes = clean(notes)
        a.reminderDays = reminderDays
        let saved = a
        let period = Fmt.date(saved.startDate) + " to " + (saved.endDate.map { Fmt.date($0) } ?? "no end date")
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
