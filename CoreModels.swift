//  CoreModels.swift
//  RentBook data model and shared helpers.
//  Foundation only: the rent tests compile this file on its own.

import Foundation

// MARK: - Calendar and dates

/// One Gregorian calendar for every date calculation in the app.
let rbCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone.current
    c.locale = Locale(identifier: "en_IN")
    return c
}()

enum DateMath {
    static func day(_ d: Date) -> Date { rbCalendar.startOfDay(for: d) }

    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        rbCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func monthStart(_ d: Date) -> Date {
        rbCalendar.date(from: rbCalendar.dateComponents([.year, .month], from: d)) ?? day(d)
    }

    static func addMonths(_ n: Int, to d: Date) -> Date {
        rbCalendar.date(byAdding: .month, value: n, to: d) ?? d
    }

    static func addDays(_ n: Int, to d: Date) -> Date {
        rbCalendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    /// Last day of the month, at the start of that day.
    static func monthEnd(_ d: Date) -> Date {
        addDays(-1, to: addMonths(1, to: monthStart(d)))
    }

    static func daysInMonth(_ d: Date) -> Int {
        rbCalendar.range(of: .day, in: .month, for: d)?.count ?? 30
    }

    /// Whole days from a to b, both taken at the start of the day.
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        rbCalendar.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }

    /// The rent due date in the month containing `d` (day kept within 1-28).
    static func dueDate(inMonthOf d: Date, day dueDay: Int) -> Date {
        var c = rbCalendar.dateComponents([.year, .month], from: d)
        c.day = min(max(dueDay, 1), 28)
        return rbCalendar.date(from: c) ?? day(d)
    }

    static func at(_ d: Date, hour: Int, minute: Int) -> Date {
        var c = rbCalendar.dateComponents([.year, .month, .day], from: d)
        c.hour = hour
        c.minute = minute
        return rbCalendar.date(from: c) ?? d
    }

    static func monthKey(_ d: Date) -> String {
        let c = rbCalendar.dateComponents([.year, .month], from: d)
        let y = c.year ?? 0
        let m = c.month ?? 0
        return "\(y)-" + (m < 10 ? "0\(m)" : "\(m)")
    }

    static func dayKey(_ d: Date) -> String {
        let c = rbCalendar.dateComponents([.year, .month, .day], from: d)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let dd = c.day ?? 0
        return "\(y)-" + (m < 10 ? "0\(m)" : "\(m)") + "-" + (dd < 10 ? "0\(dd)" : "\(dd)")
    }

    /// 1 April of the Indian financial year that contains `d`.
    static func financialYearStart(_ d: Date) -> Date {
        let c = rbCalendar.dateComponents([.year, .month], from: d)
        let year = c.year ?? 2000
        let start = (c.month ?? 1) >= 4 ? year : year - 1
        return make(start, 4, 1)
    }

    /// The next given weekday (1 = Sunday ... 7 = Saturday) after `d`.
    static func nextWeekday(_ weekday: Int, after d: Date) -> Date {
        var c = DateComponents()
        c.weekday = weekday
        return rbCalendar.nextDate(after: d, matching: c, matchingPolicy: .nextTime) ?? addDays(7, to: d)
    }
}

// MARK: - Formatting (Indian rupees and dates)

