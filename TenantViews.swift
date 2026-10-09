//  TenantViews.swift
//  Tenant list with search, filters and sorting; the tenant profile; the tenant form.

import SwiftUI
import PhotosUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all, paid, partial, unpaid, overdue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Any payment status"
        case .paid: return "Paid"
        case .partial: return "Partly paid"
        case .unpaid: return "Unpaid"
        case .overdue: return "Overdue"
        }
    }
}

enum AgreementFilter: String, CaseIterable, Identifiable {
    case all, active, expiring, expired, missing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Any agreement"
        case .active: return "Agreement active"
        case .expiring: return "Agreement expiring"
        case .expired: return "Agreement expired"
        case .missing: return "No agreement"
        }
    }
}

enum TenantSort: String, CaseIterable, Identifiable {
    case name, outstanding, daysOverdue, nextDue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Name"
        case .outstanding: return "Highest outstanding"
        case .daysOverdue: return "Most days overdue"
        case .nextDue: return "Next due date"
        }
    }
}

struct TenantListView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var status: StatusFilter = .all
    @State private var propertyID: UUID? = nil
    @State private var agreement: AgreementFilter = .all
    @State private var increasesSoon = false
    @State private var showVacated = false
    @State private var sort: TenantSort = .name
    @State private var showingAdd = false

    private var isFiltered: Bool {
        status != .all || propertyID != nil || agreement != .all || increasesSoon || showVacated || sort != .name
    }

    var body: some View {
        let snap = store.snapshot
        let rows = filteredTenants(snap)
        List {
            if isFiltered {
                Section {
                    HStack {
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { clearFilters() }
                            .font(.caption)
                    }
                }
            }
            if rows.isEmpty {
                Text(store.data.tenants.isEmpty ? "No tenants yet. Tap + to add one." : "No tenants match.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { t in
                NavigationLink(value: Route.tenant(t.id)) {
                    TenantRowView(tenant: t, ledger: snap.ledgers[t.id], place: store.place(of: t))
                }
            }
        }
        .searchable(text: $query, prompt: "Name, phone or property")
        .navigationTitle("Tenants")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            TenantFormView(tenant: nil).environmentObject(store)
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if status != .all { parts.append(status.label) }
        if let id = propertyID, let p = store.property(id) { parts.append(p.name) }
        if agreement != .all { parts.append(agreement.label) }
        if increasesSoon { parts.append("Increase soon") }
        if showVacated { parts.append("Including vacated") }
        if sort != .name { parts.append("Sorted by " + sort.label.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private func clearFilters() {
        status = .all
        propertyID = nil
        agreement = .all
        increasesSoon = false
        showVacated = false
        sort = .name
    }

    private var filterMenu: some View {
        Menu {
            Picker("Payment status", selection: $status) {
                ForEach(StatusFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker("Property", selection: $propertyID) {
                Text("All properties").tag(Optional<UUID>.none)
                ForEach(store.activeProperties) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            Picker("Agreement", selection: $agreement) {
                ForEach(AgreementFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker("Sort by", selection: $sort) {
                ForEach(TenantSort.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Toggle("Rent increase within 60 days", isOn: $increasesSoon)
            Toggle("Show vacated tenants", isOn: $showVacated)
        } label: {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private func filteredTenants(_ snap: PortfolioSnapshot) -> [Tenant] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let today = DateMath.day(Date())
        var list = store.data.tenants.filter { !$0.isArchived && (showVacated || $0.status != .vacated) }
        if !q.isEmpty {
            list = list.filter { t in
                t.name.lowercased().contains(q) || t.phone.contains(q) || store.place(of: t).lowercased().contains(q)
            }
        }
        if let pid = propertyID {
            list = list.filter { $0.propertyID == pid }
        }
        if status != .all {
            list = list.filter { snap.ledgers[$0.id]?.status.rawValue == status.rawValue }
        }
        if agreement != .all {
            let wanted = agreement
            list = list.filter { t in
                guard let a = Agreements.current(of: t, asOf: today) else { return wanted == .missing }
                let s = Agreements.status(a, asOf: today)
                switch wanted {
                case .all: return true
                case .missing: return false
                case .active: return s == .active || s == .open || s == .upcoming
                case .expiring: return s == .expiring
                case .expired: return s == .expired
                }
            }
        }
        if increasesSoon {
            list = list.filter { t in
                guard let next = Escalation.next(for: t, asOf: today) else { return false }
                return DateMath.daysBetween(today, next.date) <= 60
            }
        }
        switch sort {
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .outstanding:
            list.sort { (snap.ledgers[$0.id]?.outstanding ?? 0) > (snap.ledgers[$1.id]?.outstanding ?? 0) }
        case .daysOverdue:
            list.sort { (snap.ledgers[$0.id]?.daysOverdue ?? 0) > (snap.ledgers[$1.id]?.daysOverdue ?? 0) }
        case .nextDue:
            list.sort { a, b in
                let da = snap.ledgers[a.id]?.nextRentLine?.charge.dueDate ?? Date.distantFuture
                let db = snap.ledgers[b.id]?.nextRentLine?.charge.dueDate ?? Date.distantFuture
                return da < db
            }
        }
        return list
    }
}

struct TenantRowView: View {
    let tenant: Tenant
    let ledger: TenantLedger?
    let place: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tenant.name)
                        .font(.headline)
                    if tenant.status != .active {
                        TagLabel(text: tenant.status.label, color: tenant.status == .vacated ? .gray : .purple)
                    }
                }
                if !place.isEmpty {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let next = ledger?.nextRentLine {
                    Text("Next due " + Fmt.date(next.charge.dueDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let l = ledger {
                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(status: l.status)
                    if l.net > 0 {
                        Text(Fmt.inr(l.net))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(l.overdue > 0 ? Color.red : Color.orange)
                    } else if l.net < 0 {
                        Text(Fmt.inr(-l.net) + " credit")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }
}

// MARK: - Tenant profile

enum TenantSheet: Identifiable {
    case edit
    case pay
    case refund
    case message(MessageKind)
    case promise
    case moveOut

    var id: String {
        switch self {
        case .edit: return "edit"
        case .pay: return "pay"
        case .refund: return "refund"
        case .message(let kind): return "message-" + kind.rawValue
        case .promise: return "promise"
        case .moveOut: return "moveOut"
        }
    }
}

struct TenantDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let tenantID: UUID

    @State private var sheet: TenantSheet? = nil
    @State private var confirmArchive = false

    var body: some View {
        if let t = store.tenant(tenantID), let ledger = store.ledger(of: tenantID) {
            content(t, ledger)
        } else {
            Text("This tenant was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ l: TenantLedger) -> some View {
        List {
            summarySection(t, l)
            actionsSection(t, l)
            moneySection(t, l)
            promisesSection(t)
            detailsSection(t)
            AttachmentsSection(title: "ID and documents", ids: t.documentIDs, category: "Tenant document") { id in
                store.updateTenant(t.id) { $0.documentIDs.append(id) }
            }
            manageSection(t)
        }
        .attachmentHost()
        .navigationTitle(t.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { sheet = .edit }
            }
        }
        .sheet(item: $sheet) { which in
            sheetView(which, t)
        }
        .confirmationDialog("Archive " + t.name + "?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive tenant", role: .destructive) {
                store.setTenantArchived(t.id, true)
                dismiss()
            }
        } message: {
            Text(archiveWarning(t, l))
        }
    }

    private func archiveWarning(_ t: Tenant, _ l: TenantLedger) -> String {
        var parts: [String] = []
        if t.status != .vacated {
            parts.append(t.name + " is still marked as living there, so rent keeps being billed but won't show on the home screen, in reminders or in reports. Use Move out and settle first if they have left.")
        }
        if l.net > 0 {
            parts.append("They still owe " + Fmt.inr(l.net) + ".")
        }
        let held = Ledger.deposit(of: t).held
        if held > 0 {
            parts.append(Fmt.inr(held) + " of deposit is still held.")
        }
        parts.append("Their history is kept, and you can restore them from Settings → Archived.")
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func sheetView(_ which: TenantSheet, _ t: Tenant) -> some View {
        switch which {
        case .edit:
            TenantFormView(tenant: t).environmentObject(store)
        case .pay:
            PaymentFormView(tenantID: t.id).environmentObject(store)
        case .refund:
            PaymentFormView(tenantID: t.id, kind: .refund).environmentObject(store)
        case .message(let kind):
            MessageComposerView(tenantID: t.id, kind: kind).environmentObject(store)
        case .promise:
            PromiseFormView(tenantID: t.id).environmentObject(store)
        case .moveOut:
            SettlementView(tenantID: t.id).environmentObject(store)
        }
    }

    private func summarySection(_ t: Tenant, _ l: TenantLedger) -> some View {
        let place = store.place(of: t)
        return Section {
            HStack(spacing: 14) {
                TenantPhoto(tenant: t)
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.isEmpty ? "No property assigned" : place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        StatusBadge(status: l.status)
                        if t.status != .active {
                            TagLabel(text: t.status.label, color: .purple)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(balanceTitle(l))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.inr(abs(l.net)))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(balanceColor(l))
                if l.outstanding > 0 {
                    Text("This period " + Fmt.inr(l.currentDue) + " · Earlier dues " + Fmt.inr(l.arrears))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let oldest = l.oldestUnpaid {
                    Text("Oldest unpaid: " + oldest.charge.title + " · \(l.daysOverdue) days")
                        .font(.caption)
                        .foregroundStyle(l.overdue > 0 ? Color.red : Color.secondary)
                }
            }
            .padding(.vertical, 4)
            if let next = l.nextRentLine {
                LabeledContent("Next rent due", value: Fmt.date(next.charge.dueDate) + " · " + Fmt.inr(next.charge.amount))
            }
            if let last = l.lastPaymentDate {
                LabeledContent("Last payment", value: Fmt.date(last))
            }
        }
    }

    private func balanceTitle(_ l: TenantLedger) -> String {
        if l.net > 0 { return "Outstanding" }
        if l.net < 0 { return "In credit (paid ahead)" }
        return "All clear"
    }

    private func balanceColor(_ l: TenantLedger) -> Color {
        if l.net > 0 { return l.overdue > 0 ? .red : .orange }
        return .green
    }

    private func actionsSection(_ t: Tenant, _ l: TenantLedger) -> some View {
        Section {
            Button {
                sheet = .pay
            } label: {
                Label("Record payment", systemImage: "indianrupeesign.circle.fill")
            }
            Button {
                sheet = .message(l.overdue > 0 ? .firmReminder : .politeReminder)
            } label: {
                Label("Send WhatsApp message", systemImage: "message.fill")
            }
            if let url = Messages.callURL(phone: t.phone) {
                Button {
                    store.updateTenant(t.id) { $0.contacts.append(ContactLog(kind: .call, note: "Phone call")) }
                    openURL(url)
                } label: {
                    Label("Call " + t.phone, systemImage: "phone.fill")
                }
            }
            if let url = Messages.emailURL(t.email) {
                Button {
                    openURL(url)
                } label: {
                    Label("Email " + t.email, systemImage: "envelope.fill")
                }
            }
        }
    }

    private func moneySection(_ t: Tenant, _ l: TenantLedger) -> some View {
        let deposit = Ledger.deposit(of: t)
        let increase = Escalation.next(for: t)
        let agreement = Agreements.current(of: t)
        let paymentCount = t.payments.filter { !$0.isReversed }.count
        return Section("Rent and money") {
            NavigationLink(value: Route.tenantLedger(t.id)) {
                linkRow("Ledger and payments", "list.bullet.rectangle", "\(paymentCount) payment" + (paymentCount == 1 ? "" : "s"))
            }
            NavigationLink(value: Route.charges(t.id)) {
                linkRow("Extra charges and discounts", "plus.forwardslash.minus", "\(t.recurringCharges.count + t.adjustments.filter { !$0.isReversed }.count)")
            }
            NavigationLink(value: Route.deposits(t.id)) {
                linkRow("Security deposit", "banknote", Fmt.inr(deposit.held) + " held")
            }
            NavigationLink(value: Route.increases(t.id)) {
                linkRow("Rent increases", "arrow.up.right.circle", increaseText(increase))
            }
            NavigationLink(value: Route.agreements(t.id)) {
                linkRow("Agreements", "doc.text", agreement.map { Agreements.status($0).label } ?? "None yet")
            }
            NavigationLink(value: Route.communication(t.id)) {
                linkRow("Messages and follow-ups", "bubble.left.and.bubble.right", "\(t.contacts.count)")
            }
        }
    }

    private func increaseText(_ p: IncreaseProposal?) -> String {
        guard let p = p else { return "Not scheduled" }
        return (p.isDue ? "Due · " : "") + Fmt.date(p.date)
    }

    private func linkRow(_ title: String, _ icon: String, _ detail: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func promisesSection(_ t: Tenant) -> some View {
        let promises = t.promises.filter { !$0.isCancelled }.sorted { $0.promisedDate > $1.promisedDate }
        return Section {
            ForEach(Array(promises.prefix(3))) { p in
                PromiseRow(promise: p, status: Promises.status(p, of: t))
            }
            Button {
                sheet = .promise
            } label: {
                Label("Record a payment promise", systemImage: "hand.raised")
            }
        } header: {
            Text("Payment promises")
        }
    }

    private func detailsSection(_ t: Tenant) -> some View {
        Section("Details") {
            Group {
                if !t.phone.isEmpty { LabeledContent("Mobile", value: t.phone) }
                if !t.email.isEmpty { LabeledContent("Email", value: t.email) }
                if !t.address.isEmpty { LabeledContent("Address", value: t.address) }
                if !t.emergencyContact.isEmpty { LabeledContent("Emergency contact", value: t.emergencyContact) }
            }
            LabeledContent("Monthly rent", value: Fmt.inr(Ledger.currentRent(of: t)))
            LabeledContent("Billing", value: t.frequency.label + ", due on the " + Fmt.ordinal(min(max(t.dueDay, 1), 28)))
            LabeledContent("Tenancy", value: tenancyText(t))
            if let method = t.preferredMethod {
                LabeledContent("Usually pays by", value: method.label)
            }
            if !t.specialTerms.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Special terms").font(.caption).foregroundStyle(.secondary)
                    Text(t.specialTerms)
                }
            }
            if !t.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    Text(t.notes)
                }
            }
        }
    }

    private func tenancyText(_ t: Tenant) -> String {
        let start = t.startDate.map { Fmt.date($0) } ?? "Not set"
        let end = t.endDate.map { Fmt.date($0) } ?? "ongoing"
        return start + " to " + end
    }

    private func manageSection(_ t: Tenant) -> some View {
        Section {
            Button {
                sheet = .refund
            } label: {
                Label("Record a refund to the tenant", systemImage: "arrow.uturn.backward.circle")
            }
            if t.status != .vacated {
                Button {
                    sheet = .moveOut
                } label: {
                    Label("Move out and settle", systemImage: "door.left.hand.open")
                }
            }
            if t.isArchived {
                Button {
                    store.setTenantArchived(t.id, false)
                } label: {
                    Label("Restore tenant", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(role: .destructive) {
                    confirmArchive = true
                } label: {
                    Label("Archive tenant", systemImage: "archivebox")
                }
            }
        } footer: {
            Text("Archived tenants keep their full history and can be restored from Settings → Archived.")
        }
    }
}

struct PromiseRow: View {
    let promise: PaymentPromise
    let status: PromiseStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.inr(promise.amount) + " by " + Fmt.date(promise.promisedDate))
                if !promise.note.isEmpty {
                    Text(promise.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TagLabel(text: status.label, color: color)
        }
    }

    private var color: Color {
        switch status {
        case .pending: return .blue
        case .kept: return .green
        case .missed: return .red
        case .cancelled: return .gray
        }
    }
}

struct TenantPhoto: View {
    @EnvironmentObject var store: Store
    let tenant: Tenant
    @State private var item: PhotosPickerItem? = nil

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            avatar
        }
        .buttonStyle(.plain)
        .onChange(of: item) { newItem in
            load(newItem)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let id = tenant.photoID, let meta = store.attachment(id), let image = ImageTools.thumbnail(store.fileURL(meta), side: 120) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text(initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 60, height: 60)
        }
    }

    private var initials: String {
        let letters = tenant.name.split(separator: " ").prefix(2).compactMap { $0.first }
        let text = letters.map { String($0) }.joined().uppercased()
        return text.isEmpty ? "?" : text
    }

    private func load(_ newItem: PhotosPickerItem?) {
        guard let newItem = newItem else { return }
        Task {
            let raw = try? await newItem.loadTransferable(type: Data.self)
            await MainActor.run {
                if let raw = raw, let jpeg = ImageTools.jpeg(from: raw, maxSide: 800) {
                    let old = tenant.photoID
                    if let id = store.addAttachment(jpeg, ext: "jpg", name: tenant.name + " photo", kind: .photo, category: "Tenant photo") {
                        store.updateTenant(tenant.id) { $0.photoID = id }
                        if let old = old {
                            store.deleteAttachment(old)
                        }
                    }
                }
                item = nil
            }
        }
    }
}

// MARK: - Add or edit a tenant

struct TenantFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let existing: Tenant?

    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var emergency: String
    @State private var propertyID: UUID?
    @State private var unitID: UUID?
    @State private var status: TenantStatus
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var billingStart: Date?
    @State private var frequency: BillingFrequency
    @State private var dueDay: Int
    @State private var prorateFirst: Bool
    @State private var prorateLast: Bool
    @State private var rentText: String
    @State private var openingText: String
    @State private var preferredMethod: PaymentMethod?
    @State private var specialTerms: String
    @State private var notes: String
    @State private var remindersOn: Bool
    @State private var useDefaultReminders: Bool
    @State private var daysBefore: Int
    @State private var overdueEvery: Int

    // Only when adding a tenant.
    @State private var depositText = ""
    @State private var depositDate = Date()
    @State private var scheduleIncrease = false
    @State private var increaseMode: EscalationMode = .percent
    @State private var increaseValueText = "5"
    @State private var increaseEvery = 11
    @State private var increaseDate = DateMath.addMonths(11, to: Date())
    @State private var agreementEnd: Date? = nil
    @State private var appliedDefaults = false
    @State private var pendingSave: Tenant? = nil
    @State private var impactText = ""

    init(tenant: Tenant?, presetPropertyID: UUID? = nil, presetUnitID: UUID? = nil) {
        existing = tenant
        let t = tenant ?? Tenant()
        _name = State(initialValue: t.name)
        _phone = State(initialValue: t.phone)
        _email = State(initialValue: t.email)
        _address = State(initialValue: t.address)
        _emergency = State(initialValue: t.emergencyContact)
        _propertyID = State(initialValue: tenant == nil ? presetPropertyID : t.propertyID)
        _unitID = State(initialValue: tenant == nil ? presetUnitID : t.unitID)
        _status = State(initialValue: t.status)
        _startDate = State(initialValue: tenant == nil ? DateMath.day(Date()) : t.startDate)
        _endDate = State(initialValue: t.endDate)
        _billingStart = State(initialValue: t.billingStartDate == t.startDate ? nil : t.billingStartDate)
        _frequency = State(initialValue: t.frequency)
        _dueDay = State(initialValue: min(max(t.dueDay, 1), 28))
        _prorateFirst = State(initialValue: t.prorateFirst)
        _prorateLast = State(initialValue: t.prorateLast)
        let firstRent = t.rentHistory.sorted { $0.effectiveDate < $1.effectiveDate }.first?.amount ?? 0
        _rentText = State(initialValue: amountString(firstRent))
        _openingText = State(initialValue: amountString(t.openingBalance))
        _preferredMethod = State(initialValue: t.preferredMethod)
        _specialTerms = State(initialValue: t.specialTerms)
        _notes = State(initialValue: t.notes)
        _remindersOn = State(initialValue: t.reminders.enabled)
        _useDefaultReminders = State(initialValue: t.reminders.useDefaults)
        _daysBefore = State(initialValue: t.reminders.daysBefore)
        _overdueEvery = State(initialValue: t.reminders.overdueEveryDays)
    }

    private var isNew: Bool { existing == nil }
    private var screenTitle: String { isNew ? "New tenant" : "Edit tenant" }
    private var rentTitle: String { isNew ? "Monthly rent" : "Starting rent" }

    var body: some View {
        NavigationStack {
            Form {
                personSection
                propertySection
                tenancySection
                rentSection
                if isNew {
                    depositSection
                    increaseSection
                    Section("Agreement") {
                        OptionalDatePicker(title: "Agreement end date", date: $agreementEnd)
                    }
                }
                Section("Terms and notes") {
                    TextField("Special terms", text: $specialTerms, axis: .vertical)
                        .lineLimit(1...5)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }
                remindersSection
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: applyDefaults)
            .onChange(of: propertyID) { _ in
                fixUnit()
            }
            .confirmationDialog("This changes months already billed", isPresented: pendingBinding, titleVisibility: .visible) {
                Button("Save changes") {
                    if let t = pendingSave {
                        commit(t)
                    }
                    pendingSave = nil
                }
            } message: {
                Text(impactText)
            }
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pendingSave != nil }, set: { if !$0 { pendingSave = nil } })
    }

    private var personSection: some View {
        Section {
            TextField("Name (required)", text: $name)
                .textContentType(.name)
            TextField("Mobile number", text: $phone)
                .keyboardType(.phonePad)
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Address", text: $address, axis: .vertical)
                .lineLimit(1...3)
            TextField("Emergency contact", text: $emergency)
        } header: {
            Text("Tenant")
        } footer: {
            Text("Only the name is required. Everything else can be added later.")
        }
    }

    private var propertySection: some View {
        Section {
            Picker("Property", selection: $propertyID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(store.activeProperties) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            if let p = store.property(propertyID), !p.units.isEmpty {
                Picker("Unit", selection: $unitID) {
                    Text("Not set").tag(Optional<UUID>.none)
                    ForEach(p.units) { u in
                        Text(u.name).tag(Optional(u.id))
                    }
                }
            }
            Picker("Status", selection: $status) {
                ForEach(TenantStatus.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
        } header: {
            Text("Property")
        } footer: {
            if let warning = occupiedWarning {
                Text(warning).foregroundStyle(.orange)
            }
        }
    }

    private var occupiedWarning: String? {
        guard let unit = unitID else { return nil }
        let others = store.data.tenants.filter { $0.id != existing?.id && Portfolio.isLive($0) && $0.unitID == unit }
        guard let other = others.first else { return nil }
        return other.name + " already lives in this unit."
    }

    private var tenancySection: some View {
        Section {
            OptionalDatePicker(title: "Tenancy start date", date: $startDate)
            OptionalDatePicker(title: "Tenancy end / move-out date", date: $endDate)
            OptionalDatePicker(title: "Start billing from a later month", date: $billingStart)
            Picker("Billing", selection: $frequency) {
                ForEach(BillingFrequency.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker("Rent due on", selection: $dueDay) {
                ForEach(1...28, id: \.self) { day in
                    Text(Fmt.ordinal(day) + " of the month").tag(day)
                }
            }
            Toggle("Part-month rent in the first month", isOn: $prorateFirst)
            Toggle("Part-month rent in the last month", isOn: $prorateLast)
        } header: {
            Text("Tenancy and billing")
        } footer: {
            Text("For a tenant who moved in before you started using RentBook, start billing from this month: that month is billed in full. Enter any older unpaid rent as older dues below.")
        }
    }

    private var rentSection: some View {
        Section {
            MoneyField(title: rentTitle, text: $rentText)
            MoneyField(title: "Older pending dues", text: $openingText)
            Picker("Usually pays by", selection: $preferredMethod) {
                Text("Not set").tag(Optional<PaymentMethod>.none)
                ForEach(PaymentMethod.selectable) { m in
                    Text(m.label).tag(Optional(m))
                }
            }
        } header: {
            Text("Rent")
        } footer: {
            if !isNew {
                Text("The starting rent applies from the start of billing, so changing it changes every month since then. For a new rent from a date, use Rent increases → Change the rent by hand.")
            }
        }
    }

    private var depositSection: some View {
        Section("Security deposit") {
            MoneyField(title: "Deposit received", text: $depositText)
            if parseAmount(depositText) != nil {
                DatePicker("Received on", selection: $depositDate, displayedComponents: .date)
            }
        }
    }

    private var increaseSection: some View {
        Section {
            Toggle("Schedule rent increases", isOn: $scheduleIncrease)
            if scheduleIncrease {
                Picker("Increase by", selection: $increaseMode) {
                    ForEach(EscalationMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(increaseMode == .percent ? "Percentage" : "Amount (₹)")
                    Spacer()
                    TextField("5", text: $increaseValueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                Stepper("Every \(increaseEvery) months", value: $increaseEvery, in: 1...120)
                DatePicker("First increase on", selection: $increaseDate, displayedComponents: .date)
            }
        } header: {
            Text("Rent increases")
        } footer: {
            Text("Increases are never applied automatically. RentBook reminds you and asks you to approve each one.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Reminders for this tenant", isOn: $remindersOn)
            if remindersOn {
                Toggle("Use my usual reminder settings", isOn: $useDefaultReminders)
                if !useDefaultReminders {
                    Stepper("Remind \(daysBefore) day" + (daysBefore == 1 ? "" : "s") + " before", value: $daysBefore, in: 0...15)
                    Stepper("Repeat overdue every \(overdueEvery) day" + (overdueEvery == 1 ? "" : "s"), value: $overdueEvery, in: 1...30)
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    private func applyDefaults() {
        guard isNew, !appliedDefaults else { return }
        appliedDefaults = true
        let s = store.settings
        dueDay = min(max(s.defaultDueDay, 1), 28)
        prorateFirst = s.defaultProrate
        prorateLast = s.defaultProrate
        increaseMode = s.defaultEscalationMode
        increaseValueText = Fmt.number(s.defaultEscalationValue)
        increaseEvery = max(1, s.defaultEscalationMonths)
        increaseDate = DateMath.addMonths(increaseEvery, to: startDate ?? Date())
        daysBefore = s.remindDaysBefore
        overdueEvery = s.overdueRepeatDays
    }

    private func fixUnit() {
        guard let unit = unitID else { return }
        if let p = store.property(propertyID), p.units.contains(where: { $0.id == unit }) { return }
        unitID = nil
    }

    private func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let t = buildTenant()
        if let old = existing {
            let grace = store.settings.gracePeriodDays
            let before = Ledger.ledger(for: old, graceDays: grace).net
            let after = Ledger.ledger(for: t, graceDays: grace).net
            if before != after {
                impactText = "The balance goes from " + balanceText(before) + " to " + balanceText(after)
                    + ". Months already billed are worked out again with these details."
                pendingSave = t
                return
            }
        }
        commit(t)
    }

    private func balanceText(_ net: Int) -> String {
        if net > 0 { return Fmt.inr(net) + " owed" }
        if net < 0 { return Fmt.inr(-net) + " in credit" }
        return "nothing owed"
    }

    private func commit(_ t: Tenant) {
        store.saveTenant(t, isNew: isNew, changes: changeList(t))
        dismiss()
    }

    /// What changed, for the change history.
    private func changeList(_ t: Tenant) -> String {
        guard let old = existing else { return "" }
        var parts: [String] = []
        let oldRent = old.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
        let newRent = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
        if oldRent != newRent { parts.append("starting rent " + Fmt.inr(oldRent) + " → " + Fmt.inr(newRent)) }
        if old.openingBalance != t.openingBalance {
            parts.append("older dues " + Fmt.inr(old.openingBalance) + " → " + Fmt.inr(t.openingBalance))
        }
        if old.frequency != t.frequency { parts.append("billing " + old.frequency.label + " → " + t.frequency.label) }
        if old.dueDay != t.dueDay { parts.append("due day \(old.dueDay) → \(t.dueDay)") }
        if old.startDate != t.startDate { parts.append("start date changed") }
        if old.billingStartDate != t.billingStartDate { parts.append("billing start changed") }
        if old.endDate != t.endDate { parts.append("move-out date changed") }
        if old.prorateFirst != t.prorateFirst || old.prorateLast != t.prorateLast { parts.append("part-month setting changed") }
        if old.status != t.status { parts.append("status " + old.status.label + " → " + t.status.label) }
        if old.propertyID != t.propertyID || old.unitID != t.unitID { parts.append("property or unit changed") }
        return parts.joined(separator: ", ")
    }

    private func buildTenant() -> Tenant {
        var t = existing ?? Tenant()
        t.name = clean(name)
        t.phone = clean(phone)
        t.email = clean(email)
        t.address = clean(address)
        t.emergencyContact = clean(emergency)
        t.propertyID = propertyID
        t.unitID = propertyID == nil ? nil : unitID
        t.status = status
        t.startDate = startDate.map { DateMath.day($0) }
        t.endDate = endDate.map { DateMath.day($0) }
        if status == .vacated && t.endDate == nil {
            t.endDate = DateMath.day(Date())
        }
        t.billingStartDate = billingStart.map { DateMath.day($0) }
        t.frequency = frequency
        t.dueDay = dueDay
        t.prorateFirst = prorateFirst
        t.prorateLast = prorateLast
        t.openingBalance = parseAmount(openingText) ?? 0
        t.preferredMethod = preferredMethod
        t.specialTerms = clean(specialTerms)
        t.notes = clean(notes)
        t.reminders = TenantReminderPrefs(enabled: remindersOn, useDefaults: useDefaultReminders,
                                          daysBefore: daysBefore, overdueEveryDays: overdueEvery)

        let rentFrom = t.billingStartDate ?? t.startDate ?? DateMath.day(Date())
        if let rent = parseAmount(rentText), rent > 0 {
            let history = t.rentHistory
            if let first = history.indices.min(by: { history[$0].effectiveDate < history[$1].effectiveDate }) {
                t.rentHistory[first].amount = rent
                t.rentHistory[first].effectiveDate = rentFrom
            } else {
                t.rentHistory = [RentChange(effectiveDate: rentFrom, amount: rent, reason: "Starting rent")]
            }
        }

        if isNew {
            if let deposit = parseAmount(depositText), deposit > 0 {
                t.deposits = [DepositEntry(kind: .received, date: DateMath.day(depositDate), amount: deposit, reason: "At move-in")]
            }
            if scheduleIncrease, let value = parseDecimal(increaseValueText), value > 0 {
                t.escalation = EscalationRule(mode: increaseMode, value: value, everyMonths: increaseEvery,
                                              nextDate: DateMath.day(increaseDate), clause: "")
            }
            if let end = agreementEnd {
                var agreement = Agreement()
                agreement.startDate = t.startDate ?? DateMath.day(Date())
                agreement.endDate = DateMath.day(end)
                agreement.reminderDays = store.settings.agreementDaysBefore
                t.agreements = [agreement]
            }
            t.recurringCharges = store.settings.defaultRecurringCharges.map { (template: RecurringCharge) -> RecurringCharge in
                var copy = template
                copy.id = UUID()
                copy.startDate = nil
                copy.endDate = nil
                return copy
            }
            t.createdAt = Date()
        }
        return t
    }
}
