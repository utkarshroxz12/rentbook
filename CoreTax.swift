//  CoreTax.swift
//  Annual summaries for tax preparation: rental income for an Indian financial year,
//  expenses sorted for review, and an indicative house-property working.
//  Not tax advice: a summary to go through with a tax adviser. Foundation only.

import Foundation

enum TaxBasis: String, CaseIterable, Identifiable {
    case rentBook, partnership
    var id: String { rawValue }
    var label: String {
        self == .rentBook ? L("Rent from my RentBook tenants", "RentBook tenants ka rent")
            : L("My share of the partnership rent", "Partnership rent mein mera hissa")
    }
}

struct TaxExpenseLine: Identifiable, Hashable {
    var category: ExpenseCategory
    var total: Int
    var myShare: Int
    var id: String { category.rawValue }
}

struct TaxSummary {
    var fyStart: Date
    var fyEnd: Date
    var basis: TaxBasis
    var rentReceived = 0
    var rentByProperty: [ChartPoint] = []
    var partnershipEnabled = false
    var partnershipTotal = 0
    var partnershipMine = 0
    var myPercent = 100
    var expenses: [TaxExpenseLine] = []
    var municipalTax = 0
    var loanInterest = 0
    var otherExpenses = 0
    var tdsMonthly = 0
    var gstMonthly = 0
    var sheetName = ""

    var grossAnnualValue: Int { basis == .rentBook ? rentReceived : partnershipMine }
    var netAnnualValue: Int { grossAnnualValue - municipalTax }
    var standardDeduction: Int { netAnnualValue > 0 ? Int((Double(netAnnualValue) * 0.3).rounded()) : 0 }
    var incomeFromHouseProperty: Int { netAnnualValue - standardDeduction - loanInterest }
}

enum Tax {
    static func fyEnd(_ start: Date) -> Date {
        DateMath.addDays(-1, to: DateMath.addMonths(12, to: start))
    }

    static func fyLabel(_ start: Date) -> String {
        let year = rbCalendar.component(.year, from: start)
        return "FY \(year)-" + String(String(year + 1).suffix(2))
    }

    /// My part of an expense: everything when the partnership is off.
    static func myShare(_ e: Expense, _ data: AppData) -> Int {
        let settings = data.partnership.settings
        guard settings.enabled else { return e.amount }
        return Partnership.shares(of: e, settings: settings).mine
    }

    static func summary(_ data: AppData, fyStart: Date, basis: TaxBasis, sheet: RentSheet? = nil) -> TaxSummary {
        let start = DateMath.financialYearStart(fyStart)
        let end = fyEnd(start)
        var s = TaxSummary(fyStart: start, fyEnd: end, basis: basis)

        var byProperty: [String: Int] = [:]
        for t in data.tenants {
            let amount = Portfolio.netCollected(t, from: start, to: end)
            guard amount != 0 else { continue }
            s.rentReceived += amount
            byProperty[Reports.propertyOnly(t, data), default: 0] += amount
        }
        s.rentByProperty = byProperty.sorted { $0.key < $1.key }.enumerated().map { i, item in
            ChartPoint(label: item.key, series: "Rent", value: item.value, order: i)
        }

        let settings = data.partnership.settings
        s.partnershipEnabled = settings.enabled
        s.myPercent = settings.enabled ? Int((Partnership.myFraction(settings) * 100).rounded()) : 100
        if settings.enabled {
            for entry in data.partnership.entries where entry.kind == .rent && !entry.isVoided {
                let key = Partnership.monthKey(of: entry)
                guard let month = Partnership.monthDate(key), month >= start, month <= end else { continue }
                s.partnershipTotal += entry.amount
            }
            s.partnershipMine = Int((Double(s.partnershipTotal) * Partnership.myFraction(settings)).rounded())
        }

        var totals: [ExpenseCategory: (Int, Int)] = [:]
        for e in data.expenses where !e.isArchived && e.amount > 0 {
            let day = DateMath.day(e.date)
            guard day >= start && day <= end else { continue }
            let mine = myShare(e, data)
            let current = totals[e.category] ?? (0, 0)
            totals[e.category] = (current.0 + e.amount, current.1 + mine)
            switch e.category {
            case .tax: s.municipalTax += mine
            case .loanInterest: s.loanInterest += mine
            default: s.otherExpenses += mine
            }
        }
        s.expenses = ExpenseCategory.allCases.compactMap { c in
            guard let t = totals[c] else { return nil }
            return TaxExpenseLine(category: c, total: t.0, myShare: t.1)
        }

        if let sheet = sheet {
            s.sheetName = sheet.name
            let sums = RentSheets.sums(sheet)
            s.tdsMonthly = sums.tds
            s.gstMonthly = sums.gst
        }
        return s
    }

