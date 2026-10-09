//  CoreBackup.swift
//  Backup file format, restore detection, moving data over from RentBook 1.0,
//  and sample data for trying the app. Foundation only.

import Foundation

struct EmbeddedFile: Codable, Hashable {
    var id = UUID()
    var fileName = ""
    var base64 = ""
}

/// A complete backup: all records plus every photo and document.
struct BackupPackage: Codable {
    var format = BackupCodec.formatName
    var version = 2
    var createdAt = Date()
    var data = AppData()
    var files: [EmbeddedFile] = []
}

enum BackupError: Error, LocalizedError {
    case unrecognised

    var errorDescription: String? {
        "This file isn't a RentBook backup."
    }
}

enum BackupCodec {
    static let formatName = "rentbook-backup"

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func package(_ data: AppData, files: [EmbeddedFile]) throws -> Data {
        try encoder.encode(BackupPackage(format: formatName, version: 2, createdAt: Date(), data: data, files: files))
    }

    /// Reads a full backup, a plain data file, or a RentBook 1.0 data file.
    static func decode(_ raw: Data) throws -> (data: AppData, files: [EmbeddedFile], fromVersion1: Bool) {
        let d = decoder
        if let pkg = try? d.decode(BackupPackage.self, from: raw), pkg.format == formatName {
            return (pkg.data, pkg.files, false)
        }
        if let app = try? d.decode(AppData.self, from: raw) {
            return (app, [], false)
        }
        if let old = try? d.decode([V1Tenant].self, from: raw) {
            return (Migration.fromVersion1(old), [], true)
        }
        throw BackupError.unrecognised
    }
}

// MARK: - RentBook 1.0 format

struct V1RentChange: Decodable {
    var id: UUID
    var effectiveDate: Date
    var amount: Int
}

struct V1Payment: Decodable {
    var id: UUID
    var date: Date
    var amount: Int
    var method: String
    var note: String
}

struct V1Tenant: Decodable {
    var id: UUID
    var name: String
    var phone: String
    var unit: String
    var startDate: Date
    var dueDay: Int
    var deposit: Int
    var openingBalance: Int
    var rentHistory: [V1RentChange]
    var payments: [V1Payment]
    var incrementPercent: Double
    var incrementEveryMonths: Int
    var nextIncrementDate: Date?
    var moveOutDate: Date?
    var notes: String
}

enum Migration {
    /// Converts RentBook 1.0 data. Version 1 billed whole months without
    /// partial-month rent, so proration stays off and balances come out the same.
    static func fromVersion1(_ old: [V1Tenant]) -> AppData {
        var data = AppData()
        let unitNames = Array(Set(old.map { clean($0.unit) }.filter { !$0.isEmpty })).sorted()
        var property: RentalProperty? = nil
        if !unitNames.isEmpty {
            var p = RentalProperty()
            p.code = "P001"
            p.name = "My Property"
            p.units = unitNames.map { RentalUnit(name: $0) }
            property = p
            data.properties = [p]
            data.settings.nextPropertyNumber = 2
        }

        for o in old {
            var t = Tenant()
            t.id = o.id
            t.name = o.name
            t.phone = o.phone
            t.startDate = DateMath.day(o.startDate)
            t.billingStartDate = DateMath.day(o.startDate)
            t.dueDay = min(max(o.dueDay, 1), 28)
            t.prorateFirst = false
            t.prorateLast = false
            t.openingBalance = max(0, o.openingBalance)
            t.rentHistory = o.rentHistory.map {
                RentChange(id: $0.id, effectiveDate: $0.effectiveDate, amount: $0.amount, reason: "")
            }
            t.payments = o.payments.map { old -> Payment in
                var p = Payment()
                p.id = old.id
                p.date = old.date
                p.amount = old.amount
                p.method = method(from: old.method)
                p.note = old.note
                p.createdAt = old.date
                return p
            }
            if o.deposit > 0 {
                t.deposits = [DepositEntry(kind: .received, date: DateMath.day(o.startDate), amount: o.deposit,
                                           reason: "Moved from RentBook 1.0")]
            }
            if let next = o.nextIncrementDate {
                t.escalation = EscalationRule(mode: .percent, value: o.incrementPercent,
                                              everyMonths: max(1, o.incrementEveryMonths),
                                              nextDate: DateMath.day(next), clause: "")
            }
            if let out = o.moveOutDate {
                t.endDate = DateMath.day(out)
                t.status = .vacated
            }
            t.notes = o.notes
            if let p = property, let unit = p.units.first(where: { $0.name == clean(o.unit) }) {
                t.propertyID = p.id
                t.unitID = unit.id
            }
            t.createdAt = o.startDate
            data.tenants.append(t)
        }

        // Number the receipts in date order.
        var refs: [(tenant: Int, payment: Int, date: Date)] = []
        for (ti, t) in data.tenants.enumerated() {
            for (pi, p) in t.payments.enumerated() {
                refs.append((tenant: ti, payment: pi, date: p.date))
            }
        }
        refs.sort { $0.date < $1.date }
        var number = 1
        for r in refs {
            data.tenants[r.tenant].payments[r.payment].receiptNumber = number
            number += 1
        }
        data.settings.nextReceiptNumber = number
        data.audit = [AuditEntry(action: "Data moved",
                                 details: "Moved from RentBook 1.0 (\(old.count) tenant" + (old.count == 1 ? ")." : "s)."))]
        return data
    }

