//  PropertyViews.swift
//  Properties, their units, occupancy, history, photos and documents.

import SwiftUI

struct PropertyListView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var showingAdd = false

    private var properties: [RentalProperty] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.activeProperties
        guard !q.isEmpty else { return list }
        return list.filter { p in
            if p.name.lowercased().contains(q) { return true }
            if p.address.lowercased().contains(q) || p.city.lowercased().contains(q) { return true }
            if p.code.lowercased().contains(q) { return true }
            return p.units.contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        let snap = store.snapshot
        List {
            if properties.isEmpty {
                Text(query.isEmpty ? "No properties yet. Tap + to add one." : "No properties match your search.")
                    .foregroundStyle(.secondary)
            }
            ForEach(properties) { p in
                NavigationLink(value: Route.property(p.id)) {
                    PropertyRow(property: p, money: Portfolio.money(of: p, data: store.data, snapshot: snap))
                }
            }
        }
        .searchable(text: $query, prompt: "Name, address or unit")
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            PropertyFormView(property: nil).environmentObject(store)
        }
    }
}

struct PropertyRow: View {
    let property: RentalProperty
    let money: PropertyMoney

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(property.name)
                    .font(.headline)
                Text(property.code + " · " + property.type.label + " · \(money.unitsOccupied) of \(money.unitsTotal) occupied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if money.outstanding > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.inr(money.outstanding))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(money.overdue > 0 ? Color.red : Color.orange)
                    Text("outstanding")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum PropertySheet: Identifiable {
    case edit
    case addUnit
    case editUnit(UUID)
    case addTenant(UUID?)
    case addExpense

    var id: String {
        switch self {
        case .edit: return "edit"
        case .addUnit: return "addUnit"
        case .editUnit(let id): return "unit-" + id.uuidString
        case .addTenant(let id): return "tenant-" + (id?.uuidString ?? "whole")
        case .addExpense: return "expense"
        }
    }
}

struct PropertyDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let propertyID: UUID

    @State private var sheet: PropertySheet? = nil
    @State private var confirmArchive = false

    var body: some View {
        if let p = store.property(propertyID) {
            content(p)
        } else {
            Text("This property was removed.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ p: RentalProperty) -> some View {
        let snap = store.snapshot
        let money = Portfolio.money(of: p, data: store.data, snapshot: snap)
        let units = Portfolio.units(of: p, tenants: store.data.tenants)
        return List {
            headerSection(p)
            moneySection(money)
            unitsSection(p, units)
            historySection(p)
            AttachmentsSection(title: "Photos", ids: p.photoIDs, category: "Property photo") { id in
                store.updateProperty(p.id) { $0.photoIDs.append(id) }
            }
            AttachmentsSection(title: "Documents", ids: p.documentIDs, category: "Property document") { id in
                store.updateProperty(p.id) { $0.documentIDs.append(id) }
            }
            Section {
                NavigationLink(value: Route.expenses(p.id)) {
                    Label("Expenses and bills", systemImage: "wrench.and.screwdriver")
                }
                Button {
                    sheet = .addExpense
                } label: {
                    Label("Record an expense", systemImage: "plus")
                }
                if p.isArchived {
                    Button {
                        store.setPropertyArchived(p.id, false)
                    } label: {
                        Label("Restore property", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button(role: .destructive) {
                        confirmArchive = true
                    } label: {
                        Label("Archive property", systemImage: "archivebox")
                    }
                }
            }
        }
        .attachmentHost()
        .navigationTitle(p.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { sheet = .edit }
            }
        }
        .sheet(item: $sheet) { which in
            sheetView(which, p)
        }
        .confirmationDialog("Archive " + p.name + "?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                store.setPropertyArchived(p.id, true)
                dismiss()
            }
        } message: {
            Text("It will be hidden from lists. Its records stay, and you can restore it from Settings → Archived.")
        }
    }

    @ViewBuilder
    private func sheetView(_ which: PropertySheet, _ p: RentalProperty) -> some View {
        switch which {
        case .edit:
            PropertyFormView(property: p).environmentObject(store)
        case .addUnit:
            UnitFormView(propertyID: p.id, unit: nil).environmentObject(store)
        case .editUnit(let unitID):
            UnitFormView(propertyID: p.id, unit: p.units.first { $0.id == unitID }).environmentObject(store)
        case .addTenant(let unitID):
            TenantFormView(tenant: nil, presetPropertyID: p.id, presetUnitID: unitID).environmentObject(store)
        case .addExpense:
            ExpenseFormView(expense: nil, presetPropertyID: p.id).environmentObject(store)
        }
    }

    private func headerSection(_ p: RentalProperty) -> some View {
        Section {
            LabeledContent("Property ID", value: p.code)
            LabeledContent("Type", value: p.type.label)
            if !p.address.isEmpty || !p.city.isEmpty {
                LabeledContent("Address", value: [p.address, p.city].filter { !$0.isEmpty }.joined(separator: ", "))
            }
            if let url = URL(string: p.mapLink.trimmingCharacters(in: .whitespaces)), !p.mapLink.isEmpty {
                Button {
                    openURL(url)
                } label: {
                    Label("Open location", systemImage: "map")
                }
            }
            if !p.notes.isEmpty {
                Text(p.notes)
                    .font(.callout)
            }
        }
    }

    private func moneySection(_ m: PropertyMoney) -> some View {
        Section("Money") {
            TileGrid {
                StatTile(title: "Expected this month", value: Fmt.inr(m.expectedThisMonth))
                StatTile(title: "Collected this month", value: Fmt.inr(m.collectedThisMonth), tint: .green)
                StatTile(title: "Outstanding", value: Fmt.inr(m.outstanding), tint: m.outstanding > 0 ? .orange : .primary)
                StatTile(title: "Overdue", value: Fmt.inr(m.overdue), tint: m.overdue > 0 ? .red : .primary)
                StatTile(title: "Expenses this year", value: Fmt.inr(m.expensesThisYear))
                StatTile(title: "Occupied", value: "\(m.unitsOccupied) of \(m.unitsTotal)")
            }
        }
    }

    private func unitsSection(_ p: RentalProperty, _ units: [UnitInfo]) -> some View {
        Section {
            ForEach(units) { info in
                if let t = info.tenant {
                    NavigationLink(value: Route.tenant(t.id)) {
                        UnitRow(info: info)
                    }
                    .swipeActions(edge: .trailing) {
                        unitActions(p, info)
                    }
                } else {
                    Button {
                        sheet = .addTenant(info.unit?.id)
                    } label: {
                        UnitRow(info: info)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        unitActions(p, info)
                    }
                }
            }
            Button {
                sheet = .addUnit
            } label: {
                Label("Add unit", systemImage: "plus")
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Tap a vacant unit to add a tenant. Swipe a unit to edit it or mark it under maintenance.")
        }
    }

    @ViewBuilder
    private func unitActions(_ p: RentalProperty, _ info: UnitInfo) -> some View {
        if let unit = info.unit {
            Button {
                sheet = .editUnit(unit.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            Button {
                store.updateProperty(p.id, log: unit.underMaintenance ? "Unit available" : "Unit under maintenance", details: unit.name) { prop in
                    if let i = prop.units.firstIndex(where: { $0.id == unit.id }) {
                        prop.units[i].underMaintenance.toggle()
                    }
                }
            } label: {
                Label(unit.underMaintenance ? "Available" : "Maintenance", systemImage: "wrench")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func historySection(_ p: RentalProperty) -> some View {
        let history = Portfolio.history(of: p, tenants: store.data.tenants)
        if !history.isEmpty {
            Section("Tenant history") {
                ForEach(history) { item in
                    NavigationLink(value: Route.tenant(item.tenant.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.tenant.name)
                            Text(historyText(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func historyText(_ item: HistoryItem) -> String {
        let from = item.from.map { Fmt.date($0) } ?? "?"
        let to = item.to.map { Fmt.date($0) } ?? "now"
        let unit = item.unitName.isEmpty ? "" : item.unitName + " · "
        return unit + from + " to " + to
    }
}

struct UnitRow: View {
    let info: UnitInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                if let t = info.tenant {
                    Text(t.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if info.occupancy == .vacant {
                    Text("Tap to add a tenant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TagLabel(text: info.occupancy.label, color: color)
        }
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch info.occupancy {
        case .occupied: return .green
        case .vacant: return .blue
        case .maintenance: return .orange
        }
    }
}

struct PropertyFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let existing: RentalProperty?

    @State private var name: String
    @State private var code: String
    @State private var type: PropertyType
    @State private var address: String
    @State private var city: String
    @State private var mapLink: String
    @State private var notes: String
    @State private var units: [RentalUnit]
    @State private var newUnit = ""
    @State private var askRemove = false

    init(property: RentalProperty?) {
        existing = property
        let p = property ?? RentalProperty()
        _name = State(initialValue: p.name)
        _code = State(initialValue: p.code)
        _type = State(initialValue: p.type)
        _address = State(initialValue: p.address)
        _city = State(initialValue: p.city)
        _mapLink = State(initialValue: p.mapLink)
        _notes = State(initialValue: p.notes)
        _units = State(initialValue: p.units)
    }

    private var title: String { existing == nil ? "New property" : "Edit property" }

    private var duplicateCode: Bool {
        let c = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !c.isEmpty else { return false }
        return store.data.properties.contains { $0.id != existing?.id && $0.code.lowercased() == c }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Property name", text: $name)
                    TextField("Property ID", text: $code)
                        .textInputAutocapitalization(.characters)
                    Picker("Type", selection: $type) {
                        ForEach(PropertyType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                } footer: {
                    if duplicateCode {
                        Text("Another property already uses this ID.")
                            .foregroundStyle(.red)
                    }
                }
                Section("Location") {
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Area / city", text: $city)
                    TextField("Map link (optional)", text: $mapLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                unitsSection
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if unitsInUseBeingRemoved.isEmpty {
                            save()
                        } else {
                            askRemove = true
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || duplicateCode)
                }
            }
            .onAppear {
                if code.isEmpty { code = store.nextPropertyCode() }
            }
            .confirmationDialog("Remove units that have tenants?", isPresented: $askRemove, titleVisibility: .visible) {
                Button("Remove units", role: .destructive) { save() }
            } message: {
                Text(unitsInUseBeingRemoved.joined(separator: ", ") + " will no longer be linked to a unit. Their records stay.")
            }
        }
    }

    private var unitsSection: some View {
        Section {
            ForEach($units) { $unit in
                TextField("Unit name", text: $unit.name)
            }
            .onDelete { offsets in
                units.remove(atOffsets: offsets)
            }
            HStack {
                TextField("Add a unit, e.g. Flat 101", text: $newUnit)
                Button {
                    addUnit()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newUnit.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Leave empty if the whole property is let to one tenant. Swipe a unit to remove it.")
        }
    }

    /// Units being removed (deleted or name cleared) that a tenant is linked to, as "Unit (Tenant)".
    private var unitsInUseBeingRemoved: [String] {
        guard let old = existing else { return [] }
        let kept = Set(units.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.id })
        var result: [String] = []
        for unit in old.units where !kept.contains(unit.id) {
            for t in store.data.tenants where t.unitID == unit.id && !t.isArchived {
                result.append(unit.name + " (" + t.name + ")")
            }
        }
        return result
    }

    private func addUnit() {
        let n = newUnit.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        units.append(RentalUnit(name: n))
        newUnit = ""
    }

    private func save() {
        if !newUnit.trimmingCharacters(in: .whitespaces).isEmpty { addUnit() }
        var p = existing ?? RentalProperty()
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.code = code.trimmingCharacters(in: .whitespaces)
        p.type = type
        p.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        p.city = city.trimmingCharacters(in: .whitespaces)
        p.mapLink = mapLink.trimmingCharacters(in: .whitespaces)
        p.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        p.units = units.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let removed = Set((existing?.units ?? []).map { $0.id }).subtracting(p.units.map { $0.id })
        store.saveProperty(p, isNew: existing == nil)
        if !removed.isEmpty {
            store.change("Units removed", details: p.name, property: p.id) { d in
                for i in d.tenants.indices {
                    if let unit = d.tenants[i].unitID, removed.contains(unit) {
                        d.tenants[i].unitID = nil
                    }
                }
            }
        }
        dismiss()
    }
}

struct UnitFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let propertyID: UUID
    private let existing: RentalUnit?

    @State private var name: String
    @State private var underMaintenance: Bool
    @State private var notes: String

    init(propertyID: UUID, unit: RentalUnit?) {
        self.propertyID = propertyID
        existing = unit
        _name = State(initialValue: unit?.name ?? "")
        _underMaintenance = State(initialValue: unit?.underMaintenance ?? false)
        _notes = State(initialValue: unit?.notes ?? "")
    }

    private var screenTitle: String { existing == nil ? "New unit" : "Edit unit" }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Unit name, e.g. Flat 101", text: $name)
                Toggle("Under maintenance", isOn: $underMaintenance)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
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
        }
    }

    private func save() {
        var unit = existing ?? RentalUnit()
        unit.name = name.trimmingCharacters(in: .whitespaces)
        unit.underMaintenance = underMaintenance
        unit.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = existing == nil
        store.updateProperty(propertyID, log: isNew ? "Unit added" : "Unit updated", details: unit.name) { p in
            if let i = p.units.firstIndex(where: { $0.id == unit.id }) {
                p.units[i] = unit
            } else {
                p.units.append(unit)
            }
        }
        dismiss()
    }
}
