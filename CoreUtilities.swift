//  CoreUtilities.swift
//  Electricity and water meter readings and bills, move-in and move-out handovers,
//  the final settlement record, and the rent records worksheet. Foundation only.

import Foundation

// MARK: - Meter readings

enum MeterKind: String, Codable, CaseIterable, Identifiable {
    case electricity, water
    var id: String { rawValue }
    var label: String { self == .electricity ? L("Electricity", "Bijli") : L("Water", "Paani") }
}

struct MeterReading: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: MeterKind = .electricity
    var date = Date()
    var reading: Double = 0
    var note = ""
    /// The extra charge billed for the usage up to this reading, if any.
    var chargeID: UUID? = nil
    var billedAmount = 0
    var rate: Double = 0
}

extension MeterReading {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        reading = c.v(.reading, reading)
        note = c.v(.note, note)
        chargeID = c.v(.chargeID, chargeID)
        billedAmount = c.v(.billedAmount, billedAmount)
        rate = c.v(.rate, rate)
    }
}

/// A reading with the usage since the one before it.
struct UsageLine: Identifiable, Hashable {
    var reading: MeterReading
    var previous: MeterReading?
    var units: Double
    var id: UUID { reading.id }
}

enum Utilities {
    static func rate(_ kind: MeterKind, tenant t: Tenant, settings: AppSettings) -> Double {
        switch kind {
        case .electricity: return t.electricityRate ?? settings.defaultElectricityRate
        case .water: return t.waterRate ?? settings.defaultWaterRate
        }
    }

    /// Readings of one meter, oldest first, each with the units used since the previous one.
    static func usage(_ kind: MeterKind, of t: Tenant) -> [UsageLine] {
        let readings = t.meterReadings.filter { $0.kind == kind }.sorted { $0.date < $1.date }
        var lines: [UsageLine] = []
        var previous: MeterReading? = nil
        for r in readings {
            let units = previous.map { max(0, r.reading - $0.reading) } ?? 0
            lines.append(UsageLine(reading: r, previous: previous, units: units))
            previous = r
        }
        return lines
    }

    /// The latest reading taken on or before a day.
    static func lastReading(_ kind: MeterKind, of t: Tenant, onOrBefore date: Date? = nil) -> MeterReading? {
        let limit = date.map { DateMath.day($0) }
        return t.meterReadings
            .filter { $0.kind == kind && (limit == nil || DateMath.day($0.date) <= limit!) }
            .max { $0.date < $1.date }
    }

    static func bill(units: Double, rate: Double) -> Int {
        guard units > 0, rate > 0 else { return 0 }
        return wholeRupees(units * rate)
    }

    static func number(_ value: Double) -> String {
        Fmt.number(value)
    }

    /// "Electricity: 120 units (1520 → 1640) × ₹8"
    static func chargeTitle(_ kind: MeterKind, from: Double, to: Double, rate: Double) -> String {
        let units = max(0, to - from)
        return kind.label + ": " + number(units) + " " + L("units", "unit") + " (" + number(from) + " → " + number(to)
            + ") × ₹" + number(rate)
    }
}

// MARK: - Handovers

enum HandoverKind: String, Codable {
    case moveIn, moveOut
    var label: String { self == .moveIn ? L("Move-in handover", "Move-in handover") : L("Move-out handover", "Move-out handover") }
}

struct KeyItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var count = 1
    var returned = 0
}

extension KeyItem {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        count = c.v(.count, count)
        returned = c.v(.returned, returned)
    }
}

/// The record made when a tenant moves in or out: date, meter readings, keys and condition.
struct Handover: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: HandoverKind = .moveIn
    var date = Date()
    var electricityReading: Double? = nil
    var waterReading: Double? = nil
    var condition = ""
    var keys: [KeyItem] = []
    var attachmentIDs: [UUID] = []
    var notes = ""
}

extension Handover {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        electricityReading = c.v(.electricityReading, electricityReading)
        waterReading = c.v(.waterReading, waterReading)
        condition = c.v(.condition, condition)
        keys = c.v(.keys, keys)
        attachmentIDs = c.v(.attachmentIDs, attachmentIDs)
        notes = c.v(.notes, notes)
    }

    var keysIssued: Int { keys.reduce(0) { $0 + $1.count } }
    var keysReturned: Int { keys.reduce(0) { $0 + min($1.returned, $1.count) } }
    var keysMissing: Int { keysIssued - keysReturned }
}