enum Fmt {
    private static let rupees: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_IN")
        f.currencyCode = "INR"
        f.currencySymbol = "₹"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        // Indian grouping (1,23,456), set explicitly so every platform agrees.
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.secondaryGroupingSize = 2
        return f
    }()

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.calendar = rbCalendar
        f.timeZone = rbCalendar.timeZone
        f.dateFormat = pattern
        return f
    }

    private static let dmy = formatter("dd/MM/yyyy")
    private static let dMonY = formatter("d MMM yyyy")
    private static let monY = formatter("MMM yyyy")
    private static let monOnly = formatter("MMM")
    private static let dmyTime = formatter("dd/MM/yyyy, h:mm a")

    static func inr(_ amount: Int) -> String {
        let text = rupees.string(from: NSNumber(value: abs(amount))) ?? "₹\(abs(amount))"
        return amount < 0 ? "-" + text : text
    }

    /// Indian date format, e.g. 09/10/2026.
    static func date(_ d: Date) -> String { dmy.string(from: d) }
    static func longDate(_ d: Date) -> String { dMonY.string(from: d) }
    static func month(_ d: Date) -> String { monY.string(from: d) }
    static func dateTime(_ d: Date) -> String { dmyTime.string(from: d) }

    static func monthRange(_ from: Date, _ to: Date) -> String {
        let sameYear = rbCalendar.component(.year, from: from) == rbCalendar.component(.year, from: to)
        if sameYear {
            return monOnly.string(from: from) + "–" + monY.string(from: to)
        }
        return monY.string(from: from) + "–" + monY.string(from: to)
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        if (n / 10) % 10 == 1 {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "–" }
        if value == value.rounded() { return "\(Int(value))%" }
        return String(format: "%.1f%%", value)
    }

    static func number(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "" }
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.2f", value)
    }
}

// MARK: - Typed amounts

/// Whole rupees from typed or pasted text: "₹12,500.00" gives 12500 (paise are dropped).
func parseAmount(_ text: String) -> Int? {
    let whole = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let digits = whole.filter { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, digits.count <= 12 else { return nil }
    return Int(digits)
}

/// A percentage or amount that may have decimals. Commas are thousands separators.
func parseDecimal(_ text: String) -> Double? {
    let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard let value = Double(cleaned), value.isFinite, abs(value) < 1e9 else { return nil }
    return value
}

/// Text for an amount field: empty for zero.
func amountString(_ value: Int) -> String {
    value > 0 ? String(value) : ""
}

/// Whole rupees from a stored decimal, safe for any value.
func wholeRupees(_ value: Double) -> Int {
    guard value.isFinite, abs(value) < 1e12 else { return 0 }
    return Int(value.rounded())
}

// MARK: - Tolerant decoding
// Every model decodes field by field with a fallback, so data saved by an older or
// newer version of the app still opens instead of failing as a whole.

extension KeyedDecodingContainer {
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return value
    }
}

// MARK: - Choices

enum PropertyType: String, Codable, CaseIterable, Identifiable {
    case flat, house, shop, office, room, pg, warehouse, plot, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: return "Flat"
        case .house: return "House"
        case .shop: return "Shop"
        case .office: return "Office"
        case .room: return "Room"
        case .pg: return "PG / Hostel"
        case .warehouse: return "Warehouse"
        case .plot: return "Plot / Land"
        case .other: return "Other"
        }
    }
}

enum TenantStatus: String, Codable, CaseIterable, Identifiable {
    case active, notice, vacated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .active: return "Active"
        case .notice: return "Notice period"
        case .vacated: return "Vacated"
        }
    }
}

enum BillingFrequency: Int, Codable, CaseIterable, Identifiable {
    case monthly = 1, quarterly = 3, halfYearly = 6, yearly = 12
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .halfYearly: return "Half-yearly"
        case .yearly: return "Yearly"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case upi, cash, bank, cheque, other, deposit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .upi: return "UPI"
        case .cash: return "Cash"
        case .bank: return "Bank transfer"
        case .cheque: return "Cheque"
        case .other: return "Other"
        case .deposit: return "From deposit"
        }
    }
    static let selectable: [PaymentMethod] = [.upi, .cash, .bank, .cheque, .other]
}

enum PaymentKind: String, Codable {
    case payment, refund
}

enum AdjustmentKind: String, Codable, CaseIterable, Identifiable {
    case extraCharge, discount, waiver, correction
    var id: String { rawValue }
    var label: String {
        switch self {
        case .extraCharge: return "Extra charge"
        case .discount: return "Discount"
        case .waiver: return "Waive rent"
        case .correction: return "Correction"
        }
    }
}

