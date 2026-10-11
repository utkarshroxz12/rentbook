//  SheetViews.swift
//  Rent records worksheets: a table you fill in yourself for each tenant (rent start,
//  rent, cash, account, TDS, GST, current rent and next increase), kept apart from the
//  rent ledger, and exported to Excel, CSV or PDF.

import SwiftUI

struct RentSheetsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var deleting: RentSheet? = nil

    var body: some View {
        let sheets = store.data.rentSheets.sorted { $0.createdAt > $1.createdAt }
        List {
            Section {
                if sheets.isEmpty {
                    Text(L("No worksheets yet. Start one to keep each tenant's rent, cash and account split, TDS, GST and increase dates in one table.",
                           "Abhi koi worksheet nahi. Har tenant ka rent, cash aur account, TDS, GST aur badhotri ki tareekh ek table mein rakhne ke liye shuru karein."))
                        .foregroundStyle(.secondary)
                }
                ForEach(sheets) { sheet in
                    NavigationLink(value: Route.rentSheet(sheet.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sheet.name)
                            Text(L("\(sheet.rows.count) tenants · current rent ", "\(sheet.rows.count) tenant · abhi ka rent ")
                                 + Fmt.inr(sheet.rows.reduce(0) { $0 + $1.currentRent }))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deleting = sheet
                        } label: {
                            Label(L("Delete", "Delete"), systemImage: "trash")
                        }
                        .tint(.red)
                        Button {
                            store.duplicateRentSheet(sheet.id)
                        } label: {
                            Label(L("Copy", "Copy"), systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                Text(L("Worksheets are your own records. They don't change rent, payments or reports.",
                       "Worksheet aapke apne record hain. Inse rent, payment ya reports nahi badalte."))
            }
            Section {
                Button {
                    adding = true
                } label: {
                    Label(L("New worksheet", "Nayi worksheet"), systemImage: "plus")
                }
            }
        }
        .navigationTitle(L("Rent records", "Rent records"))
        .sheet(isPresented: $adding) {
            NewRentSheetForm().environmentObject(store)
        }
        .confirmationDialog(L("Delete this worksheet?", "Yeh worksheet delete karein?"), isPresented: deleteBinding, titleVisibility: .visible) {
            Button(L("Delete worksheet", "Worksheet delete karein"), role: .destructive) {
                if let s = deleting { store.deleteRentSheet(s.id) }
                deleting = nil
            }
        } message: {
            Text(L("Its rows are deleted from this iPhone. Export it first if you want to keep a copy.",
                   "Iski rows is iPhone se delete ho jayengi. Copy chahiye to pehle export karein."))
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

struct NewRentSheetForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var fill = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name, e.g. Rent records 2026-27", "Naam, jaise Rent records 2026-27"), text: $name)
                    if !store.liveTenants.isEmpty {
                        Toggle(L("Start with my current tenants", "Mere abhi ke tenants se shuru karein"), isOn: $fill)
                    }
                } footer: {
                    Text(L("Tenants are copied with their start date, rent and next increase. You fill in cash, account, TDS and GST.",
                           "Tenants unki shuru ki tareekh, rent aur agli badhotri ke saath copy honge. Cash, account, TDS aur GST aap bharein."))
                }
            }
            .navigationTitle(L("New worksheet", "Nayi worksheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Create", "Banayein")) { create() }
                }
            }
        }
    }

    private func create() {
        var sheet = RentSheet()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sheet.name = trimmed.isEmpty ? L("Rent records", "Rent records") + " " + Tax.fyLabel(DateMath.financialYearStart(Date())) : trimmed
        if fill {
            sheet.rows = RentSheets.rows(from: store.data, excluding: [])
        }
        store.saveRentSheet(sheet, isNew: true)
        dismiss()
    }
}