/// What was settled when the tenant left, kept for the record and the statement.
struct FinalSettlement: Codable, Hashable {
    var date = Date()
    var rentOwed = 0
    var utilityCharges = 0
    var advanceReturned = 0
    var depositHeld = 0
    var damages = 0
    var damagesReason = ""
    var depositUsedForRent = 0
    var depositRefund = 0
    var balanceDue = 0
    var refundMethod: PaymentMethod = .bank
    var notes = ""
}

extension FinalSettlement {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.v(.date, date)
        rentOwed = c.v(.rentOwed, rentOwed)
        utilityCharges = c.v(.utilityCharges, utilityCharges)
        advanceReturned = c.v(.advanceReturned, advanceReturned)
        depositHeld = c.v(.depositHeld, depositHeld)
        damages = c.v(.damages, damages)
        damagesReason = c.v(.damagesReason, damagesReason)
        depositUsedForRent = c.v(.depositUsedForRent, depositUsedForRent)
        depositRefund = c.v(.depositRefund, depositRefund)
        balanceDue = c.v(.balanceDue, balanceDue)
        refundMethod = c.v(.refundMethod, refundMethod)
        notes = c.v(.notes, notes)
    }
}

// MARK: - Rent records worksheet

/// One tenant's line in the rent records worksheet. Filled in by hand and kept apart
/// from the rent ledger. TDS and GST are percentages of the rent paid into the account;
/// rent paid in cash has neither.
struct RentSheetRow: Identifiable, Codable, Hashable {
    var id = UUID()
    var tenantName = ""
    var place = ""
    var startDate: Date? = nil
    var rent = 0
    // How it is paid.
    var cash = 0
    var bank = 0
    var tdsPercent: Double = 0
    var gstPercent: Double = 0
    // Rent after increment. Empty (nil) means the same as how it is paid.
    var cashNow: Int? = nil
    var bankNow: Int? = nil
    var tdsPercentNow: Double? = nil
    var gstPercentNow: Double? = nil
    // Maintenance as first paid, with its own TDS and GST on the account part.
    var maintCash = 0
    var maintBank = 0
    var maintTDSPercent: Double = 0
    var maintGSTPercent: Double = 0
    // Maintenance after increment. Empty (nil) means the same as first paid.
    var maintCashNow: Int? = nil
    var maintBankNow: Int? = nil
    var maintTDSPercentNow: Double? = nil
    var maintGSTPercentNow: Double? = nil
    var missedIncrease: Date? = nil
    var nextIncrease: Date? = nil
    var notes = ""
}

/// Rent split into cash and account, with TDS taken off and GST added to the account part.
struct SheetMoney: Hashable {
    var cash = 0
    var account = 0
    var tdsPercent: Double = 0
    var gstPercent: Double = 0

    var tds: Int { RentSheets.percentOf(account, tdsPercent) }
    var gst: Int { RentSheets.percentOf(account, gstPercent) }
    /// Account rent less TDS.
    var afterTDS: Int { account - tds }
    /// Account rent less TDS plus GST: the final (or current) rent in account.
    var finalAccount: Int { account - tds + gst }
    /// Cash plus the final rent in account.
    var total: Int { cash + finalAccount }
}

extension RentSheetRow {
    /// As set out under "How it is paid".
    var paid: SheetMoney {
        SheetMoney(cash: cash, account: bank, tdsPercent: tdsPercent, gstPercent: gstPercent)
    }

    /// After the increment. Anything left empty is the same as under "How it is paid".
    var current: SheetMoney {
        let c: Int = cashNow ?? cash
        let a: Int = bankNow ?? bank
        let t: Double = tdsPercentNow ?? tdsPercent
        let g: Double = gstPercentNow ?? gstPercent
        return SheetMoney(cash: c, account: a, tdsPercent: t, gstPercent: g)
    }

    /// Maintenance as first paid. Its total is the final maintenance.
    var maintenancePaid: SheetMoney {
        SheetMoney(cash: maintCash, account: maintBank, tdsPercent: maintTDSPercent, gstPercent: maintGSTPercent)
    }