enum DepositEntryKind: String, Codable, CaseIterable, Identifiable {
    case received, additional, deduction, refund
    var id: String { rawValue }
    var label: String {
        switch self {
        case .received: return "Deposit received"
        case .additional: return "Additional deposit"
        case .deduction: return "Deduction"
        case .refund: return "Refund to tenant"
        }
    }
}

enum EscalationMode: String, Codable, CaseIterable, Identifiable {
    case percent, fixed
    var id: String { rawValue }
    var label: String { self == .percent ? "Percentage" : "Fixed amount" }
}

enum EscalationEventKind: String, Codable {
    case applied, skipped, postponed, cancelled
    var label: String {
        switch self {
        case .applied: return "Applied"
        case .skipped: return "Skipped"
        case .postponed: return "Postponed"
        case .cancelled: return "Schedule cancelled"
        }
    }
}

enum ContactKind: String, Codable, CaseIterable, Identifiable {
    case reminder, receipt, increase, renewal, call, note
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reminder: return "Rent reminder sent"
        case .receipt: return "Receipt sent"
        case .increase: return "Increase notice sent"
        case .renewal: return "Renewal message sent"
        case .call: return "Phone call"
        case .note: return "Note"
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case repairs, plumbing, electrical, painting, cleaning, maintenance, utilities, tax, insurance, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .repairs: return "Repairs"
        case .plumbing: return "Plumbing"
        case .electrical: return "Electrical"
        case .painting: return "Painting"
        case .cleaning: return "Cleaning"
        case .maintenance: return "Society maintenance"
        case .utilities: return "Utilities"
        case .tax: return "Property tax"
        case .insurance: return "Insurance"
        case .other: return "Other"
        }
    }
}

enum AttachmentKind: String, Codable {
    case photo, document
}

// MARK: - Properties

struct RentalUnit: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var underMaintenance = false
    var notes = ""
}

extension RentalUnit {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        underMaintenance = c.v(.underMaintenance, underMaintenance)
        notes = c.v(.notes, notes)
    }
}

struct RentalProperty: Identifiable, Codable, Hashable {
    var id = UUID()
    var code = ""
    var name = ""
    var type: PropertyType = .flat
    var address = ""
    var city = ""
    var mapLink = ""
    var units: [RentalUnit] = []
    var photoIDs: [UUID] = []
    var documentIDs: [UUID] = []
    var notes = ""
    var isArchived = false
    var createdAt = Date()
}

extension RentalProperty {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        code = c.v(.code, code)
        name = c.v(.name, name)
        type = c.v(.type, type)
        address = c.v(.address, address)
        city = c.v(.city, city)
        mapLink = c.v(.mapLink, mapLink)
        units = c.v(.units, units)
        photoIDs = c.v(.photoIDs, photoIDs)
        documentIDs = c.v(.documentIDs, documentIDs)
        notes = c.v(.notes, notes)
        isArchived = c.v(.isArchived, isArchived)
        createdAt = c.v(.createdAt, createdAt)
    }
}

// MARK: - Rent terms

struct RentChange: Identifiable, Codable, Hashable {
    var id = UUID()
    var effectiveDate = Date()
    var amount = 0
    var reason = ""
}

extension RentChange {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        effectiveDate = c.v(.effectiveDate, effectiveDate)
        amount = c.v(.amount, amount)
        reason = c.v(.reason, reason)
    }
}

struct EscalationRule: Codable, Hashable {
    var mode: EscalationMode = .percent
    var value: Double = 5
    var everyMonths = 12
    var nextDate = Date()
    var clause = ""
}

extension EscalationRule {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.v(.mode, mode)
        value = c.v(.value, value)
        everyMonths = c.v(.everyMonths, everyMonths)
        nextDate = c.v(.nextDate, nextDate)
        clause = c.v(.clause, clause)
    }
}

