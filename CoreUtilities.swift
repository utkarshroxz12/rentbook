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
/// from the rent ledger.
struct RentSheetRow: Identifiable, Codable, Hashable {
    var id = UUID()
    var tenantName = ""
    var place = ""
    var startDate: Date? = nil
    var rent = 0
    var cash = 0
    var bank = 0
    var tds = 0
    var gst = 0
    var currentRent = 0
    var nextIncrease: Date? = nil
    var notes = ""

    var received: Int { cash + bank }
}

extension RentSheetRow {
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
        tds = c.v(.tds, tds)
        gst = c.v(.gst, gst)
        currentRent = c.v(.currentRent, currentRent)
        nextIncrease = c.v(.nextIncrease, nextIncrease)
        notes = c.v(.notes, notes)
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

enum RentSheets {
    static var columns: [String] {
        [L("Tenant", "Tenant"), L("Property", "Property"), L("Rent started", "Rent shuru"), L("Rent", "Rent"),
         L("Cash", "Cash"), L("Account", "Account"), L("TDS", "TDS"), L("GST", "GST"),
         L("Current rent", "Abhi ka rent"), L("Next increase", "Agli badhotri"), L("Notes", "Notes")]
    }

    static func table(_ sheet: RentSheet) -> ReportTable {
        let rows: [[String]] = sheet.rows.map { r in
            [r.tenantName, r.place, r.startDate.map { Fmt.date($0) } ?? "", Fmt.inr(r.rent), Fmt.inr(r.cash),
             Fmt.inr(r.bank), Fmt.inr(r.tds), Fmt.inr(r.gst), Fmt.inr(r.currentRent),
             r.nextIncrease.map { Fmt.date($0) } ?? "", r.notes]
        }
        func sum(_ value: (RentSheetRow) -> Int) -> String {
            Fmt.inr(sheet.rows.reduce(0) { $0 + value($1) })
        }
        let totals = [L("Total", "Kul"), "", "", sum { $0.rent }, sum { $0.cash }, sum { $0.bank }, sum { $0.tds },
                      sum { $0.gst }, sum { $0.currentRent }, "", ""]
        return ReportTable(title: sheet.name, subtitle: L("\(sheet.rows.count) tenants", "\(sheet.rows.count) tenant"),
                           columns: columns, rows: rows, totals: totals)
    }

    /// Rows filled from RentBook's tenants, for those not already in the sheet.
    static func rows(from data: AppData, excluding names: Set<String>, asOf: Date = Date()) -> [RentSheetRow] {
        var out: [RentSheetRow] = []
        for t in data.tenants where Portfolio.isLive(t) && !names.contains(t.name.lowercased()) {
            var r = RentSheetRow()
            r.tenantName = t.name
            r.place = Reports.place(t, data)
            r.startDate = t.startDate
            r.rent = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.amount ?? 0
            r.currentRent = Ledger.currentRent(of: t, asOf: asOf)
            r.nextIncrease = t.escalation?.nextDate
            out.append(r)
        }
        return out.sorted { $0.tenantName.localizedCaseInsensitiveCompare($1.tenantName) == .orderedAscending }
    }
}