    static func table(_ s: TaxSummary) -> ReportTable {
        var rows: [[String]] = []
        rows.append([L("Rent received from RentBook tenants", "RentBook tenants se mila rent"), Fmt.inr(s.rentReceived)])
        for p in s.rentByProperty {
            rows.append(["   " + p.label, Fmt.inr(p.value)])
        }
        if s.partnershipEnabled {
            rows.append([L("Partnership rent, total", "Partnership rent, kul"), Fmt.inr(s.partnershipTotal)])
            rows.append([L("My share of it (\(s.myPercent)%)", "Usmein mera hissa (\(s.myPercent)%)"), Fmt.inr(s.partnershipMine)])
        }
        rows.append([L("Gross annual value", "Gross annual value") + " – " + s.basis.label, Fmt.inr(s.grossAnnualValue)])
        rows.append([L("Less: municipal / property tax paid (my share)", "Ghatayein: municipal / property tax (mera hissa)"), Fmt.inr(-s.municipalTax)])
        rows.append([L("Net annual value", "Net annual value"), Fmt.inr(s.netAnnualValue)])
        rows.append([L("Less: standard deduction, 30%", "Ghatayein: standard deduction, 30%"), Fmt.inr(-s.standardDeduction)])
        rows.append([L("Less: home loan interest (my share)", "Ghatayein: home loan interest (mera hissa)"), Fmt.inr(-s.loanInterest)])
        rows.append([L("Income from house property (indicative)", "House property se income (andaaza)"), Fmt.inr(s.incomeFromHouseProperty)])
        rows.append([L("Other expenses for review (my share)", "Baaki kharche, review ke liye (mera hissa)"), Fmt.inr(s.otherExpenses)])
        for line in s.expenses {
            rows.append(["   " + line.category.label, Fmt.inr(line.myShare)])
        }
        if !s.sheetName.isEmpty {
            rows.append([L("TDS per month (", "TDS har mahine (") + s.sheetName + ")", Fmt.inr(s.tdsMonthly)])
            rows.append([L("GST per month (", "GST har mahine (") + s.sheetName + ")", Fmt.inr(s.gstMonthly)])
        }
        let note = L("An indicative summary to go through with your tax adviser, not tax advice. "
                     + "For let-out house property, repairs and other running costs are covered by the 30% standard deduction; "
                     + "they matter if the rent is treated as business income.",
                     "Yeh sirf andaaza hai, apne CA ke saath check karein. Tax advice nahi hai. "
                     + "Kiraye par diye ghar ke liye repair jaise kharche 30% standard deduction mein aa jaate hain; "
                     + "agar rent business income maana jaye tab yeh kharche alag se gine jaate hain.")
        return ReportTable(title: L("Annual tax summary", "Saalana tax summary") + " · " + fyLabel(s.fyStart),
                           subtitle: Fmt.date(s.fyStart) + " – " + Fmt.date(s.fyEnd),
                           columns: [L("Item", "Item"), L("Amount", "Amount")], rows: rows, note: note)
    }

    /// Everything for the year, sheet by sheet, for a tax adviser.
    static func workbook(_ data: AppData, fyStart: Date, basis: TaxBasis, sheet: RentSheet?) -> [XLSXSheet] {
        let s = summary(data, fyStart: fyStart, basis: basis, sheet: sheet)
        let filter = ReportFilter(from: s.fyStart, to: s.fyEnd)
        var sheets: [XLSXSheet] = [Excel.sheet(table(s), name: L("Summary", "Summary"))]
        sheets.append(Excel.sheet(Reports.build(.paymentsList, data: data, filter: filter, asOf: s.fyEnd), name: L("Rent received", "Mila rent")))
        sheets.append(Excel.sheet(expenseTable(data, from: s.fyStart, to: s.fyEnd), name: L("Expenses", "Kharche")))
        if data.partnership.settings.enabled {
            sheets.append(Excel.sheet(Reports.build(.partnerSettlement, data: data, filter: filter, asOf: s.fyEnd), name: L("Partnership", "Partnership")))
        }
        if let sheet = sheet {
            sheets.append(Excel.sheet(RentSheets.table(sheet), name: sheet.name))
        }
        return sheets
    }

    static func expenseTable(_ data: AppData, from: Date, to: Date) -> ReportTable {
        let settings = data.partnership.settings
        let list = data.expenses.filter { e in
            let d = DateMath.day(e.date)
            return !e.isArchived && d >= DateMath.day(from) && d <= DateMath.day(to)
        }.sorted { $0.date < $1.date }
        var total = 0
        var mineTotal = 0
        let rows: [[String]] = list.map { e in
            let mine = myShare(e, data)
            total += e.amount
            mineTotal += mine
            let name = e.title.isEmpty ? e.vendor : e.title
            let property = data.properties.first { $0.id == e.propertyID }?.name ?? ""
            let who = Partnership.name(e.paidBy, settings)
            let split = settings.enabled ? Partnership.splitText(e.split, settings: settings) : "100%"
            return [Fmt.date(e.date), e.category.label, name, property, Fmt.inr(e.amount), who, split, Fmt.inr(mine)]
        }
        return ReportTable(title: L("Expenses", "Kharche"), subtitle: Fmt.date(from) + " – " + Fmt.date(to),
                           columns: [L("Date", "Tareekh"), L("Category", "Category"), L("Details", "Details"), L("Property", "Property"),
                                     L("Amount", "Amount"), L("Paid by", "Kisne diya"), L("Split", "Batwara"), L("My share", "Mera hissa")],
                           rows: rows, totals: [L("Total", "Kul"), "", "", "", Fmt.inr(total), "", "", Fmt.inr(mineTotal)])
    }
}
