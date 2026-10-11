//  TaxViews.swift
//  The yearly summary for tax preparation: rent received in an Indian financial year,
//  expenses sorted by category, and an indicative house-property working, with
//  exports for your tax adviser. Not tax advice.

import SwiftUI

struct TaxSummaryView: View {
    @EnvironmentObject var store: Store
    @State private var fyStart: Date = DateMath.financialYearStart(Date())
    @State private var basis: TaxBasis = .rentBook
    @State private var sheetID: UUID? = nil
    @State private var share: ShareItem? = nil
    @State private var prepared = false

    private var years: [Date] {
        var earliest = DateMath.financialYearStart(Date())
        for t in store.data.tenants {
            if let first = t.payments.map({ $0.date }).min() {
                earliest = min(earliest, DateMath.financialYearStart(first))
            }
        }
        if let first = store.data.expenses.map({ $0.date }).min() {
            earliest = min(earliest, DateMath.financialYearStart(first))
        }
        if let first = store.partnership.entries.map({ $0.date }).min() {
            earliest = min(earliest, DateMath.financialYearStart(first))
        }
        var list: [Date] = []
        var y = DateMath.financialYearStart(Date())
        while y >= earliest && list.count < 20 {
            list.append(y)
            y = DateMath.addMonths(-12, to: y)
        }
        return list
    }

    private var sheet: RentSheet? {
        sheetID.flatMap { store.rentSheet($0) }
    }

    var body: some View {
        let summary = Tax.summary(store.data, fyStart: fyStart, basis: basis, sheet: sheet)
        let table = Tax.table(summary)
        List {
            Section {
                Picker(L("Financial year", "Financial year"), selection: $fyStart) {
                    ForEach(years, id: \.self) { y in
                        Text(Tax.fyLabel(y)).tag(y)
                    }
                }
                if store.partnerSettings.enabled {
                    Picker(L("Rental income", "Rent ki income"), selection: $basis) {
                        ForEach(TaxBasis.allCases) { b in
                            Text(b.label).tag(b)
                        }
                    }
                }
                if !store.data.rentSheets.isEmpty {
                    Picker(L("TDS and GST from", "TDS aur GST kahan se"), selection: $sheetID) {
                        Text(L("Not included", "Shaamil nahi")).tag(Optional<UUID>.none)
                        ForEach(store.data.rentSheets) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                }
            } footer: {
                Text(Fmt.date(summary.fyStart) + " – " + Fmt.date(summary.fyEnd))
            }
            Section {
                TileGrid {
                    StatTile(title: L("Gross annual value", "Gross annual value"), value: Fmt.inr(summary.grossAnnualValue))
                    StatTile(title: L("Income from house property", "House property se income"), value: Fmt.inr(summary.incomeFromHouseProperty))
                }
            }
            Section(L("Working", "Hisaab")) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { item in
                    let row = item.element
                    LabeledContent(row.first ?? "", value: row.count > 1 ? row[1] : "")
                        .font(row.first?.hasPrefix("   ") == true ? .caption : .subheadline)
                }
            }
            Section {
                Text(table.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    exportPDF(table)
                } label: {
                    Label(L("Share summary as PDF", "Summary PDF share karein"), systemImage: "doc.richtext")
                }
                Button {
                    exportExcel()
                } label: {
                    Label(L("Excel file for your tax adviser", "CA ke liye Excel file"), systemImage: "tablecells")
                }
            } footer: {
                Text(L("The Excel file has the summary, every rent payment received, every expense with your share, the partnership statement and the chosen worksheet, one sheet each.",
                       "Excel file mein summary, har mila rent, har kharcha aapke hisse ke saath, partnership statement aur chuni worksheet hai, har ek alag sheet mein."))
            }
        }
        .navigationTitle(L("Tax summary", "Tax summary"))
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            if !prepared {
                prepared = true
                // From April to July the year just ended is the one being filed.
                let month = rbCalendar.component(.month, from: Date())
                if (4...7).contains(month) {
                    fyStart = DateMath.addMonths(-12, to: DateMath.financialYearStart(Date()))
                }
                if store.partnerSettings.enabled && store.data.tenants.isEmpty {
                    basis = .partnership
                }
            }
        }
    }

    private func exportPDF(_ table: ReportTable) {
        if let url = PDFMaker.report(table, landlord: store.settings.landlordName) {
            share = ShareItem(url: url)
        }
    }

    private func exportExcel() {
        let sheets = Tax.workbook(store.data, fyStart: fyStart, basis: basis, sheet: sheet)
        if let url = store.excelFile(sheets: sheets, named: L("Tax summary ", "Tax summary ") + Tax.fyLabel(fyStart)) {
            share = ShareItem(url: url)
        }
    }
}