    static func method(from text: String) -> PaymentMethod {
        switch text.lowercased() {
        case "upi": return .upi
        case "cash": return .cash
        case "bank transfer", "bank": return .bank
        case "cheque", "check": return .cheque
        default: return .other
        }
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Sample data

enum SampleData {
    /// A small made-up portfolio for trying the app.
    static func make(asOf: Date = Date()) -> AppData {
        var data = AppData()
        let today = DateMath.day(asOf)
        let thisMonth = DateMath.monthStart(today)

        var flats = RentalProperty()
        flats.code = "P001"
        flats.name = "Green Residency"
        flats.type = .flat
        flats.address = "12 MG Road"
        flats.city = "Pune"
        flats.units = [RentalUnit(name: "Flat 101"), RentalUnit(name: "Flat 102"), RentalUnit(name: "Flat 201")]

        var shops = RentalProperty()
        shops.code = "P002"
        shops.name = "Market Shops"
        shops.type = .shop
        shops.address = "Station Road"
        shops.city = "Pune"
        shops.units = [RentalUnit(name: "Shop 1"), RentalUnit(name: "Shop 2")]

        data.properties = [flats, shops]
        data.settings.nextPropertyNumber = 3

        func makeTenant(_ name: String, _ phone: String, property: RentalProperty, unit: Int,
                        rent: Int, monthsAgo: Int, deposit: Int) -> Tenant {
            var t = Tenant()
            t.name = name
            t.phone = phone
            t.propertyID = property.id
            t.unitID = property.units[unit].id
            let start = DateMath.addMonths(-monthsAgo, to: thisMonth)
            t.startDate = start
            t.billingStartDate = start
            t.dueDay = 5
            t.rentHistory = [RentChange(effectiveDate: start, amount: rent, reason: "Starting rent")]
            t.deposits = [DepositEntry(kind: .received, date: start, amount: deposit, reason: "At move-in")]
            t.escalation = EscalationRule(mode: .percent, value: 5, everyMonths: 11,
                                          nextDate: DateMath.addMonths(11, to: start), clause: "5% every 11 months")
            t.agreements = [Agreement(title: "Rental agreement", startDate: start,
                                      endDate: DateMath.addDays(-1, to: DateMath.addMonths(11, to: start)),
                                      noticePeriod: "1 month", renewalTerms: "Renewable by mutual consent",
                                      escalationClause: "5% after 11 months", depositTerms: "Refundable at move-out")]
            t.createdAt = start
            return t
        }

        func paid(_ t: inout Tenant, months: Int, partialLast: Int? = nil) {
            for k in 0..<months {
                let monthDate = DateMath.addMonths(k, to: t.startDate ?? thisMonth)
                let paidOn = DateMath.addDays(2, to: DateMath.dueDate(inMonthOf: monthDate, day: t.dueDay))
                guard paidOn <= today else { continue }
                var p = Payment()
                p.date = paidOn
                p.createdAt = paidOn
                p.amount = (k == months - 1 ? partialLast : nil) ?? Ledger.rent(of: t, on: paidOn)
                p.method = k % 2 == 0 ? .upi : .bank
                t.payments.append(p)
            }
        }

        var ravi = makeTenant("Ravi Kumar", "9876500001", property: flats, unit: 0, rent: 15000, monthsAgo: 8, deposit: 30000)
        paid(&ravi, months: 9, partialLast: 8000)

        var priya = makeTenant("Priya Sharma", "9876500002", property: flats, unit: 1, rent: 12000, monthsAgo: 3, deposit: 24000)
        paid(&priya, months: 2)
        priya.promises = [PaymentPromise(madeOn: DateMath.addDays(-3, to: today), promisedDate: DateMath.addDays(4, to: today),
                                         amount: 12000, note: "Salary on the 10th")]

        var mohan = makeTenant("Mohan Stores", "9876500003", property: shops, unit: 0, rent: 20000, monthsAgo: 5, deposit: 60000)
        mohan.recurringCharges = [RecurringCharge(title: "Maintenance", amount: 1500, startDate: mohan.startDate)]
        var advance = Payment()
        advance.date = DateMath.addDays(-10, to: today)
        advance.createdAt = advance.date
        advance.amount = 21500 * 7
        advance.method = .bank
        advance.reference = "NEFT 4471"
        mohan.payments = [advance]

        var anita = makeTenant("Anita Desai", "9876500004", property: flats, unit: 2, rent: 10000, monthsAgo: 10, deposit: 20000)
        paid(&anita, months: 9)
        anita.endDate = DateMath.addDays(-1, to: thisMonth)
        anita.status = .vacated
        anita.escalation = nil

        var number = 1
        var all = [ravi, priya, mohan, anita]
        for ti in all.indices {
            for pi in all[ti].payments.indices {
                all[ti].payments[pi].receiptNumber = number
                number += 1
            }
        }
        data.tenants = all
        data.settings.nextReceiptNumber = number

        var plumbing = Expense()
        plumbing.propertyID = flats.id
        plumbing.unitID = flats.units[0].id
        plumbing.category = .plumbing
        plumbing.date = DateMath.addDays(-20, to: today)
        plumbing.amount = 2500
        plumbing.vendor = "Sai Plumbers"

        var painting = Expense()
        painting.propertyID = flats.id
        painting.unitID = flats.units[2].id
        painting.category = .painting
        painting.date = DateMath.addDays(-2, to: today)
        painting.amount = 18000
        painting.vendor = "Colour Works"
        painting.isPaid = false
        painting.dueDate = DateMath.addDays(7, to: today)

        data.expenses = [plumbing, painting]
        data.audit = [AuditEntry(action: "Sample data", details: "Sample properties and tenants added.")]
        return data
    }
}