struct EscalationEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var recordedAt = Date()
    var kind: EscalationEventKind = .applied
    var scheduledDate: Date? = nil
    var effectiveDate: Date? = nil
    var fromAmount = 0
    var toAmount = 0
    var note = ""
}

extension EscalationEvent {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        recordedAt = c.v(.recordedAt, recordedAt)
        kind = c.v(.kind, kind)
        scheduledDate = c.v(.scheduledDate, scheduledDate)
        effectiveDate = c.v(.effectiveDate, effectiveDate)
        fromAmount = c.v(.fromAmount, fromAmount)
        toAmount = c.v(.toAmount, toAmount)
        note = c.v(.note, note)
    }
}

/// A monthly extra such as parking or maintenance, billed with the rent.
struct RecurringCharge: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "Maintenance"
    var amount = 0
    var startDate: Date? = nil
    var endDate: Date? = nil
}

extension RecurringCharge {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        title = c.v(.title, title)
        amount = c.v(.amount, amount)
        startDate = c.v(.startDate, startDate)
        endDate = c.v(.endDate, endDate)
    }
}

/// A one-off extra charge, or a discount, waiver or correction on one billing period.
struct Adjustment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AdjustmentKind = .extraCharge
    var date = Date()
    var periodKey: String? = nil
    var amount = 0
    var title = ""
    var reason = ""
    var isReversed = false
}

extension Adjustment {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        periodKey = c.v(.periodKey, periodKey)
        amount = c.v(.amount, amount)
        title = c.v(.title, title)
        reason = c.v(.reason, reason)
        isReversed = c.v(.isReversed, isReversed)
    }
}

// MARK: - Payments

struct Allocation: Codable, Hashable {
    var chargeKey = ""
    var amount = 0
}

extension Allocation {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chargeKey = c.v(.chargeKey, chargeKey)
        amount = c.v(.amount, amount)
    }
}

struct Payment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: PaymentKind = .payment
    var date = Date()
    var amount = 0
    var method: PaymentMethod = .upi
    var reference = ""
    var note = ""
    /// nil = settle the oldest dues first; otherwise the chosen months.
    var manualAllocations: [Allocation]? = nil
    var attachmentIDs: [UUID] = []
    var isReversed = false
    var reversalReason = ""
    var receiptNumber = 0
    var createdAt = Date()
    var editedAt: Date? = nil
}

extension Payment {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        amount = c.v(.amount, amount)
        method = c.v(.method, method)
        reference = c.v(.reference, reference)
        note = c.v(.note, note)
        manualAllocations = c.v(.manualAllocations, manualAllocations)
        attachmentIDs = c.v(.attachmentIDs, attachmentIDs)
        isReversed = c.v(.isReversed, isReversed)
        reversalReason = c.v(.reversalReason, reversalReason)
        receiptNumber = c.v(.receiptNumber, receiptNumber)
        createdAt = c.v(.createdAt, createdAt)
        editedAt = c.v(.editedAt, editedAt)
    }
}

struct DepositEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: DepositEntryKind = .received
    var date = Date()
    var amount = 0
    var reason = ""
    var linkedPaymentID: UUID? = nil
    var isReversed = false
}

extension DepositEntry {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        amount = c.v(.amount, amount)
        reason = c.v(.reason, reason)
        linkedPaymentID = c.v(.linkedPaymentID, linkedPaymentID)
        isReversed = c.v(.isReversed, isReversed)
    }
}

struct PaymentPromise: Identifiable, Codable, Hashable {
    var id = UUID()
    var madeOn = Date()
    var promisedDate = Date()
    var amount = 0
    var note = ""
    var isCancelled = false
}

extension PaymentPromise {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        madeOn = c.v(.madeOn, madeOn)
        promisedDate = c.v(.promisedDate, promisedDate)
        amount = c.v(.amount, amount)
        note = c.v(.note, note)
        isCancelled = c.v(.isCancelled, isCancelled)
    }
}