struct RentSheetView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let sheetID: UUID

    @State private var editingRow: RentSheetRow? = nil
    @State private var addingRow = false
    @State private var deletingRow: RentSheetRow? = nil
    @State private var renaming = false
    @State private var newName = ""
    @State private var askDelete = false
    @State private var share: ShareItem? = nil
    @State private var filledCount: Int? = nil

    var body: some View {
        if let sheet = store.rentSheet(sheetID) {
            content(sheet)
        } else {
            Text(L("This worksheet was deleted.", "Yeh worksheet delete ho gayi."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ sheet: RentSheet) -> some View {
        List {
            Section {
                TileGrid {
                    StatTile(title: L("Rent (current)", "Rent (abhi ka)"), value: Fmt.inr(sum(sheet) { $0.currentRent }))
                    StatTile(title: L("Cash + account", "Cash + account"), value: Fmt.inr(sum(sheet) { $0.received }))
                    StatTile(title: L("TDS", "TDS"), value: Fmt.inr(sum(sheet) { $0.tds }))
                    StatTile(title: L("GST", "GST"), value: Fmt.inr(sum(sheet) { $0.gst }))
                }
            }
            Section {
                if sheet.rows.isEmpty {
                    Text(L("No rows yet. Add a tenant's row with the + button.", "Abhi koi row nahi. + se tenant ki row jodein."))
                        .foregroundStyle(.secondary)
                }
                ForEach(sheet.rows) { row in
                    Button {
                        editingRow = row
                    } label: {
                        SheetRowCard(row: row)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deletingRow = row
                        } label: {
                            Label(L("Delete", "Delete"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
                .onMove { from, to in
                    store.moveSheetRows(sheetID: sheetID, from: from, to: to)
                }
            } header: {
                Text(L("Tenants", "Tenants"))
            } footer: {
                if let count = filledCount {
                    Text(count == 0 ? L("Every current tenant is already in this worksheet.", "Sab abhi ke tenants pehle se is worksheet mein hain.")
                         : L("\(count) tenants added.", "\(count) tenant jode gaye."))
                }
            }
        }
        .navigationTitle(sheet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exportExcel(sheet)
                    } label: {
                        Label(L("Excel file", "Excel file"), systemImage: "tablecells")
                    }
                    Button {
                        exportPDF(sheet)
                    } label: {
                        Label(L("PDF", "PDF"), systemImage: "doc.richtext")
                    }
                    Button {
                        exportCSV(sheet)
                    } label: {
                        Label(L("CSV", "CSV"), systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    Button {
                        addingRow = true
                    } label: {
                        Label(L("Add a row", "Row jodein"), systemImage: "plus")
                    }
                    if !store.liveTenants.isEmpty {
                        Button {
                            fillFromTenants(sheet)
                        } label: {
                            Label(L("Add my tenants not in the sheet", "Jo tenants nahi hain unhe jodein"), systemImage: "person.2.badge.plus")
                        }
                    }
                    Button {
                        newName = sheet.name
                        renaming = true
                    } label: {
                        Label(L("Rename", "Naam badlein"), systemImage: "pencil")
                    }
                    Button {
                        store.duplicateRentSheet(sheet.id)
                        dismiss()
                    } label: {
                        Label(L("Make a copy", "Copy banayein"), systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        askDelete = true
                    } label: {
                        Label(L("Delete worksheet", "Worksheet delete karein"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                if sheet.rows.count > 1 {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $addingRow) {
            RentSheetRowForm(sheetID: sheetID, row: nil).environmentObject(store)
        }
        .sheet(item: $editingRow) { row in
            RentSheetRowForm(sheetID: sheetID, row: row).environmentObject(store)
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .alert(L("Rename worksheet", "Worksheet ka naam badlein"), isPresented: $renaming) {
            TextField(L("Name", "Naam"), text: $newName)
            Button(L("Save", "Save karein")) {
                var s = sheet
                s.name = newName
                store.saveRentSheet(s, isNew: false)
            }
            Button(L("Cancel", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("Delete this row?", "Yeh row delete karein?"), isPresented: deleteRowBinding, titleVisibility: .visible) {
            Button(L("Delete row", "Row delete karein"), role: .destructive) {
                if let row = deletingRow { store.deleteSheetRow(row.id, sheetID: sheetID) }
                deletingRow = nil
            }
        }
        .confirmationDialog(L("Delete this worksheet?", "Yeh worksheet delete karein?"), isPresented: $askDelete, titleVisibility: .visible) {
            Button(L("Delete worksheet", "Worksheet delete karein"), role: .destructive) {
                store.deleteRentSheet(sheetID)
                dismiss()
            }
        } message: {
            Text(L("Export it first if you want to keep a copy.", "Copy chahiye to pehle export karein."))
        }
    }

    private var deleteRowBinding: Binding<Bool> {
        Binding(get: { deletingRow != nil }, set: { if !$0 { deletingRow = nil } })
    }

    private func sum(_ sheet: RentSheet, _ value: (RentSheetRow) -> Int) -> Int {
        sheet.rows.reduce(0) { $0 + value($1) }
    }

    private func fillFromTenants(_ sheet: RentSheet) {
        let names = Set(sheet.rows.map { $0.tenantName.lowercased() })
        let rows = RentSheets.rows(from: store.data, excluding: names)
        store.addSheetRows(rows, sheetID: sheetID)
        filledCount = rows.count
    }

    private func fileName(_ sheet: RentSheet) -> String {
        sheet.name + " " + DateMath.dayKey(Date())
    }

    private func exportExcel(_ sheet: RentSheet) {
        if let url = store.excelFile(sheets: [Excel.sheet(RentSheets.table(sheet), name: sheet.name)], named: fileName(sheet)) {
            share = ShareItem(url: url)
        }
    }

    private func exportPDF(_ sheet: RentSheet) {
        if let url = PDFMaker.report(RentSheets.table(sheet), landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportCSV(_ sheet: RentSheet) {
        if let url = store.writeTemporary("\u{FEFF}" + RentSheets.table(sheet).csv, named: PDFMaker.safeName(fileName(sheet)) + ".csv") {
            share = ShareItem(url: url)
        }
    }
}

struct SheetRowCard: View {
    let row: RentSheetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.tenantName.isEmpty ? L("(no name)", "(naam nahi)") : row.tenantName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.inr(row.currentRent > 0 ? row.currentRent : row.rent))
                    .font(.subheadline.weight(.semibold))
            }
            if !row.place.isEmpty {
                Text(row.place)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts: [String] = []
        if let start = row.startDate { parts.append(L("from ", "shuru ") + Fmt.date(start)) }
        if row.rent > 0 && row.rent != row.currentRent { parts.append(L("started at ", "shuru ka rent ") + Fmt.inr(row.rent)) }
        if row.cash > 0 { parts.append(L("cash ", "cash ") + Fmt.inr(row.cash)) }
        if row.bank > 0 { parts.append(L("account ", "account ") + Fmt.inr(row.bank)) }
        if row.tds > 0 { parts.append("TDS " + Fmt.inr(row.tds)) }
        if row.gst > 0 { parts.append("GST " + Fmt.inr(row.gst)) }
        if let next = row.nextIncrease { parts.append(L("next increase ", "agli badhotri ") + Fmt.date(next)) }
        return parts.joined(separator: " · ")
    }
}

struct RentSheetRowForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let sheetID: UUID
    let existing: RentSheetRow?

    @State private var tenantName: String
    @State private var place: String
    @State private var startDate: Date?
    @State private var rentText: String
    @State private var cashText: String
    @State private var bankText: String
    @State private var tdsText: String
    @State private var gstText: String
    @State private var currentText: String
    @State private var nextIncrease: Date?
    @State private var notes: String
    @State private var copyFrom: UUID? = nil

    init(sheetID: UUID, row: RentSheetRow?) {
        self.sheetID = sheetID
        existing = row
        let r = row ?? RentSheetRow()
        _tenantName = State(initialValue: r.tenantName)
        _place = State(initialValue: r.place)
        _startDate = State(initialValue: r.startDate)
        _rentText = State(initialValue: amountString(r.rent))
        _cashText = State(initialValue: amountString(r.cash))
        _bankText = State(initialValue: amountString(r.bank))
        _tdsText = State(initialValue: amountString(r.tds))
        _gstText = State(initialValue: amountString(r.gst))
        _currentText = State(initialValue: amountString(r.currentRent))
        _nextIncrease = State(initialValue: r.nextIncrease)
        _notes = State(initialValue: r.notes)
    }

    private func value(_ text: String) -> Int { parseAmount(text) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil && !store.liveTenants.isEmpty {
                    Section {
                        Picker(L("Fill from a tenant", "Tenant se bharein"), selection: $copyFrom) {
                            Text(L("Type it in", "Khud likhein")).tag(Optional<UUID>.none)
                            ForEach(store.liveTenants) { t in
                                Text(t.name).tag(Optional(t.id))
                            }
                        }
                    }
                }
                Section {
                    TextField(L("Tenant", "Tenant"), text: $tenantName)
                    TextField(L("Property", "Property"), text: $place)
                    OptionalDatePicker(title: L("Date rent started", "Rent shuru hone ki tareekh"), date: $startDate)
                    MoneyField(title: L("Rent amount", "Rent amount"), text: $rentText)
                }
                Section {
                    MoneyField(title: L("Rent in cash", "Cash mein rent"), text: $cashText)
                    MoneyField(title: L("Rent in account", "Account mein rent"), text: $bankText)
                    MoneyField(title: L("TDS", "TDS"), text: $tdsText)
                    MoneyField(title: L("GST", "GST"), text: $gstText)
                } header: {
                    Text(L("How it is paid", "Kaise milta hai"))
                } footer: {
                    let received = value(cashText) + value(bankText)
                    if received > 0 {
                        Text(L("Cash and account together: ", "Cash aur account milakar: ") + Fmt.inr(received))
                    }
                }
                Section {
                    MoneyField(title: L("Current rent after increase", "Badhotri ke baad abhi ka rent"), text: $currentText)
                    OptionalDatePicker(title: L("Next increase date", "Agli badhotri ki tareekh"), date: $nextIncrease)
                    TextField(L("Notes", "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(existing == nil ? L("New row", "Nayi row") : L("Edit row", "Row badlein"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(tenantName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .keyboardDoneButton()
            .onChange(of: copyFrom) { id in
                fill(id)
            }
        }
    }

    private func fill(_ id: UUID?) {
        guard let id = id, let t = store.tenant(id) else { return }
        tenantName = t.name
        place = store.place(of: t)
        startDate = t.startDate
        let first = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
        rentText = amountString(first)
        currentText = amountString(Ledger.currentRent(of: t))
        nextIncrease = t.escalation?.nextDate
    }

    private func save() {
        var r = existing ?? RentSheetRow()
        r.tenantName = tenantName.trimmingCharacters(in: .whitespacesAndNewlines)
        r.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        r.startDate = startDate.map { DateMath.day($0) }
        r.rent = value(rentText)
        r.cash = value(cashText)
        r.bank = value(bankText)
        r.tds = value(tdsText)
        r.gst = value(gstText)
        r.currentRent = value(currentText)
        r.nextIncrease = nextIncrease.map { DateMath.day($0) }
        r.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveSheetRow(r, sheetID: sheetID)
        dismiss()
    }
}
