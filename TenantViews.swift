//  TenantViews.swift
//  Tenant list with search, filters and sorting; the tenant profile; the tenant form.

import SwiftUI
import PhotosUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all, paid, partial, unpaid, overdue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("Any payment status", "Koi bhi payment status")
        case .paid: return "Paid"
        case .partial: return L("Partly paid", "Aadha paid")
        case .unpaid: return L("Unpaid", "Baaki")
        case .overdue: return "Overdue"
        }
    }
}

enum AgreementFilter: String, CaseIterable, Identifiable {
    case all, active, expiring, expired, missing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("Any agreement", "Koi bhi agreement")
        case .active: return L("Agreement active", "Agreement chalu")
        case .expiring: return L("Agreement expiring", "Agreement khatam hone wala")
        case .expired: return L("Agreement expired", "Agreement khatam")
        case .missing: return L("No agreement", "Koi agreement nahi")
        }
    }
}

enum TenantSort: String, CaseIterable, Identifiable {
    case name, outstanding, daysOverdue, nextDue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return L("Name", "Naam")
        case .outstanding: return L("Highest outstanding", "Sabse zyada baaki")
        case .daysOverdue: return L("Most days overdue", "Sabse zyada din overdue")
        case .nextDue: return L("Next due date", "Agli due date")
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
                        Button(L("Clear", "Hatayein")) { clearFilters() }
                            .font(.caption)
                    }
                }
            }
            if rows.isEmpty {
                Text(store.data.tenants.isEmpty ? L("No tenants yet. Tap + to add one.", "Abhi koi tenant nahi. + dabakar jodein.") : L("No tenants match.", "Aisa koi tenant nahi mila."))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { t in
                NavigationLink(value: Route.tenant(t.id)) {
                    TenantRowView(tenant: t, ledger: snap.ledgers[t.id], place: store.place(of: t))
                }
            }
        }
        .searchable(text: $query, prompt: L("Name, phone or property", "Naam, phone ya property"))
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
        if increasesSoon { parts.append(L("Increase soon", "Jaldi badhotri")) }
        if showVacated { parts.append(L("Including vacated", "Chhod chuke bhi")) }
        if sort != .name { parts.append(L("Sorted by ", "Kram: ") + sort.label.lowercased()) }
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
            Picker(L("Payment status", "Payment status"), selection: $status) {
                ForEach(StatusFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker("Property", selection: $propertyID) {
                Text(L("All properties", "Saari properties")).tag(Optional<UUID>.none)
                ForEach(store.activeProperties) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            Picker("Agreement", selection: $agreement) {
                ForEach(AgreementFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker(L("Sort by", "Kram"), selection: $sort) {
                ForEach(TenantSort.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Toggle(L("Rent increase within 60 days", "60 din mein rent badhotri"), isOn: $increasesSoon)
            Toggle(L("Show vacated tenants", "Chhod chuke tenants dikhayein"), isOn: $showVacated)
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
                    Text(L("Next due ", "Agli tareekh ") + Fmt.date(next.charge.dueDate))
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
                        Text(Fmt.inr(-l.net) + L(" credit", " credit"))
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
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ l: TenantLedger) -> some View {
        List {
            summarySection(t, l)
            actionsSection(t, l)
            moneySection(t, l)
            metersSection(t)
            promisesSection(t)
            detailsSection(t)
            AttachmentsSection(title: L("ID and documents", "ID aur documents"), ids: t.documentIDs, category: "Tenant document") { id in
                store.updateTenant(t.id) { $0.documentIDs.append(id) }
            }
            manageSection(t)
        }
        .attachmentHost()
        .navigationTitle(t.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("Edit", "Badlein")) { sheet = .edit }
            }
        }
        .sheet(item: $sheet) { which in
            sheetView(which, t)
        }
        .confirmationDialog(L("Archive ", "Archive karein: ") + t.name + "?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button(L("Archive tenant", "Tenant archive karein"), role: .destructive) {
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
            parts.append(L(t.name + " is still marked as living there, so rent keeps being billed but won't show on the home screen, in reminders or in reports. Use Move out and settle first if they have left.",
                           t.name + " abhi bhi wahan rehte hain aisa mark hai, isliye rent banta rahega par home screen, reminders ya reports mein nahi dikhega. Agar woh chale gaye hain to pehle Move out aur final hisaab karein."))
        }
        if l.net > 0 {
            parts.append(L("They still owe " + Fmt.inr(l.net) + ".", "Unpar abhi bhi " + Fmt.inr(l.net) + " baaki hai."))
        }
        let held = Ledger.deposit(of: t).held
        if held > 0 {
            parts.append(L(Fmt.inr(held) + " of deposit is still held.", Fmt.inr(held) + " deposit abhi bhi jama hai."))
        }
        parts.append(L("Their history is kept, and you can restore them from Settings → Archived.", "Unki history rahegi, aur Settings → Archived se wapas la sakte hain."))
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
                    Text(place.isEmpty ? L("No property assigned", "Koi property nahi di") : place)
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
                    Text(concat(L("This period ", "Is baar "), Fmt.inr(l.currentDue), L(" · Earlier dues ", " · Purana baaki "), Fmt.inr(l.arrears)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let oldest = l.oldestUnpaid {
                    Text(L("Oldest unpaid: ", "Sabse purana baaki: ") + oldest.charge.title + L(" · \(l.daysOverdue) days", " · \(l.daysOverdue) din"))
                        .font(.caption)
                        .foregroundStyle(l.overdue > 0 ? Color.red : Color.secondary)
                }
            }
            .padding(.vertical, 4)
            if let next = l.nextRentLine {
                LabeledContent(L("Next rent due", "Agla rent"), value: Fmt.date(next.charge.dueDate) + " · " + Fmt.inr(next.charge.amount))
            }
            if let last = l.lastPaymentDate {
                LabeledContent(L("Last payment", "Aakhri payment"), value: Fmt.date(last))
            }
        }
    }

    private func balanceTitle(_ l: TenantLedger) -> String {
        if l.net > 0 { return L("Outstanding", "Baaki") }
        if l.net < 0 { return L("In credit (paid ahead)", "Credit mein (pehle diya)") }
        return L("All clear", "Sab saaf")
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
                Label(L("Record payment", "Payment record karein"), systemImage: "indianrupeesign.circle.fill")
            }
            Button {
                sheet = .message(l.overdue > 0 ? .firmReminder : .politeReminder)
            } label: {
                Label(L("Send WhatsApp message", "WhatsApp message bhejein"), systemImage: "message.fill")
            }
            if let url = Messages.callURL(phone: t.phone) {
                Button {
                    store.updateTenant(t.id) { $0.contacts.append(ContactLog(kind: .call, note: "Phone call")) }
                    openURL(url)
                } label: {
                    Label(L("Call ", "Call karein: ") + t.phone, systemImage: "phone.fill")
                }
            }
            if let url = Messages.emailURL(t.email) {
                Button {
                    openURL(url)
                } label: {
                    Label(L("Email ", "Email karein: ") + t.email, systemImage: "envelope.fill")
                }
            }
        }
    }

    private func moneySection(_ t: Tenant, _ l: TenantLedger) -> some View {
        let deposit = Ledger.deposit(of: t)
        let increase = Escalation.next(for: t)
        let agreement = Agreements.current(of: t)
        let paymentCount = t.payments.filter { !$0.isReversed }.count
        return Section(L("Rent and money", "Rent aur paisa")) {
            NavigationLink(value: Route.tenantLedger(t.id)) {
                linkRow(L("Ledger and payments", "Ledger aur payment"), "list.bullet.rectangle", L("\(paymentCount) payment" + (paymentCount == 1 ? "" : "s"), "\(paymentCount) payment"))
            }
            NavigationLink(value: Route.charges(t.id)) {
                linkRow(L("Extra charges and discounts", "Extra charges aur chhoot"), "plus.forwardslash.minus", "\(t.recurringCharges.count + t.adjustments.filter { !$0.isReversed }.count)")
            }
            NavigationLink(value: Route.deposits(t.id)) {
                linkRow(L("Security deposit", "Security deposit"), "banknote", Fmt.inr(deposit.held) + L(" held", " jama"))
            }
            NavigationLink(value: Route.increases(t.id)) {
                linkRow(L("Rent increases", "Rent badhotri"), "arrow.up.right.circle", increaseText(increase))
            }
            NavigationLink(value: Route.agreements(t.id)) {
                linkRow("Agreements", "doc.text", agreement.map { Agreements.status($0).label } ?? L("None yet", "Abhi koi nahi"))
            }
            NavigationLink(value: Route.communication(t.id)) {
                linkRow(L("Messages and follow-ups", "Messages aur follow-up"), "bubble.left.and.bubble.right", "\(t.contacts.count)")
            }
        }
    }

    private func metersSection(_ t: Tenant) -> some View {
        let electricity = Utilities.lastReading(.electricity, of: t)
        let water = Utilities.lastReading(.water, of: t)
        let moveIn = store.handover(.moveIn, of: t)
        var meterText = L("No readings", "Reading nahi")
        if let r = electricity ?? water {
            meterText = L("Last ", "Pichhli ") + Fmt.date(r.date)
        }
        return Section(L("Meters and handover", "Meter aur handover")) {
            NavigationLink(value: Route.utilities(t.id)) {
                linkRow(L("Electricity and water", "Bijli aur paani"), "bolt", meterText)
            }
            NavigationLink(value: Route.handovers(t.id)) {
                linkRow(L("Move-in and move-out", "Aana aur jaana"), "key", moveIn.map { Fmt.date($0.date) } ?? L("Not recorded", "Record nahi"))
            }
            if let settlement = t.finalSettlement {
                NavigationLink(value: Route.finalSettlement(t.id)) {
                    linkRow(L("Final settlement", "Final hisaab"), "checkmark.seal", Fmt.date(settlement.date))
                }
            }
        }
    }

    private func increaseText(_ p: IncreaseProposal?) -> String {
        guard let p = p else { return L("Not scheduled", "Tay nahi") }
        return (p.isDue ? L("Due · ", "Due · ") : "") + Fmt.date(p.date)
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
                Label(L("Record a payment promise", "Payment ka vaada record karein"), systemImage: "hand.raised")
            }
        } header: {
            Text(L("Payment promises", "Payment ke vaade"))
        }
    }

    private func detailsSection(_ t: Tenant) -> some View {
        Section(L("Details", "Details")) {
            Group {
                if !t.phone.isEmpty { LabeledContent(L("Mobile", "Mobile"), value: t.phone) }
                if !t.email.isEmpty { LabeledContent(L("Email", "Email"), value: t.email) }
                if !t.address.isEmpty { LabeledContent(L("Address", "Pata"), value: t.address) }
                if !t.emergencyContact.isEmpty { LabeledContent(L("Emergency contact", "Emergency contact"), value: t.emergencyContact) }
            }
            LabeledContent(L("Monthly rent", "Mahine ka rent"), value: Fmt.inr(Ledger.currentRent(of: t)))
            LabeledContent(L("Billing", "Billing"), value: t.frequency.label + L(", due on the " + Fmt.ordinal(min(max(t.dueDay, 1), 28)),
                                                                                    ", mahine ki \(min(max(t.dueDay, 1), 28)) tareekh ko"))
            LabeledContent(L("Tenancy", "Kirayedari"), value: tenancyText(t))
            if let method = t.preferredMethod {
                LabeledContent(L("Usually pays by", "Aam taur par kaise deta hai"), value: method.label)
            }
            if !t.specialTerms.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Special terms", "Khaas sharten")).font(.caption).foregroundStyle(.secondary)
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
        let start = t.startDate.map { Fmt.date($0) } ?? L("Not set", "Set nahi")
        let end = t.endDate.map { Fmt.date($0) } ?? L("ongoing", "abhi chalu")
        return start + L(" to ", " – ") + end
    }

    private func manageSection(_ t: Tenant) -> some View {
        Section {
            Button {
                sheet = .refund
            } label: {
                Label(L("Record a refund to the tenant", "Tenant ko refund record karein"), systemImage: "arrow.uturn.backward.circle")
            }
            if t.status != .vacated {
                Button {
                    sheet = .moveOut
                } label: {
                    Label(L("Move out and settle", "Move out aur final hisaab"), systemImage: "door.left.hand.open")
                }
            }
            if t.isArchived {
                Button {
                    store.setTenantArchived(t.id, false)
                } label: {
                    Label(L("Restore tenant", "Tenant wapas layein"), systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(role: .destructive) {
                    confirmArchive = true
                } label: {
                    Label(L("Archive tenant", "Tenant archive karein"), systemImage: "archivebox")
                }
            }
        } footer: {
            Text(L("Archived tenants keep their full history and can be restored from Settings → Archived.", "Archive kiye tenants ki poori history rehti hai aur Settings → Archived se wapas la sakte hain."))
        }
    }
}

struct PromiseRow: View {
    let promise: PaymentPromise
    let status: PromiseStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(Fmt.inr(promise.amount) + " by " + Fmt.date(promise.promisedDate), Fmt.date(promise.promisedDate) + " tak " + Fmt.inr(promise.amount)))
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
    private var screenTitle: String { isNew ? L("New tenant", "Naya tenant") : L("Edit tenant", "Tenant badlein") }
    private var rentTitle: String { isNew ? L("Monthly rent", "Mahine ka rent") : L("Starting rent", "Shuru ka rent") }

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
                        OptionalDatePicker(title: L("Agreement end date", "Agreement khatam hone ki tareekh"), date: $agreementEnd)
                    }
                }
                Section(L("Terms and notes", "Sharten aur notes")) {
                    TextField(L("Special terms", "Khaas sharten"), text: $specialTerms, axis: .vertical)
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
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: applyDefaults)
            .onChange(of: propertyID) { _ in
                fixUnit()
            }
            .confirmationDialog(L("This changes months already billed", "Isse bane hue mahine badlenge"), isPresented: pendingBinding, titleVisibility: .visible) {
                Button(L("Save changes", "Badlav save karein")) {
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
            TextField(L("Name (required)", "Naam (zaroori)"), text: $name)
                .textContentType(.name)
            TextField(L("Mobile number", "Mobile number"), text: $phone)
                .keyboardType(.phonePad)
            TextField(L("Email", "Email"), text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField(L("Address", "Pata"), text: $address, axis: .vertical)
                .lineLimit(1...3)
            TextField(L("Emergency contact", "Emergency contact"), text: $emergency)
        } header: {
            Text("Tenant")
        } footer: {
            Text(L("Only the name is required. Everything else can be added later.", "Sirf naam zaroori hai. Baaki sab baad mein jod sakte hain."))
        }
    }

    private var propertySection: some View {
        Section {
            Picker("Property", selection: $propertyID) {
                Text(L("None", "Koi nahi")).tag(Optional<UUID>.none)
                ForEach(store.activeProperties) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            if let p = store.property(propertyID), !p.units.isEmpty {
                Picker(L("Unit", "Unit"), selection: $unitID) {
                    Text(L("Not set", "Set nahi")).tag(Optional<UUID>.none)
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
        return L(other.name + " already lives in this unit.", other.name + " pehle se is unit mein rehte hain.")
    }

    private var tenancySection: some View {
        Section {
            OptionalDatePicker(title: L("Tenancy start date", "Kirayedari shuru hone ki tareekh"), date: $startDate)
            OptionalDatePicker(title: L("Tenancy end / move-out date", "Kirayedari khatam / ghar chhodne ki tareekh"), date: $endDate)
            OptionalDatePicker(title: L("Start billing from a later month", "Baad ke mahine se billing shuru"), date: $billingStart)
            Picker("Billing", selection: $frequency) {
                ForEach(BillingFrequency.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            Picker(L("Rent due on", "Rent ki tareekh"), selection: $dueDay) {
                ForEach(1...28, id: \.self) { day in
                    Text(Fmt.ordinal(day) + " of the month").tag(day)
                }
            }
            Toggle(L("Part-month rent in the first month", "Pehle mahine mein aadhe mahine ka rent"), isOn: $prorateFirst)
            Toggle(L("Part-month rent in the last month", "Aakhri mahine mein aadhe mahine ka rent"), isOn: $prorateLast)
        } header: {
            Text(L("Tenancy and billing", "Kirayedari aur billing"))
        } footer: {
            Text(L("For a tenant who moved in before you started using RentBook, start billing from this month: that month is billed in full. Enter any older unpaid rent as older dues below.", "Jo tenant RentBook use karne se pehle aaye the, unki billing is mahine se shuru karein: yeh mahina poora banega. Purana baaki rent neeche purane baaki mein daalein."))
        }
    }

    private var rentSection: some View {
        Section {
            MoneyField(title: rentTitle, text: $rentText)
            MoneyField(title: L("Older pending dues", "Purana baaki"), text: $openingText)
            Picker(L("Usually pays by", "Aam taur par kaise deta hai"), selection: $preferredMethod) {
                Text(L("Not set", "Set nahi")).tag(Optional<PaymentMethod>.none)
                ForEach(PaymentMethod.selectable) { m in
                    Text(m.label).tag(Optional(m))
                }
            }
        } header: {
            Text("Rent")
        } footer: {
            if !isNew {
                Text(L("The starting rent applies from the start of billing, so changing it changes every month since then. For a new rent from a date, use Rent increases → Change the rent by hand.", "Shuru ka rent billing ki shuruaat se lagta hai, isliye ise badalne se tab se har mahina badlega. Kisi tareekh se naya rent ho to Rent badhotri → Rent khud badlein use karein."))
            }
        }
    }

    private var depositSection: some View {
        Section("Security deposit") {
            MoneyField(title: L("Deposit received", "Deposit mila"), text: $depositText)
            if parseAmount(depositText) != nil {
                DatePicker(L("Received on", "Kab mila"), selection: $depositDate, displayedComponents: .date)
            }
        }
    }

    private var increaseSection: some View {
        Section {
            Toggle(L("Schedule rent increases", "Rent badhotri tay karein"), isOn: $scheduleIncrease)
            if scheduleIncrease {
                Picker(L("Increase by", "Kitni badhotri"), selection: $increaseMode) {
                    ForEach(EscalationMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(increaseMode == .percent ? L("Percentage", "Percent") : L("Amount (₹)", "Amount (₹)"))
                    Spacer()
                    TextField("5", text: $increaseValueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                Stepper(L("Every \(increaseEvery) months", "Har \(increaseEvery) mahine"), value: $increaseEvery, in: 1...120)
                DatePicker(L("First increase on", "Pehli badhotri ki tareekh"), selection: $increaseDate, displayedComponents: .date)
            }
        } header: {
            Text(L("Rent increases", "Rent badhotri"))
        } footer: {
            Text(L("Increases are never applied automatically. RentBook reminds you and asks you to approve each one.", "Badhotri kabhi apne aap nahi lagti. RentBook yaad dilata hai aur har ek ke liye aapka approval maangta hai."))
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(L("Reminders for this tenant", "Is tenant ke reminders"), isOn: $remindersOn)
            if remindersOn {
                Toggle(L("Use my usual reminder settings", "Meri aam reminder settings use karein"), isOn: $useDefaultReminders)
                if !useDefaultReminders {
                    Stepper(L("Remind \(daysBefore) day" + (daysBefore == 1 ? "" : "s") + " before", "\(daysBefore) din pehle yaad dilayein"),
                            value: $daysBefore, in: 0...15)
                    Stepper(L("Repeat overdue every \(overdueEvery) day" + (overdueEvery == 1 ? "" : "s"), "Overdue har \(overdueEvery) din mein dobara"),
                            value: $overdueEvery, in: 1...30)
                }
            }
        } header: {
            Text(L("Reminders", "Reminders"))
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
                impactText = L("The balance goes from " + balanceText(before) + " to " + balanceText(after)
                               + ". Months already billed are worked out again with these details.",
                               "Balance " + balanceText(before) + " se " + balanceText(after) + " ho jayega. Bane hue mahine in details se dobara gine jayenge.")
                pendingSave = t
                return
            }
        }
        commit(t)
    }

    private func balanceText(_ net: Int) -> String {
        if net > 0 { return Fmt.inr(net) + L(" owed", " baaki") }
        if net < 0 { return Fmt.inr(-net) + L(" in credit", " credit") }
        return L("nothing owed", "kuch baaki nahi")
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