    /// Maintenance after the increment. Anything left empty is the same as first paid.
    var maintenanceCurrent: SheetMoney {
        let c: Int = maintCashNow ?? maintCash
        let a: Int = maintBankNow ?? maintBank
        let t: Double = maintTDSPercentNow ?? maintTDSPercent
        let g: Double = maintGSTPercentNow ?? maintGSTPercent
        return SheetMoney(cash: c, account: a, tdsPercent: t, gstPercent: g)
    }

    /// Cash + final rent, plus the final maintenance, as first paid.
    var paidWithMaintenance: Int { paid.total + maintenancePaid.total }

    /// Total current rent plus the current final maintenance.
    var currentWithMaintenance: Int { current.total + maintenanceCurrent.total }

    var hasMaintenance: Bool {
        maintCash != 0 || maintBank != 0 || maintCashNow != nil || maintBankNow != nil
    }

    var hasIncrement: Bool {
        let rent = cashNow != nil || bankNow != nil || tdsPercentNow != nil || gstPercentNow != nil
        let maintenance = maintCashNow != nil || maintBankNow != nil || maintTDSPercentNow != nil || maintGSTPercentNow != nil
        return rent || maintenance
    }

    /// Months from the missed increment's month to this month, both counted; nil without a date.
    func missedMonths(asOf: Date = Date()) -> Int? {
        guard let missed = missedIncrease else { return nil }
        return RentSheets.monthsCounted(from: missed, to: asOf)
    }
}

extension RentSheetRow {
    /// RentBook 2.1 kept TDS and GST as rupee amounts and the current rent as one total.
    private enum OldKeys: String, CodingKey {
        case tds, gst, currentRent
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        tenantName = c.v(.tenantName, tenantName)
        place = c.v(.place, place)
        startDate = c.v(.startDate, startDate)
        rent = c.v(.rent, rent)
        cash = c.v(.cash, cash)
        bank = c.v(.bank, bank)
        tdsPercent = c.v(.tdsPercent, tdsPercent)
        gstPercent = c.v(.gstPercent, gstPercent)
        cashNow = c.v(.cashNow, cashNow)
        bankNow = c.v(.bankNow, bankNow)
        tdsPercentNow = c.v(.tdsPercentNow, tdsPercentNow)
        gstPercentNow = c.v(.gstPercentNow, gstPercentNow)
        maintCash = c.v(.maintCash, maintCash)
        maintBank = c.v(.maintBank, maintBank)
        maintTDSPercent = c.v(.maintTDSPercent, maintTDSPercent)
        maintGSTPercent = c.v(.maintGSTPercent, maintGSTPercent)
        maintCashNow = c.v(.maintCashNow, maintCashNow)
        maintBankNow = c.v(.maintBankNow, maintBankNow)
        maintTDSPercentNow = c.v(.maintTDSPercentNow, maintTDSPercentNow)
        maintGSTPercentNow = c.v(.maintGSTPercentNow, maintGSTPercentNow)
        missedIncrease = c.v(.missedIncrease, missedIncrease)
        nextIncrease = c.v(.nextIncrease, nextIncrease)
        notes = c.v(.notes, notes)
        if !c.contains(.tdsPercent) && !c.contains(.gstPercent), let old = try? decoder.container(keyedBy: OldKeys.self) {
            RentSheets.upgrade(&self, tds: old.v(.tds, 0), gst: old.v(.gst, 0), currentRent: old.v(.currentRent, 0))
        }
    }
}

struct RentSheet: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "Rent records"
    var rows: [RentSheetRow] = []
    var createdAt = Date()
}

extension RentSheet {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        rows = c.v(.rows, rows)
        createdAt = c.v(.createdAt, createdAt)
    }
}

/// Column totals of a worksheet. "Old" values are as first paid; the rest are after the increment.
struct SheetSums: Hashable {
    var tenants = 0
    var rent = 0
    var missedMonths = 0
    var oldCash = 0
    var oldAccount = 0
    var oldTDS = 0
    var oldGST = 0
    var finalAccount = 0
    var cashPlusFinal = 0
    var cash = 0
    var account = 0
    var tds = 0
    var gst = 0
    var currentAccount = 0
    var totalCurrent = 0
    var oldMaintCash = 0
    var oldMaintAccount = 0
    var oldMaintTDS = 0
    var oldMaintGST = 0
    var oldFinalMaint = 0
    var oldRentPlusMaint = 0
    var maintCash = 0
    var maintAccount = 0
    var maintTDS = 0
    var maintGST = 0
    var finalMaint = 0
    var rentPlusMaint = 0
}