struct ContactLog: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: ContactKind = .reminder
    var note = ""
    var followUpDate: Date? = nil
    var followUpDone = false
}

extension ContactLog {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        date = c.v(.date, date)
        kind = c.v(.kind, kind)
        note = c.v(.note, note)
        followUpDate = c.v(.followUpDate, followUpDate)
        followUpDone = c.v(.followUpDone, followUpDone)
    }
}

// MARK: - Agreements

struct Agreement: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "Rental agreement"
    var startDate = Date()
    var endDate: Date? = nil
    var noticePeriod = ""
    var renewalTerms = ""
    var escalationClause = ""
    var depositTerms = ""
    var notes = ""
    var attachmentIDs: [UUID] = []
    var reminderDays = 30
    var createdAt = Date()
}

extension Agreement {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        title = c.v(.title, title)
        startDate = c.v(.startDate, startDate)
        endDate = c.v(.endDate, endDate)
        noticePeriod = c.v(.noticePeriod, noticePeriod)
        renewalTerms = c.v(.renewalTerms, renewalTerms)
        escalationClause = c.v(.escalationClause, escalationClause)
        depositTerms = c.v(.depositTerms, depositTerms)
        notes = c.v(.notes, notes)
        attachmentIDs = c.v(.attachmentIDs, attachmentIDs)
        reminderDays = c.v(.reminderDays, reminderDays)
        createdAt = c.v(.createdAt, createdAt)
    }
}

// MARK: - Tenants

/// Where a tenant lived and when, kept so property history survives moves.
struct UnitAssignment: Identifiable, Codable, Hashable {
    var id = UUID()
    var propertyID: UUID? = nil
    var unitID: UUID? = nil
    var from = Date()
    var to: Date? = nil
}

extension UnitAssignment {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        propertyID = c.v(.propertyID, propertyID)
        unitID = c.v(.unitID, unitID)
        from = c.v(.from, from)
        to = c.v(.to, to)
    }
}

struct TenantReminderPrefs: Codable, Hashable {
    var enabled = true
    var useDefaults = true
    var daysBefore = 3
    var overdueEveryDays = 3
}

extension TenantReminderPrefs {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.v(.enabled, enabled)
        useDefaults = c.v(.useDefaults, useDefaults)
        daysBefore = c.v(.daysBefore, daysBefore)
        overdueEveryDays = c.v(.overdueEveryDays, overdueEveryDays)
    }
}

struct Tenant: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var phone = ""
    var email = ""
    var address = ""
    var emergencyContact = ""
    var photoID: UUID? = nil
    var propertyID: UUID? = nil
    var unitID: UUID? = nil
    var status: TenantStatus = .active
    var startDate: Date? = nil
    var endDate: Date? = nil
    var billingStartDate: Date? = nil
    var frequency: BillingFrequency = .monthly
    var dueDay = 5
    var prorateFirst = true
    var prorateLast = true
    var rentHistory: [RentChange] = []
    var escalation: EscalationRule? = nil
    var escalationEvents: [EscalationEvent] = []
    var recurringCharges: [RecurringCharge] = []
    var adjustments: [Adjustment] = []
    var payments: [Payment] = []
    var deposits: [DepositEntry] = []
    var openingBalance = 0
    var promises: [PaymentPromise] = []
    var contacts: [ContactLog] = []
    var agreements: [Agreement] = []
    var assignments: [UnitAssignment] = []
    var documentIDs: [UUID] = []
    var preferredMethod: PaymentMethod? = nil
    var specialTerms = ""
    var notes = ""
    var reminders = TenantReminderPrefs()
    var isArchived = false
    var createdAt = Date()
}

