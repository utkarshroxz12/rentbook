//  HandoverViews.swift
//  Move-in and move-out handovers: the date, meter readings, the property's condition,
//  keys given and returned, photos, and the final settlement when a tenant leaves.

import SwiftUI

enum HandoverSheet: Identifiable {
    case edit(HandoverKind, UUID?)
    case moveOut

    var id: String {
        switch self {
        case .edit(let kind, let id): return kind.rawValue + (id?.uuidString ?? "new")
        case .moveOut: return "moveOut"
        }
    }
}

struct HandoversView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID

    @State private var sheet: HandoverSheet? = nil
    @State private var share: ShareItem? = nil

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        List {
            handoverSection(.moveIn, t)
            handoverSection(.moveOut, t)
            if t.finalSettlement != nil {
                Section {
                    NavigationLink(value: Route.finalSettlement(t.id)) {
                        Label(L("Final settlement", "Final hisaab"), systemImage: "checkmark.seal")
                    }
                }
            }
        }
        .navigationTitle(L("Move-in and move-out", "Aana aur jaana"))
        .sheet(item: $sheet) { which in
            switch which {
            case .edit(let kind, let id):
                HandoverFormView(tenantID: tenantID, kind: kind, existing: t.handovers.first { $0.id == id })
                    .environmentObject(store)
            case .moveOut:
                SettlementView(tenantID: tenantID).environmentObject(store)
            }
        }
    }

    private func handoverSection(_ kind: HandoverKind, _ t: Tenant) -> some View {
        let list = t.handovers.filter { $0.kind == kind }.sorted { $0.date > $1.date }
        return Section {
            ForEach(list) { h in
                Button {
                    sheet = .edit(kind, h.id)
                } label: {
                    HandoverSummary(handover: h)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if list.isEmpty {
                if kind == .moveIn {
                    Button {
                        sheet = .edit(.moveIn, nil)
                    } label: {
                        Label(L("Record the move-in handover", "Move-in handover record karein"), systemImage: "key")
                    }
                } else if t.status != .vacated {
                    Button {
                        sheet = .moveOut
                    } label: {
                        Label(L("Move out and settle", "Move out aur final hisaab"), systemImage: "door.left.hand.open")
                    }
                } else {
                    Button {
                        sheet = .edit(.moveOut, nil)
                    } label: {
                        Label(L("Record the move-out handover", "Move-out handover record karein"), systemImage: "key")
                    }
                }
            }
        } header: {
            Text(kind == .moveIn ? L("Move-in", "Move-in") : L("Move-out", "Move-out"))
        } footer: {
            if kind == .moveIn && list.isEmpty {
                Text(L("Note the meter readings, the keys given and the state of the place, with photos, on the day the tenant moves in.",
                       "Tenant aane ke din meter reading, di gayi chaabiyan aur jagah ki halat photo ke saath likhein."))
            }
        }
    }
}

struct HandoverSummary: View {
    let handover: Handover

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.date(handover.date))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if handover.keysIssued > 0 {
                    Text(keysText)
                        .font(.caption)
                        .foregroundStyle(handover.kind == .moveOut && handover.keysMissing > 0 ? Color.red : Color.secondary)
                }
            }
            if !readings.isEmpty {
                Text(readings)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !handover.condition.isEmpty {
                Text(handover.condition)
                    .font(.caption)
                    .lineLimit(2)
            }
            if !handover.attachmentIDs.isEmpty {
                Text(L("\(handover.attachmentIDs.count) photos or files", "\(handover.attachmentIDs.count) photo ya file"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keysText: String {
        if handover.kind == .moveOut {
            return L("Keys returned \(handover.keysReturned) of \(handover.keysIssued)", "Chaabiyan wapas \(handover.keysReturned)/\(handover.keysIssued)")
        }
        return L("\(handover.keysIssued) keys given", "\(handover.keysIssued) chaabiyan di")
    }

    private var readings: String {
        var parts: [String] = []
        if let e = handover.electricityReading { parts.append(MeterKind.electricity.label + " " + Fmt.number(e)) }
        if let w = handover.waterReading { parts.append(MeterKind.water.label + " " + Fmt.number(w)) }
        return parts.joined(separator: " · ")
    }
}

struct HandoverFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    let kind: HandoverKind
    let existing: Handover?

    @State private var handoverID: UUID
    @State private var date: Date
    @State private var electricityText: String
    @State private var waterText: String
    @State private var condition: String
    @State private var keys: [KeyItem]
    @State private var notes: String
    @State private var attachmentIDs: [UUID]
    @State private var added: [UUID] = []
    @State private var prepared = false

    init(tenantID: UUID, kind: HandoverKind, existing: Handover?) {
        self.tenantID = tenantID
        self.kind = kind
        self.existing = existing
        let h = existing ?? Handover()
        _handoverID = State(initialValue: h.id)
        _date = State(initialValue: h.date)
        _electricityText = State(initialValue: h.electricityReading.map { Fmt.number($0) } ?? "")
        _waterText = State(initialValue: h.waterReading.map { Fmt.number($0) } ?? "")
        _condition = State(initialValue: h.condition)
        _keys = State(initialValue: h.keys)
        _notes = State(initialValue: h.notes)
        _attachmentIDs = State(initialValue: h.attachmentIDs)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L("Date", "Tareekh"), selection: $date, displayedComponents: .date)
                    readingField(MeterKind.electricity.label, $electricityText)
                    readingField(MeterKind.water.label, $waterText)
                } footer: {
                    Text(L("Meter readings are added to the tenant's electricity and water history.",
                           "Meter reading tenant ki bijli-paani history mein judegi."))
                }
                Section {
                    TextField(L("Condition of the place, fittings, paint, furniture", "Jagah ki halat, fittings, paint, furniture"), text: $condition, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text(L("Condition", "Halat"))
                }
                keysSection
                AttachmentsSection(title: L("Photos and papers", "Photo aur kaagaz"), ids: attachmentIDs, category: "Handover") { id in
                    attachmentIDs.append(id)
                    added.append(id)
                }
                Section {
                    TextField(L("Notes", "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                }
            }
            .attachmentHost()
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
        }
    }

    private var keysSection: some View {
        Section {
            ForEach($keys) { key in
                KeyEditorRow(key: key, showReturned: kind == .moveOut)
            }
            .onDelete { offsets in
                keys.remove(atOffsets: offsets)
            }
            Button {
                keys.append(KeyItem())
            } label: {
                Label(L("Add a key", "Chaabi jodein"), systemImage: "plus")
            }
        } header: {
            Text(L("Keys", "Chaabiyan"))
        } footer: {
            if kind == .moveOut {
                let missing = keys.reduce(0) { $0 + max(0, $1.count - $1.returned) }
                if missing > 0 {
                    Text(L("\(missing) not returned.", "\(missing) wapas nahi aayi."))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func readingField(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(L("Reading", "Reading"), text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        guard existing == nil, let t = store.tenant(tenantID) else { return }
        if kind == .moveIn, let start = t.startDate {
            date = start
        }
        if kind == .moveOut {
            if let end = t.endDate { date = end }
            // Start from the keys given at move-in.
            if keys.isEmpty, let moveIn = store.handover(.moveIn, of: t) {
                keys = moveIn.keys.map { KeyItem(name: $0.name, count: $0.count, returned: $0.count) }
            }
        }
        if keys.isEmpty && kind == .moveIn {
            keys = [KeyItem(name: L("Main door", "Main door"), count: 2, returned: 0)]
        }
    }

    private func cancel() {
        // Files added to a handover that is not saved are removed again.
        for id in added {
            store.deleteAttachment(id)
        }
        dismiss()
    }

    private func save() {
        var h = existing ?? Handover()
        h.id = handoverID
        h.kind = kind
        h.date = date
        h.electricityReading = parseDecimal(electricityText).flatMap { $0 >= 0 ? $0 : nil }
        h.waterReading = parseDecimal(waterText).flatMap { $0 >= 0 ? $0 : nil }
        h.condition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        h.keys = keys.map { k in
            var key = k
            key.name = k.name.trimmingCharacters(in: .whitespacesAndNewlines)
            key.returned = min(max(0, k.returned), k.count)
            return key
        }
        h.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        h.attachmentIDs = attachmentIDs
        store.saveHandover(h, tenantID: tenantID)
        dismiss()
    }
}

/// One key: its name, how many were given and, at move-out, how many came back.
struct KeyEditorRow: View {
    @Binding var key: KeyItem
    let showReturned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("Key, e.g. Main door", "Chaabi, jaise Main door"), text: $key.name)
            Stepper(L("Given: ", "Di: ") + String(key.count), value: $key.count, in: 0...20)
            if showReturned {
                Stepper(L("Returned: ", "Wapas: ") + String(key.returned), value: $key.returned, in: 0...max(key.count, 0))
            }
        }
        .padding(.vertical, 2)
    }
}

/// At move-out: how many of one key came back.
struct KeyReturnRow: View {
    @Binding var key: KeyItem

    var body: some View {
        Stepper((key.name.isEmpty ? L("Key", "Chaabi") : key.name) + L(": returned ", ": wapas ") + String(key.returned) + "/" + String(key.count),
                value: $key.returned, in: 0...max(key.count, 0))
    }
}

// MARK: - Final settlement

struct FinalSettlementView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var share: ShareItem? = nil

    var body: some View {
        if let t = store.tenant(tenantID), let s = t.finalSettlement {
            content(t, s)
        } else {
            Text(L("No final settlement recorded.", "Koi final hisaab record nahi."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant, _ s: FinalSettlement) -> some View {
        List {
            Section {
                LabeledContent(L("Moved out", "Ghar chhoda"), value: Fmt.date(s.date))
                if let start = t.startDate {
                    LabeledContent(L("Tenancy", "Kirayedari"), value: Fmt.date(start) + " – " + Fmt.date(s.date))
                }
            }
            Section(L("Rent", "Rent")) {
                LabeledContent(L("Owed up to move-out", "Move-out tak baaki"), value: Fmt.inr(s.rentOwed))
                if s.utilityCharges > 0 {
                    LabeledContent(L("Including final electricity and water", "Isme aakhri bijli-paani"), value: Fmt.inr(s.utilityCharges))
                }
                if s.advanceReturned > 0 {
                    LabeledContent(L("Advance returned", "Advance wapas diya"), value: Fmt.inr(s.advanceReturned))
                }
            }
            Section(L("Security deposit", "Security deposit")) {
                LabeledContent(L("Held", "Jama tha"), value: Fmt.inr(s.depositHeld))
                if s.damages > 0 {
                    LabeledContent(L("Kept for damages", "Nuksaan ke liye rakha"), value: Fmt.inr(s.damages))
                    if !s.damagesReason.isEmpty {
                        Text(s.damagesReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if s.depositUsedForRent > 0 {
                    LabeledContent(L("Used for rent", "Rent mein liya"), value: Fmt.inr(s.depositUsedForRent))
                }
                LabeledContent(L("Refunded", "Wapas diya"), value: Fmt.inr(s.depositRefund) + (s.depositRefund > 0 ? " · " + s.refundMethod.label : ""))
            }
            Section {
                LabeledContent(L("Still owed by the tenant", "Tenant par ab bhi baaki"), value: Fmt.inr(s.balanceDue))
                    .font(.headline)
                if !s.notes.isEmpty {
                    Text(s.notes)
                }
            }
            if let h = store.handover(.moveOut, of: t) {
                Section(L("Move-out handover", "Move-out handover")) {
                    HandoverSummary(handover: h)
                }
            }
            Section {
                Button {
                    if let url = PDFMaker.finalSettlement(tenant: t, place: store.place(of: t), settlement: s,
                                                          handover: store.handover(.moveOut, of: t), settings: store.settings) {
                        share = ShareItem(url: url)
                    }
                } label: {
                    Label(L("Share as PDF", "PDF share karein"), systemImage: "doc.richtext")
                }
            }
        }
        .navigationTitle(L("Final settlement", "Final hisaab"))
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
    }
}

extension PDFMaker {
    static func finalSettlement(tenant: Tenant, place: String, settlement s: FinalSettlement, handover: Handover?,
                                settings: AppSettings) -> URL? {
        render(title: L("Final settlement", "Final hisaab"), fileName: L("Final settlement ", "Final hisaab ") + tenant.name) { w in
            w.text(L("FINAL SETTLEMENT", "FINAL HISAAB"), font: UIFont.boldSystemFont(ofSize: 20), after: 2)
            w.text(L("Date: ", "Tareekh: ") + Fmt.date(s.date), font: UIFont.systemFont(ofSize: 11), color: .darkGray)
            let landlord = [settings.landlordName, settings.landlordPhone].filter { !$0.isEmpty }
            if !landlord.isEmpty {
                w.text(L("Landlord: ", "Makaan malik: ") + landlord.joined(separator: " · "), font: UIFont.systemFont(ofSize: 11), color: .darkGray)
            }
            w.rule()
            w.pair(L("Tenant", "Tenant"), tenant.name, bold: true)
            if !place.isEmpty {
                w.pair(L("Property", "Property"), place)
            }
            if let start = tenant.startDate {
                w.pair(L("Tenancy", "Kirayedari"), Fmt.date(start) + " – " + Fmt.date(s.date))
            }
            w.space(6)
            w.pair(L("Rent and charges owed", "Rent aur charges baaki"), Fmt.inr(s.rentOwed))
            if s.utilityCharges > 0 {
                w.pair(L("of which electricity and water", "jisme bijli aur paani"), Fmt.inr(s.utilityCharges))
            }
            if s.advanceReturned > 0 {
                w.pair(L("Advance rent returned", "Advance rent wapas"), Fmt.inr(s.advanceReturned))
            }
            w.pair(L("Security deposit held", "Security deposit jama"), Fmt.inr(s.depositHeld))
            if s.damages > 0 {
                w.pair(L("Kept for damages", "Nuksaan ke liye rakha"), Fmt.inr(s.damages) + (s.damagesReason.isEmpty ? "" : "\n" + s.damagesReason))
            }
            if s.depositUsedForRent > 0 {
                w.pair(L("Deposit used for rent", "Deposit se rent"), Fmt.inr(s.depositUsedForRent))
            }
            w.pair(L("Deposit refunded", "Deposit wapas"), Fmt.inr(s.depositRefund) + (s.depositRefund > 0 ? " · " + s.refundMethod.label : ""))
            w.rule()
            w.pair(s.balanceDue > 0 ? L("Still to be paid by the tenant", "Tenant ko abhi dena hai") : L("Balance", "Balance"),
                   s.balanceDue > 0 ? Fmt.inr(s.balanceDue) : L("Nil", "Kuch nahi"), bold: true)
            if let h = handover {
                w.space(10)
                w.text(L("Handover", "Handover"), font: UIFont.boldSystemFont(ofSize: 13), after: 4)
                if let e = h.electricityReading {
                    w.pair(L("Electricity meter", "Bijli meter"), Fmt.number(e))
                }
                if let water = h.waterReading {
                    w.pair(L("Water meter", "Paani meter"), Fmt.number(water))
                }
                if h.keysIssued > 0 {
                    let list = h.keys.map { $0.name + " \(min($0.returned, $0.count))/\($0.count)" }.joined(separator: ", ")
                    w.pair(L("Keys returned", "Chaabiyan wapas"), "\(h.keysReturned) / \(h.keysIssued)" + (list.isEmpty ? "" : "\n" + list))
                }
                if !h.condition.isEmpty {
                    w.pair(L("Condition", "Halat"), h.condition)
                }
            }
            if !s.notes.isEmpty {
                w.pair(L("Notes", "Notes"), s.notes)
            }
            w.space(36)
            w.text(L("Landlord's signature: ", "Makaan malik ke sign: ") + "____________________     "
                   + L("Tenant's signature: ", "Tenant ke sign: ") + "____________________",
                   font: UIFont.systemFont(ofSize: 10))
        }
    }
}
