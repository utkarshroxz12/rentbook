//  SheetViews.swift
//  Rent records worksheets: a table you fill in yourself for each tenant (rent start, rent,
//  cash and account, TDS and GST as percentages of the account rent, the rent after
//  increment, missed and next increment dates), kept apart from the rent ledger, with a
//  dashboard of totals you can arrange and extend with your own formulas, and exported to
//  Excel, CSV or PDF.

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
                    Text(L("No worksheets yet. Start one to keep each tenant's rent, cash and account split, TDS, GST and increment dates in one table.",
                           "Abhi koi worksheet nahi. Har tenant ka rent, cash aur account, TDS, GST aur badhotri ki tareekh ek table mein rakhne ke liye shuru karein."))
                        .foregroundStyle(.secondary)
                }
                ForEach(sheets) { sheet in
                    NavigationLink(value: Route.rentSheet(sheet.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sheet.name)
                            Text(subtitle(sheet))
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

    private func subtitle(_ sheet: RentSheet) -> String {
        let total = Fmt.inr(RentSheets.sums(sheet).totalCurrent)
        return concat(L("\(sheet.rows.count) tenants · total current rent ", "\(sheet.rows.count) tenant · kul abhi ka rent "), total)
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
                    Text(L("Tenants are copied with their start date, first rent and next increment. You fill in cash, account, TDS and GST.",
                           "Tenants unki shuru ki tareekh, pehle rent aur agli badhotri ke saath copy honge. Cash, account, TDS aur GST aap bharein."))
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
    @State private var editingDashboard = false

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
            dashboardSection(sheet)
            rowsSection(sheet)
        }
        .navigationTitle(sheet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                exportMenu(sheet)
                moreMenu(sheet)
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
        .sheet(isPresented: $editingDashboard) {
            SheetDashboardEditor(sheetID: sheetID, tiles: store.sheetTiles).environmentObject(store)
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

    private func dashboardSection(_ sheet: RentSheet) -> some View {
        let tiles = store.sheetTiles
        let values = SheetFormula.values(RentSheets.sums(sheet))
        return Section {
            if !tiles.isEmpty {
                TileGrid {
                    ForEach(tiles) { tile in
                        StatTile(title: tile.title, value: tileValue(tile, values, tiles))
                    }
                }
            }
            Button {
                editingDashboard = true
            } label: {
                Label(L("Edit dashboard", "Dashboard badlein"), systemImage: "slider.horizontal.3")
            }
        } footer: {
            Text(L("Worked out from the rent after increment. Where a row has no increment, how it is paid is used.",
                   "Badhotri ke baad ke rent se nikala gaya. Jis row mein badhotri nahi, wahan kaise milta hai wala rent liya gaya."))
        }
    }

    private func tileValue(_ tile: SheetTile, _ values: [String: Double], _ tiles: [SheetTile]) -> String {
        let result = SheetFormula.value(of: tile, values: values, tiles: tiles)
        return SheetFormula.display(result, isMoney: tile.isMoney)
    }

    private func rowsSection(_ sheet: RentSheet) -> some View {
        Section {
            if sheet.rows.isEmpty {
                Text(L("No rows yet. Add a tenant's row from the ⋯ menu.", "Abhi koi row nahi. ⋯ menu se tenant ki row jodein."))
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
            Button {
                addingRow = true
            } label: {
                Label(L("Add a row", "Row jodein"), systemImage: "plus")
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

    private func exportMenu(_ sheet: RentSheet) -> some View {
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
    }

    private func moreMenu(_ sheet: RentSheet) -> some View {
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
                editingDashboard = true
            } label: {
                Label(L("Edit dashboard", "Dashboard badlein"), systemImage: "slider.horizontal.3")
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
    }

    private var deleteRowBinding: Binding<Bool> {
        Binding(get: { deletingRow != nil }, set: { if !$0 { deletingRow = nil } })
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

    /// The full worksheet, with the dashboard on a second sheet.
    private func exportExcel(_ sheet: RentSheet) {
        let tiles = store.sheetTiles
        var books: [XLSXSheet] = [Excel.sheet(RentSheets.table(sheet), name: sheet.name)]
        if !tiles.isEmpty {
            books.append(Excel.sheet(SheetFormula.table(sheet, tiles: tiles), name: L("Dashboard", "Dashboard")))
        }
        if let url = store.excelFile(sheets: books, named: fileName(sheet)) {
            share = ShareItem(url: url)
        }
    }

    /// The dashboard and the rent after increment, which fit on a page.
    private func exportPDF(_ sheet: RentSheet) {
        let tiles = store.sheetTiles
        var tables: [ReportTable] = []
        if !tiles.isEmpty {
            tables.append(SheetFormula.table(sheet, tiles: tiles))
        }
        tables.append(RentSheets.shortTable(sheet))
        let subtitle = L("As of ", "Tareekh: ") + Fmt.date(Date())
        if let url = PDFMaker.reports(tables, title: sheet.name, subtitle: subtitle, landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportCSV(_ sheet: RentSheet) {
        let name = PDFMaker.safeName(fileName(sheet)) + ".csv"
        if let url = store.writeTemporary("\u{FEFF}" + RentSheets.table(sheet).csv, named: name) {
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
                Text(Fmt.inr(headline))
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
            if let months = row.missedMonths(), months > 0 {
                TagLabel(text: missedLabel(months), color: .orange)
            }
        }
        .padding(.vertical, 2)
    }

    /// The total current rent, or the rent amount while cash and account are not filled in.
    private var headline: Int {
        let total = row.current.total
        return total > 0 ? total : row.rent
    }

    private func missedLabel(_ months: Int) -> String {
        months == 1 ? L("Increment missed 1 month", "Badhotri 1 mahine se chhooti")
            : L("Increment missed \(months) months", "Badhotri \(months) mahine se chhooti")
    }

    private var details: String {
        let n = row.current
        var parts: [String] = []
        if n.cash > 0 { parts.append(L("cash ", "cash ") + Fmt.inr(n.cash)) }
        if n.account > 0 { parts.append(L("account ", "account ") + Fmt.inr(n.account)) }
        if n.tdsPercent > 0 { parts.append("TDS " + RentSheets.percentText(n.tdsPercent)) }
        if n.gstPercent > 0 { parts.append("GST " + RentSheets.percentText(n.gstPercent)) }
        if n.cash == 0 && n.account == 0 {
            parts.append(L("fill in cash and account", "cash aur account bharein"))
        }
        if row.hasIncrement {
            parts.append(L("after increment", "badhotri ke baad"))
        } else if let start = row.startDate {
            parts.append(L("from ", "shuru ") + Fmt.date(start))
        }
        if let next = row.nextIncrease { parts.append(L("next increment ", "agli badhotri ") + Fmt.date(next)) }
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
    @State private var cashNowText: String
    @State private var bankNowText: String
    @State private var tdsNowText: String
    @State private var gstNowText: String
    @State private var missedIncrease: Date?
    @State private var nextIncrease: Date?
    @State private var notes: String
    @State private var copyFrom: UUID? = nil
    @State private var rentInRentBook: Int? = nil

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
        _tdsText = State(initialValue: RentSheets.percentInput(r.tdsPercent))
        _gstText = State(initialValue: RentSheets.percentInput(r.gstPercent))
        _cashNowText = State(initialValue: r.cashNow.map { String($0) } ?? "")
        _bankNowText = State(initialValue: r.bankNow.map { String($0) } ?? "")
        _tdsNowText = State(initialValue: r.tdsPercentNow.map { RentSheets.percentNumber($0) } ?? "")
        _gstNowText = State(initialValue: r.gstPercentNow.map { RentSheets.percentNumber($0) } ?? "")
        _missedIncrease = State(initialValue: r.missedIncrease)
        _nextIncrease = State(initialValue: r.nextIncrease)
        _notes = State(initialValue: r.notes)
    }

    // MARK: Reading the boxes

    private func amount(_ text: String) -> Int { parseAmount(text) ?? 0 }

    private func percent(_ text: String) -> Double {
        min(max(parseDecimal(text) ?? 0, 0), 100)
    }

    /// Empty means "the same as how it is paid".
    private func optionalAmount(_ text: String) -> Int? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : parseAmount(text)
    }

    private func optionalPercent(_ text: String) -> Double? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let value = parseDecimal(text) else { return nil }
        return min(max(value, 0), 100)
    }

    private var paid: SheetMoney {
        SheetMoney(cash: amount(cashText), account: amount(bankText), tdsPercent: percent(tdsText), gstPercent: percent(gstText))
    }

    private var now: SheetMoney {
        let p = paid
        let cash: Int = optionalAmount(cashNowText) ?? p.cash
        let account: Int = optionalAmount(bankNowText) ?? p.account
        let tds: Double = optionalPercent(tdsNowText) ?? p.tdsPercent
        let gst: Double = optionalPercent(gstNowText) ?? p.gstPercent
        return SheetMoney(cash: cash, account: account, tdsPercent: tds, gstPercent: gst)
    }

    // MARK: Screen

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
                paidSection
                incrementSection
                datesSection
                Section {
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

    private var paidSection: some View {
        let p = paid
        return Section {
            MoneyField(title: L("Rent in cash", "Cash mein rent"), text: $cashText)
            MoneyField(title: L("Rent in account", "Account mein rent"), text: $bankText)
            PercentField(title: L("TDS", "TDS"), text: $tdsText)
            PercentField(title: L("GST", "GST"), text: $gstText)
            LabeledContent(L("Final rent in account", "Account mein final rent"), value: Fmt.inr(p.finalAccount))
            LabeledContent(L("Cash + final rent", "Cash + final rent"), value: Fmt.inr(p.total))
                .font(.headline)
        } header: {
            Text(L("How it is paid", "Kaise milta hai"))
        } footer: {
            Text(paidFooter(p))
        }
    }

    private func paidFooter(_ p: SheetMoney) -> String {
        concat(L("TDS and GST are on the rent in account only: TDS ", "TDS aur GST sirf account wale rent par: TDS "), Fmt.inr(p.tds),
               L(" is taken off and GST ", " kata aur GST "), Fmt.inr(p.gst), L(" added. Cash rent has neither.", " juda. Cash rent par dono nahi."))
    }

    private var incrementSection: some View {
        let p = paid
        let n = now
        return Section {
            MoneyField(title: L("Cash rent after increment", "Badhotri ke baad cash rent"), text: $cashNowText, placeholder: String(p.cash))
            MoneyField(title: L("Account rent after increment", "Badhotri ke baad account rent"), text: $bankNowText, placeholder: String(p.account))
            PercentField(title: L("TDS", "TDS"), text: $tdsNowText, placeholder: RentSheets.percentNumber(p.tdsPercent))
            PercentField(title: L("GST", "GST"), text: $gstNowText, placeholder: RentSheets.percentNumber(p.gstPercent))
            LabeledContent(L("Current rent in account", "Account mein abhi ka rent"), value: Fmt.inr(n.finalAccount))
            LabeledContent(L("Total current rent", "Kul abhi ka rent"), value: Fmt.inr(n.total))
                .font(.headline)
        } header: {
            Text(L("Rent after increment", "Badhotri ke baad rent"))
        } footer: {
            Text(incrementFooter(n))
        }
    }

    private func incrementFooter(_ n: SheetMoney) -> String {
        var text = concat(L("Leave a box empty if it has not changed; the grey amount from How it is paid is used. TDS ",
                            "Jo nahi badla use khaali chhodein; Kaise milta hai wala grey amount liya jayega. TDS "),
                          Fmt.inr(n.tds), L(" and GST ", " aur GST "), Fmt.inr(n.gst),
                          L(" are on the account rent after increment only.", " sirf badhotri ke baad wale account rent par."))
        if let current = rentInRentBook {
            text += concat(L(" In RentBook, this tenant's rent is now ", " RentBook mein is tenant ka rent abhi "), Fmt.inr(current), ".")
        }
        return text
    }

    private var datesSection: some View {
        Section {
            OptionalDatePicker(title: L("Missed increment date", "Chhooti badhotri ki tareekh"), date: $missedIncrease)
            if let missed = missedIncrease {
                LabeledContent(L("Months since then", "Tab se kitne mahine"), value: missedText(missed))
            }
            OptionalDatePicker(title: L("Next increment date", "Agli badhotri ki tareekh"), date: $nextIncrease)
        } header: {
            Text(L("Increment dates", "Badhotri ki tareekh"))
        } footer: {
            Text(L("Months are counted from the missed increment's month to this month, both included: April to October is 7.",
                   "Mahine chhooti badhotri ke mahine se is mahine tak, dono milakar gine jaate hain: April se October 7 hain."))
        }
    }

    private func missedText(_ date: Date) -> String {
        let today = Date()
        let months = RentSheets.monthsCounted(from: date, to: today)
        if months == 0 { return L("Not yet", "Abhi nahi") }
        let count = months == 1 ? L("1 month", "1 mahina") : L("\(months) months", "\(months) mahine")
        return concat(count, " (", Fmt.month(date), " – ", Fmt.month(today), ")")
    }

    private func fill(_ id: UUID?) {
        guard let id = id, let t = store.tenant(id) else { return }
        tenantName = t.name
        place = store.place(of: t)
        startDate = t.startDate
        let first = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
        let current = Ledger.currentRent(of: t)
        let rent = first > 0 ? first : current
        rentText = amountString(rent)
        rentInRentBook = current > 0 && current != rent ? current : nil
        nextIncrease = t.escalation?.nextDate
    }

    private func save() {
        var r = existing ?? RentSheetRow()
        r.tenantName = tenantName.trimmingCharacters(in: .whitespacesAndNewlines)
        r.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        r.startDate = startDate.map { DateMath.day($0) }
        r.rent = amount(rentText)
        r.cash = amount(cashText)
        r.bank = amount(bankText)
        r.tdsPercent = percent(tdsText)
        r.gstPercent = percent(gstText)
        r.cashNow = optionalAmount(cashNowText)
        r.bankNow = optionalAmount(bankNowText)
        r.tdsPercentNow = optionalPercent(tdsNowText)
        r.gstPercentNow = optionalPercent(gstNowText)
        r.missedIncrease = missedIncrease.map { DateMath.day($0) }
        r.nextIncrease = nextIncrease.map { DateMath.day($0) }
        r.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveSheetRow(r, sheetID: sheetID)
        dismiss()
    }
}

// MARK: - Dashboard

/// Arrange, add, change and delete the worksheet dashboard's items. Nothing changes until Save.
struct SheetDashboardEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let sheetID: UUID

    @State private var tiles: [SheetTile]
    @State private var editing: SheetTile? = nil
    @State private var adding = false
    @State private var askReset = false

    init(sheetID: UUID, tiles: [SheetTile]) {
        self.sheetID = sheetID
        _tiles = State(initialValue: tiles)
    }

    private var values: [String: Double] {
        guard let sheet = store.rentSheet(sheetID) else { return SheetFormula.values(SheetSums()) }
        return SheetFormula.values(RentSheets.sums(sheet))
    }

    var body: some View {
        let totals = values
        NavigationStack {
            List {
                Section {
                    if tiles.isEmpty {
                        Text(L("No items. Add one below.", "Koi item nahi. Neeche se jodein."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tiles) { tile in
                        Button {
                            editing = tile
                        } label: {
                            SheetTileRow(tile: tile, value: shown(tile, totals))
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { from, to in
                        tiles.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        tiles.remove(atOffsets: offsets)
                    }
                    Button {
                        adding = true
                    } label: {
                        Label(L("Add an item", "Item jodein"), systemImage: "plus")
                    }
                } header: {
                    Text(L("Items, in the order shown", "Items, isi kram mein"))
                } footer: {
                    Text(L("Tap an item to change its name or formula. Swipe left to delete it. Tap Edit, then drag to change the order. Nothing is kept until you tap Save.",
                           "Naam ya formula badalne ke liye item par tap karein. Delete ke liye left swipe karein. Kram badalne ke liye Edit dabakar khinchein. Save dabane tak kuch nahi badalta."))
                }
                Section {
                    Button(role: .destructive) {
                        askReset = true
                    } label: {
                        Label(L("Go back to the standard seven items", "Wapas standard saat items"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle(L("Dashboard", "Dashboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button(L("Save", "Save karein")) {
                        store.saveSheetTiles(tiles)
                        dismiss()
                    }
                }
            }
            .sheet(item: $editing) { tile in
                SheetTileForm(tile: tile, others: tiles.filter { $0.id != tile.id }, values: totals) { updated in
                    update(updated)
                }
            }
            .sheet(isPresented: $adding) {
                SheetTileForm(tile: nil, others: tiles, values: totals) { added in
                    update(added)
                }
            }
            .confirmationDialog(L("Go back to the standard items?", "Wapas standard items?"), isPresented: $askReset, titleVisibility: .visible) {
                Button(L("Use the standard seven", "Standard saat lein"), role: .destructive) {
                    tiles = SheetFormula.defaultTiles
                }
            } message: {
                Text(L("Your own items are removed when you then tap Save.", "Save dabane par aapke apne items hat jayenge."))
            }
        }
    }

    private func shown(_ tile: SheetTile, _ totals: [String: Double]) -> String {
        let result = SheetFormula.value(of: tile, values: totals, tiles: tiles)
        return SheetFormula.display(result, isMoney: tile.isMoney)
    }

    /// Puts a changed or new item in place. When an item is renamed, formulas that use it by
    /// name are changed to the new name.
    private func update(_ tile: SheetTile) {
        guard let i = tiles.firstIndex(where: { $0.id == tile.id }) else {
            tiles.append(tile)
            return
        }
        let oldTitle = tiles[i].title
        tiles[i] = tile
        let oldKey = oldTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard oldKey != tile.key else { return }
        for j in tiles.indices where j != i {
            tiles[j].formula = SheetFormula.renaming(tiles[j].formula, from: oldTitle, to: tile.title)
        }
    }
}

struct SheetTileRow: View {
    let tile: SheetTile
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title.isEmpty ? L("(no name)", "(naam nahi)") : tile.title)
                Text(tile.formula)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .contentShape(Rectangle())
    }
}

/// One dashboard item: its name, how it is shown, and its formula, with the worksheet's
/// values and the other items to tap in.
struct SheetTileForm: View {
    @Environment(\.dismiss) private var dismiss
    let existing: SheetTile?
    let others: [SheetTile]
    let values: [String: Double]
    let onSave: (SheetTile) -> Void

    @State private var title: String
    @State private var formula: String
    @State private var isMoney: Bool

    private let signs = ["+", "−", "×", "÷", "(", ")", "%"]

    init(tile: SheetTile?, others: [SheetTile], values: [String: Double], onSave: @escaping (SheetTile) -> Void) {
        existing = tile
        self.others = others
        self.values = values
        self.onSave = onSave
        _title = State(initialValue: tile?.title ?? "")
        _formula = State(initialValue: tile?.formula ?? "")
        _isMoney = State(initialValue: tile?.isMoney ?? true)
    }

    private var draft: SheetTile {
        var t = existing ?? SheetTile()
        t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.formula = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        t.isMoney = isMoney
        return t
    }

    private var result: Result<Double, FormulaProblem> {
        let t = draft
        return SheetFormula.value(of: t, values: values, tiles: others + [t])
    }

    /// A mistake in the formula itself. Dividing by a total that is zero today is allowed.
    private var problem: FormulaProblem? {
        guard case .failure(let p) = result, p != .divideByZero else { return nil }
        return p
    }

    private var duplicateName: Bool {
        let key = draft.key
        return !key.isEmpty && others.contains { $0.key == key }
    }

    private var canSave: Bool {
        !draft.key.isEmpty && !duplicateName && problem == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name, e.g. Yearly actual rent", "Naam, jaise Saal ka actual rent"), text: $title)
                    Picker(L("Show as", "Kaise dikhe"), selection: $isMoney) {
                        Text(L("Rupees", "Rupaye")).tag(true)
                        Text(L("Number", "Number")).tag(false)
                    }
                } footer: {
                    if duplicateName {
                        Text(L("Another item already has this name.", "Is naam ka item pehle se hai."))
                            .foregroundStyle(Color.red)
                    }
                }
                formulaSection
                valuesSection
                if !others.isEmpty {
                    itemsSection
                }
            }
            .navigationTitle(existing == nil ? L("New item", "Naya item") : L("Edit item", "Item badlein"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done", "Ho gaya")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var formulaSection: some View {
        Section {
            TextField(L("Formula, e.g. CASH + ACCOUNT - TDS", "Formula, jaise CASH + ACCOUNT - TDS"), text: $formula, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .lineLimit(1...4)
            LabeledContent(L("Result", "Nateeja"), value: SheetFormula.display(result, isMoney: isMoney))
            HStack(spacing: 6) {
                ForEach(signs, id: \.self) { sign in
                    Button(sign) {
                        add(sign)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button(L("Clear the formula", "Formula mitayein"), role: .destructive) {
                formula = ""
            }
            .disabled(formula.isEmpty)
        } header: {
            Text(L("Formula", "Formula"))
        } footer: {
            Text(formulaHelp)
                .foregroundStyle(problem == nil ? Color.secondary : Color.red)
        }
    }

    private var formulaHelp: String {
        if let p = problem { return p.message }
        if case .failure(let p) = result { return p.message }
        return L("Use the values below, numbers, + − × ÷, brackets and %. {Name} uses another item, for example {Actual rent} × 12.",
                 "Neeche ki values, numbers, + − × ÷, bracket aur % use karein. {Naam} se doosra item, jaise {Actual rent} × 12.")
    }

    private var valuesSection: some View {
        Section {
            ForEach(SheetFormula.fields) { field in
                Button {
                    add(field.code)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.code)
                                .font(.system(.subheadline, design: .monospaced))
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fieldValue(field))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L("Values (tap to add)", "Values (jodne ke liye tap karein)"))
        } footer: {
            Text(L("Each value is the total of that column for every tenant in this worksheet.",
                   "Har value is worksheet ke sab tenants ke us column ka total hai."))
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(others) { item in
                Button {
                    add("{" + item.title + "}")
                } label: {
                    HStack {
                        Text(item.title)
                        Spacer()
                        Text(itemValue(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L("Other items (tap to add)", "Doosre items (jodne ke liye tap karein)"))
        }
    }

    private func fieldValue(_ field: SheetField) -> String {
        SheetFormula.display(.success(values[field.code] ?? 0), isMoney: field.isMoney)
    }

    private func itemValue(_ item: SheetTile) -> String {
        let result = SheetFormula.value(of: item, values: values, tiles: others)
        return SheetFormula.display(result, isMoney: item.isMoney)
    }

    /// Adds a value, item or sign at the end of the formula.
    private func add(_ piece: String) {
        let current = formula.trimmingCharacters(in: .whitespaces)
        if current.isEmpty {
            formula = piece
        } else if piece == "%" || piece == ")" {
            formula = current + piece
        } else {
            formula = current + " " + piece
        }
    }
}