extension Tenant {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        phone = c.v(.phone, phone)
        email = c.v(.email, email)
        address = c.v(.address, address)
        emergencyContact = c.v(.emergencyContact, emergencyContact)
        photoID = c.v(.photoID, photoID)
        propertyID = c.v(.propertyID, propertyID)
        unitID = c.v(.unitID, unitID)
        status = c.v(.status, status)
        startDate = c.v(.startDate, startDate)
        endDate = c.v(.endDate, endDate)
        billingStartDate = c.v(.billingStartDate, billingStartDate)
        frequency = c.v(.frequency, frequency)
        dueDay = c.v(.dueDay, dueDay)
        prorateFirst = c.v(.prorateFirst, prorateFirst)
        prorateLast = c.v(.prorateLast, prorateLast)
        rentHistory = c.v(.rentHistory, rentHistory)
        escalation = c.v(.escalation, escalation)
        escalationEvents = c.v(.escalationEvents, escalationEvents)
        recurringCharges = c.v(.recurringCharges, recurringCharges)
        adjustments = c.v(.adjustments, adjustments)
        payments = c.v(.payments, payments)
        deposits = c.v(.deposits, deposits)
        openingBalance = c.v(.openingBalance, openingBalance)
        promises = c.v(.promises, promises)
        contacts = c.v(.contacts, contacts)
        agreements = c.v(.agreements, agreements)
        assignments = c.v(.assignments, assignments)
        documentIDs = c.v(.documentIDs, documentIDs)
        preferredMethod = c.v(.preferredMethod, preferredMethod)
        specialTerms = c.v(.specialTerms, specialTerms)
        notes = c.v(.notes, notes)
        reminders = c.v(.reminders, reminders)
        isArchived = c.v(.isArchived, isArchived)
        createdAt = c.v(.createdAt, createdAt)
    }
}

// MARK: - Expenses, files and history

struct Expense: Identifiable, Codable, Hashable {
    var id = UUID()
    var propertyID: UUID? = nil
    var unitID: UUID? = nil
    var category: ExpenseCategory = .repairs
    var date = Date()
    var amount = 0
    var vendor = ""
    var note = ""
    var isPaid = true
    var dueDate: Date? = nil
    var attachmentIDs: [UUID] = []
    var isArchived = false
}

extension Expense {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        propertyID = c.v(.propertyID, propertyID)
        unitID = c.v(.unitID, unitID)
        category = c.v(.category, category)
        date = c.v(.date, date)
        amount = c.v(.amount, amount)
        vendor = c.v(.vendor, vendor)
        note = c.v(.note, note)
        isPaid = c.v(.isPaid, isPaid)
        dueDate = c.v(.dueDate, dueDate)
        attachmentIDs = c.v(.attachmentIDs, attachmentIDs)
        isArchived = c.v(.isArchived, isArchived)
    }
}

struct AttachmentMeta: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName = ""
    var originalName = ""
    var kind: AttachmentKind = .document
    var category = ""
    var addedAt = Date()
    var byteCount = 0
}

extension AttachmentMeta {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        fileName = c.v(.fileName, fileName)
        originalName = c.v(.originalName, originalName)
        kind = c.v(.kind, kind)
        category = c.v(.category, category)
        addedAt = c.v(.addedAt, addedAt)
        byteCount = c.v(.byteCount, byteCount)
    }
}

struct AuditEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var tenantID: UUID? = nil
    var propertyID: UUID? = nil
    var action = ""
    var details = ""
}

extension AuditEntry {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        date = c.v(.date, date)
        tenantID = c.v(.tenantID, tenantID)
        propertyID = c.v(.propertyID, propertyID)
        action = c.v(.action, action)
        details = c.v(.details, details)
    }
}

// MARK: - Settings