enum RentSheets {
    /// A percentage of an amount in whole rupees: 10% of ₹25,000 is ₹2,500.
    static func percentOf(_ amount: Int, _ percent: Double) -> Int {
        guard percent.isFinite, percent != 0 else { return 0 }
        let value = (Double(amount) * percent / 100).rounded()
        guard abs(value) < 1e12 else { return 0 }
        return Int(value)
    }

    /// A percentage kept to two decimal places.
    static func roundedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }

    /// A percentage as typed: "10", "7.5"; empty for none.
    static func percentInput(_ value: Double) -> String {
        guard value.isFinite, value != 0, abs(value) < 1e6 else { return "" }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A percentage for a table cell: "10", "7.5", "0".
    static func percentNumber(_ value: Double) -> String {
        let text = percentInput(value)
        return text.isEmpty ? "0" : text
    }

    /// "10%", "7.5%".
    static func percentText(_ value: Double) -> String {
        percentNumber(value) + "%"
    }

    /// Months from one date's month to another's, both counted: April to October is 7.
    /// Zero while the date is still ahead.
    static func monthsCounted(from start: Date, to end: Date) -> Int {
        guard DateMath.day(start) <= DateMath.day(end) else { return 0 }
        let a = rbCalendar.dateComponents([.year, .month], from: start)
        let b = rbCalendar.dateComponents([.year, .month], from: end)
        let years = (b.year ?? 0) - (a.year ?? 0)
        let months = (b.month ?? 0) - (a.month ?? 0)
        return max(0, years * 12 + months + 1)
    }

    /// Moves a row saved by RentBook 2.1 over: TDS and GST amounts become percentages of the
    /// account rent, and a different current rent is split between cash and account in the
    /// same proportion as before. Anything that cannot be moved is kept in the notes.
    static func upgrade(_ r: inout RentSheetRow, tds: Int, gst: Int, currentRent: Int) {
        var kept: [String] = []
        if r.bank > 0 {
            r.tdsPercent = roundedPercent(Double(tds) * 100 / Double(r.bank))
            r.gstPercent = roundedPercent(Double(gst) * 100 / Double(r.bank))
        } else {
            if tds > 0 { kept.append("TDS " + Fmt.inr(tds)) }
            if gst > 0 { kept.append("GST " + Fmt.inr(gst)) }
        }
        let paid = r.cash + r.bank
        if currentRent > 0 && currentRent != paid {
            if paid > 0 {
                let cashPart = Int((Double(currentRent) * Double(r.cash) / Double(paid)).rounded())
                r.cashNow = cashPart
                r.bankNow = currentRent - cashPart
            } else if currentRent != r.rent {
                kept.append("current rent " + Fmt.inr(currentRent))
            }
        }
        if !kept.isEmpty {
            let note = "Earlier: " + kept.joined(separator: ", ")
            r.notes = r.notes.isEmpty ? note : r.notes + " · " + note
        }
    }

    static func sums(_ sheet: RentSheet, asOf: Date = Date()) -> SheetSums {
        var s = SheetSums()
        for r in sheet.rows {
            let p = r.paid
            let n = r.current
            s.tenants += 1
            s.rent += r.rent
            s.missedMonths += r.missedMonths(asOf: asOf) ?? 0
            s.oldCash += p.cash
            s.oldAccount += p.account
            s.oldTDS += p.tds
            s.oldGST += p.gst
            s.finalAccount += p.finalAccount
            s.cashPlusFinal += p.total
            s.cash += n.cash
            s.account += n.account
            s.tds += n.tds
            s.gst += n.gst
            s.currentAccount += n.finalAccount
            s.totalCurrent += n.total
            let pm = r.maintenancePaid
            let nm = r.maintenanceCurrent
            s.oldMaintCash += pm.cash
            s.oldMaintAccount += pm.account
            s.oldMaintTDS += pm.tds
            s.oldMaintGST += pm.gst
            s.oldFinalMaint += pm.total
            s.oldRentPlusMaint += p.total + pm.total
            s.maintCash += nm.cash
            s.maintAccount += nm.account
            s.maintTDS += nm.tds
            s.maintGST += nm.gst
            s.finalMaint += nm.total
            s.rentPlusMaint += n.total + nm.total
        }
        return s
    }

    static var columns: [String] {
        [L("Tenant", "Tenant"), L("Property", "Property"), L("Rent started", "Rent shuru"), L("Rent", "Rent"),
         L("Cash", "Cash"), L("Account", "Account"), L("TDS %", "TDS %"), L("GST %", "GST %"),
         L("Final rent in account", "Account mein final rent"), L("Cash + final rent", "Cash + final rent"),
         L("Maintenance cash", "Maintenance cash"), L("Maintenance account", "Maintenance account"),
         L("Maintenance TDS %", "Maintenance TDS %"), L("Maintenance GST %", "Maintenance GST %"),
         L("Final maintenance", "Final maintenance"), L("Rent + maintenance", "Rent + maintenance"),
         L("Cash after increment", "Badhotri ke baad cash"), L("Account after increment", "Badhotri ke baad account"),
         L("TDS % after increment", "Badhotri ke baad TDS %"), L("GST % after increment", "Badhotri ke baad GST %"),
         L("TDS", "TDS"), L("GST", "GST"), L("Current rent in account", "Account mein abhi ka rent"),
         L("Total current rent", "Kul abhi ka rent"),
         L("Maintenance cash after increment", "Badhotri ke baad maintenance cash"),
         L("Maintenance account after increment", "Badhotri ke baad maintenance account"),
         L("Maintenance TDS % after increment", "Badhotri ke baad maintenance TDS %"),
         L("Maintenance GST % after increment", "Badhotri ke baad maintenance GST %"),
         L("Maintenance TDS", "Maintenance TDS"), L("Maintenance GST", "Maintenance GST"),
         L("Current final maintenance", "Abhi ka final maintenance"),
         L("Total current rent + maintenance", "Kul abhi ka rent + maintenance"),
         L("Missed increment", "Chhooti badhotri"),
         L("Months since", "Kitne mahine"), L("Next increment", "Agli badhotri"), L("Notes", "Notes")]
    }

    private static func dateText(_ date: Date?) -> String {
        guard let d = date else { return "" }
        return Fmt.date(d)
    }

    private static func line(_ r: RentSheetRow, asOf: Date) -> [String] {
        let p = r.paid
        let n = r.current
        let started = dateText(r.startDate)
        let missed = dateText(r.missedIncrease)
        let months = r.missedMonths(asOf: asOf).map { String($0) } ?? ""
        let next = dateText(r.nextIncrease)
        var cells: [String] = [r.tenantName, r.place, started, Fmt.inr(r.rent)]
        cells += [Fmt.inr(p.cash), Fmt.inr(p.account), percentNumber(p.tdsPercent), percentNumber(p.gstPercent)]
        cells += [Fmt.inr(p.finalAccount), Fmt.inr(p.total)]
        let pm = r.maintenancePaid
        cells += [Fmt.inr(pm.cash), Fmt.inr(pm.account), percentNumber(pm.tdsPercent), percentNumber(pm.gstPercent)]
        cells += [Fmt.inr(pm.total), Fmt.inr(r.paidWithMaintenance)]
        cells += [Fmt.inr(n.cash), Fmt.inr(n.account), percentNumber(n.tdsPercent), percentNumber(n.gstPercent)]
        cells += [Fmt.inr(n.tds), Fmt.inr(n.gst), Fmt.inr(n.finalAccount), Fmt.inr(n.total)]
        let nm = r.maintenanceCurrent
        cells += [Fmt.inr(nm.cash), Fmt.inr(nm.account), percentNumber(nm.tdsPercent), percentNumber(nm.gstPercent)]
        cells += [Fmt.inr(nm.tds), Fmt.inr(nm.gst), Fmt.inr(nm.total), Fmt.inr(r.currentWithMaintenance)]
        cells += [missed, months, next, r.notes]
        return cells
    }

    /// Every column, for Excel and CSV.
    static func table(_ sheet: RentSheet, asOf: Date = Date()) -> ReportTable {
        let rows = sheet.rows.map { line($0, asOf: asOf) }
        let s = sums(sheet, asOf: asOf)
        var totals: [String] = [L("Total", "Kul"), "", "", Fmt.inr(s.rent)]
        totals += [Fmt.inr(s.oldCash), Fmt.inr(s.oldAccount), "", ""]
        totals += [Fmt.inr(s.finalAccount), Fmt.inr(s.cashPlusFinal)]
        totals += [Fmt.inr(s.oldMaintCash), Fmt.inr(s.oldMaintAccount), "", ""]
        totals += [Fmt.inr(s.oldFinalMaint), Fmt.inr(s.oldRentPlusMaint)]
        totals += [Fmt.inr(s.cash), Fmt.inr(s.account), "", ""]
        totals += [Fmt.inr(s.tds), Fmt.inr(s.gst), Fmt.inr(s.currentAccount), Fmt.inr(s.totalCurrent)]
        totals += [Fmt.inr(s.maintCash), Fmt.inr(s.maintAccount), "", ""]
        totals += [Fmt.inr(s.maintTDS), Fmt.inr(s.maintGST), Fmt.inr(s.finalMaint), Fmt.inr(s.rentPlusMaint)]
        let missedTotal = s.missedMonths > 0 ? String(s.missedMonths) : ""
        totals += ["", missedTotal, "", ""]
        return ReportTable(title: sheet.name, subtitle: L("\(sheet.rows.count) tenants", "\(sheet.rows.count) tenant"),
                           columns: columns, rows: rows, totals: totals)
    }

    /// The rent after increment only, narrow enough for a PDF page.
    static func shortTable(_ sheet: RentSheet, asOf: Date = Date()) -> ReportTable {
        let columns: [String] = [L("Tenant", "Tenant"), L("Property", "Property"), L("Cash", "Cash"), L("Account", "Account"),
                                 L("TDS %", "TDS %"), L("GST %", "GST %"), L("TDS", "TDS"), L("GST", "GST"),
                                 L("Current rent in account", "Account mein abhi ka rent"), L("Total current rent", "Kul abhi ka rent"),
                                 L("Final maintenance", "Final maintenance"), L("Rent + maintenance", "Rent + maintenance"),
                                 L("Months since missed increment", "Chhooti badhotri ke mahine"), L("Next increment", "Agli badhotri")]
        let rows: [[String]] = sheet.rows.map { r in
            let n = r.current
            let months = r.missedMonths(asOf: asOf).map { String($0) } ?? ""
            var cells: [String] = [r.tenantName, r.place, Fmt.inr(n.cash), Fmt.inr(n.account)]
            cells += [percentNumber(n.tdsPercent), percentNumber(n.gstPercent), Fmt.inr(n.tds), Fmt.inr(n.gst)]
            cells += [Fmt.inr(n.finalAccount), Fmt.inr(n.total)]
            cells += [Fmt.inr(r.maintenanceCurrent.total), Fmt.inr(r.currentWithMaintenance)]
            cells += [months, dateText(r.nextIncrease)]
            return cells
        }
        let s = sums(sheet, asOf: asOf)
        var totals: [String] = [L("Total", "Kul"), "", Fmt.inr(s.cash), Fmt.inr(s.account), "", ""]
        totals += [Fmt.inr(s.tds), Fmt.inr(s.gst), Fmt.inr(s.currentAccount), Fmt.inr(s.totalCurrent)]
        totals += [Fmt.inr(s.finalMaint), Fmt.inr(s.rentPlusMaint)]
        totals += [s.missedMonths > 0 ? String(s.missedMonths) : "", ""]
        return ReportTable(title: sheet.name,
                           subtitle: L("Rent after increment · \(sheet.rows.count) tenants", "Badhotri ke baad rent · \(sheet.rows.count) tenant"),
                           columns: columns, rows: rows, totals: totals)
    }

    /// Rows filled from RentBook's tenants, for those not already in the sheet. How the rent is
    /// split between cash and account is left for you to fill in.
    static func rows(from data: AppData, excluding names: Set<String>, asOf: Date = Date()) -> [RentSheetRow] {
        var out: [RentSheetRow] = []
        for t in data.tenants where Portfolio.isLive(t) && !names.contains(t.name.lowercased()) {
            var r = RentSheetRow()
            r.tenantName = t.name
            r.place = Reports.place(t, data)
            r.startDate = t.startDate
            let first = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
            let now = Ledger.currentRent(of: t, asOf: asOf)
            r.rent = first > 0 ? first : now
            if now > 0 && now != r.rent {
                r.notes = L("Rent now ", "Abhi ka rent ") + Fmt.inr(now)
            }
            r.nextIncrease = t.escalation?.nextDate
            out.append(r)
        }
        return out.sorted { $0.tenantName.localizedCaseInsensitiveCompare($1.tenantName) == .orderedAscending }
    }
}