struct AppSettings: Codable, Hashable {
    var defaultDueDay = 5
    var gracePeriodDays = 5
    var defaultProrate = true
    var autoAllocate = true
    var defaultEscalationMode: EscalationMode = .percent
    var defaultEscalationValue: Double = 5
    var defaultEscalationMonths = 11
    var defaultRecurringCharges: [RecurringCharge] = []
    var reminderHour = 10
    var reminderMinute = 0
    var remindBeforeDue = true
    var remindDaysBefore = 3
    var remindOnDue = true
    var remindOverdue = true
    var overdueRepeatDays = 3
    var remindPromises = true
    var remindFollowUps = true
    var remindIncreases = true
    var increaseDaysBefore = 30
    var remindAgreements = true
    var agreementDaysBefore = 30
    var remindVacant = true
    var remindDeposits = true
    var appLockEnabled = false
    var lockAfterMinutes = 1
    var landlordName = ""
    var landlordPhone = ""
    var nextReceiptNumber = 1
    var nextPropertyNumber = 1
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultDueDay = c.v(.defaultDueDay, defaultDueDay)
        gracePeriodDays = c.v(.gracePeriodDays, gracePeriodDays)
        defaultProrate = c.v(.defaultProrate, defaultProrate)
        autoAllocate = c.v(.autoAllocate, autoAllocate)
        defaultEscalationMode = c.v(.defaultEscalationMode, defaultEscalationMode)
        defaultEscalationValue = c.v(.defaultEscalationValue, defaultEscalationValue)
        defaultEscalationMonths = c.v(.defaultEscalationMonths, defaultEscalationMonths)
        defaultRecurringCharges = c.v(.defaultRecurringCharges, defaultRecurringCharges)
        reminderHour = c.v(.reminderHour, reminderHour)
        reminderMinute = c.v(.reminderMinute, reminderMinute)
        remindBeforeDue = c.v(.remindBeforeDue, remindBeforeDue)
        remindDaysBefore = c.v(.remindDaysBefore, remindDaysBefore)
        remindOnDue = c.v(.remindOnDue, remindOnDue)
        remindOverdue = c.v(.remindOverdue, remindOverdue)
        overdueRepeatDays = c.v(.overdueRepeatDays, overdueRepeatDays)
        remindPromises = c.v(.remindPromises, remindPromises)
        remindFollowUps = c.v(.remindFollowUps, remindFollowUps)
        remindIncreases = c.v(.remindIncreases, remindIncreases)
        increaseDaysBefore = c.v(.increaseDaysBefore, increaseDaysBefore)
        remindAgreements = c.v(.remindAgreements, remindAgreements)
        agreementDaysBefore = c.v(.agreementDaysBefore, agreementDaysBefore)
        remindVacant = c.v(.remindVacant, remindVacant)
        remindDeposits = c.v(.remindDeposits, remindDeposits)
        appLockEnabled = c.v(.appLockEnabled, appLockEnabled)
        lockAfterMinutes = c.v(.lockAfterMinutes, lockAfterMinutes)
        landlordName = c.v(.landlordName, landlordName)
        landlordPhone = c.v(.landlordPhone, landlordPhone)
        nextReceiptNumber = c.v(.nextReceiptNumber, nextReceiptNumber)
        nextPropertyNumber = c.v(.nextPropertyNumber, nextPropertyNumber)
    }
}

// MARK: - Everything the app stores

struct AppData: Codable {
    var schemaVersion = 2
    var properties: [RentalProperty] = []
    var tenants: [Tenant] = []
    var expenses: [Expense] = []
    var attachments: [AttachmentMeta] = []
    var audit: [AuditEntry] = []
    var settings = AppSettings()
    var lastModified = Date()
}

extension AppData {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required, so an unrelated JSON file is never mistaken for RentBook data.
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        properties = c.v(.properties, properties)
        tenants = c.v(.tenants, tenants)
        expenses = c.v(.expenses, expenses)
        attachments = c.v(.attachments, attachments)
        audit = c.v(.audit, audit)
        settings = c.v(.settings, settings)
        lastModified = c.v(.lastModified, lastModified)
    }
}
