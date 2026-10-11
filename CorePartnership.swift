//  CorePartnership.swift
//  The settlement with a business partner (a brother sharing the rental income):
//  rent each partner collects from their own fixed tenants, shared and personal
//  expenses, transfers between the partners, and the running balance.
//  Also expense allocation rules and recurring expenses. Foundation only.

import Foundation

// MARK: - Partners and splits

enum Partner: String, Codable, CaseIterable, Identifiable {
    case me, partner
    var id: String { rawValue }

    var other: Partner { self == .me ? .partner : .me }
}

enum SplitKind: String, Codable, CaseIterable, Identifiable {
    case shared, mine, partners, custom
    var id: String { rawValue }
}

/// How an expense is shared between the partners.
struct ExpenseSplit: Codable, Hashable {
    var kind: SplitKind = .shared
    /// My share in percent, used for a custom split such as 60/40.
    var myPercent: Double = 50
}

extension ExpenseSplit {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.v(.kind, kind)
        myPercent = c.v(.myPercent, myPercent)
    }
}

enum RepairStatus: String, Codable, CaseIterable, Identifiable {
    case reported, inProgress, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reported: return L("Reported", "Bataya gaya")
        case .inProgress: return L("In progress", "Kaam chal raha hai")
        case .done: return L("Done", "Ho gaya")
        }
    }
}

// MARK: - Partnership records

struct PartnershipSettings: Codable, Hashable {
    var enabled = false
    var myName = "Me"
    var partnerName = "Brother"
    /// My share of the rental income in percent; the partner has the rest.
    var myShare: Double = 50
    /// Expenses before this day are left out of the settlement.
    var startDate: Date? = nil
    /// The balance on the start day: positive when I owed my partner, negative when they owed me.
    var openingBalance = 0
    /// For sending the monthly statement on WhatsApp.
    var partnerPhone = ""
}

extension PartnershipSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.v(.enabled, enabled)
        myName = c.v(.myName, myName)
        partnerName = c.v(.partnerName, partnerName)
        myShare = c.v(.myShare, myShare)
        startDate = c.v(.startDate, startDate)
        openingBalance = c.v(.openingBalance, openingBalance)
        partnerPhone = c.v(.partnerPhone, partnerPhone)
    }
}

/// A fixed tenant whose rent counts in the settlement, collected by one of the partners.
struct PartnerSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var place = ""
    var monthlyRent = 0
    var collectedBy: Partner = .me
    var isActive = true
    var notes = ""
}

extension PartnerSource {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        place = c.v(.place, place)
        monthlyRent = c.v(.monthlyRent, monthlyRent)
        collectedBy = c.v(.collectedBy, collectedBy)
        isActive = c.v(.isActive, isActive)
        notes = c.v(.notes, notes)
    }
}

enum PartnerEntryKind: String, Codable, CaseIterable, Identifiable {
    case rent, transfer, adjustment
    var id: String { rawValue }
}

/// Rent collected, money passed between the partners, or a correction to the balance.
/// Entries are never deleted: a mistake is voided and, if needed, replaced.
struct PartnerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: PartnerEntryKind = .rent
    var date = Date()
    /// The month the entry counts for, e.g. "2026-10".
    var month = ""
    var amount = 0
    /// Rent: the fixed tenant it came from.
    var sourceID: UUID? = nil
    /// Rent: who collected it. Transfer: who paid the other.
    /// Adjustment: who the balance moves in favour of.
    var party: Partner = .me
    var title = ""
    var note = ""
    var method: PaymentMethod? = nil
    var isVoided = false
    var voidReason = ""
    var correctionOf: UUID? = nil
    var createdAt = Date()
}

extension PartnerEntry {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        kind = c.v(.kind, kind)
        date = c.v(.date, date)
        month = c.v(.month, month)
        amount = c.v(.amount, amount)
        sourceID = c.v(.sourceID, sourceID)
        party = c.v(.party, party)
        title = c.v(.title, title)
        note = c.v(.note, note)
        method = c.v(.method, method)
        isVoided = c.v(.isVoided, isVoided)
        voidReason = c.v(.voidReason, voidReason)
        correctionOf = c.v(.correctionOf, correctionOf)
        createdAt = c.v(.createdAt, createdAt)
    }
}

/// A saved rule that suggests who pays and how an expense is split, by property and category.
struct AllocationRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var propertyID: UUID? = nil
    var category: ExpenseCategory? = nil
    var paidBy: Partner? = nil
    var split = ExpenseSplit()
}

extension AllocationRule {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        name = c.v(.name, name)
        propertyID = c.v(.propertyID, propertyID)
        category = c.v(.category, category)
        paidBy = c.v(.paidBy, paidBy)
        split = c.v(.split, split)
    }
}

struct PartnershipData: Codable, Hashable {
    var settings = PartnershipSettings()
    var sources: [PartnerSource] = []
    var entries: [PartnerEntry] = []
    var rules: [AllocationRule] = []
}

extension PartnershipData {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = c.v(.settings, settings)
        sources = c.v(.sources, sources)
        entries = c.v(.entries, entries)
        rules = c.v(.rules, rules)
    }
}

// MARK: - Recurring expenses

/// A monthly expense such as society maintenance or a watchman's salary. Each month an
/// entry is prepared for review; nothing is saved until it is approved.
struct RecurringExpense: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var category: ExpenseCategory = .maintenance
    var amount = 0
    var dayOfMonth = 1
    var propertyID: UUID? = nil
    var unitID: UUID? = nil
    var vendor = ""
    var paidBy: Partner = .me
    var split = ExpenseSplit()
    var startDate = Date()
    var endDate: Date? = nil
    var isActive = true
    var markPaid = true
    var skippedMonths: [String] = []
}

extension RecurringExpense {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, id)
        title = c.v(.title, title)
        category = c.v(.category, category)
        amount = c.v(.amount, amount)
        dayOfMonth = c.v(.dayOfMonth, dayOfMonth)
        propertyID = c.v(.propertyID, propertyID)
        unitID = c.v(.unitID, unitID)
        vendor = c.v(.vendor, vendor)
        paidBy = c.v(.paidBy, paidBy)
        split = c.v(.split, split)
        startDate = c.v(.startDate, startDate)
        endDate = c.v(.endDate, endDate)
        isActive = c.v(.isActive, isActive)
        markPaid = c.v(.markPaid, markPaid)
        skippedMonths = c.v(.skippedMonths, skippedMonths)
    }
}

/// A recurring expense waiting for review for one month.
struct PendingExpense: Identifiable, Hashable {
    var template: RecurringExpense
    var month: String
    var date: Date
    var id: String { template.id.uuidString + "-" + month }
}

// MARK: - Statements

struct PartnerRentLine: Identifiable, Hashable {
    var entry: PartnerEntry
    var sourceName: String
    /// Change in what I owe my partner.
    var effect: Int
    var id: UUID { entry.id }
}

struct PartnerExpenseLine: Identifiable, Hashable {
    var expense: Expense
    var myShare: Int
    var partnerShare: Int
    /// Change in what I owe my partner.
    var effect: Int
    var id: UUID { expense.id }
}

struct PartnerMonth: Identifiable, Hashable {
    var key: String
    var start: Date
    var opening: Int
    var rent: [PartnerRentLine] = []
    var expenses: [PartnerExpenseLine] = []
    var transfers: [PartnerEntry] = []
    var adjustments: [PartnerEntry] = []
    var closing: Int = 0

    var id: String { key }
    var rentMine: Int { rent.filter { $0.entry.party == .me }.reduce(0) { $0 + $1.entry.amount } }
    var rentPartner: Int { rent.filter { $0.entry.party == .partner }.reduce(0) { $0 + $1.entry.amount } }
    var totalRent: Int { rentMine + rentPartner }
    var rentEffect: Int { rent.reduce(0) { $0 + $1.effect } }
    var expenseEffect: Int { expenses.reduce(0) { $0 + $1.effect } }
    var expensesTotal: Int { expenses.reduce(0) { $0 + $1.expense.amount } }
    var transferEffect: Int { transfers.reduce(0) { $0 + Partnership.effect(of: $1) } }
    var adjustmentEffect: Int { adjustments.reduce(0) { $0 + Partnership.effect(of: $1) } }
    var isEmpty: Bool { rent.isEmpty && expenses.isEmpty && transfers.isEmpty && adjustments.isEmpty }
}

/// One line of the settlement history, in date order, with the balance after it.
struct PartnerHistoryLine: Identifiable, Hashable {
    var id: String
    var date: Date
    var title: String
    var detail: String
    var effect: Int
    var balance: Int
    var voided: Bool
    var entryID: UUID?
    var expenseID: UUID?
}

/// A month worked out the way the partners think about it: all the rent, less the expenses,
/// shared out, against what each partner already holds.
struct PartnerStatement: Hashable {
    var month: PartnerMonth
    var rentByMe = 0
    var rentByPartner = 0
    var expensesByMe = 0
    var expensesByPartner = 0
    /// The partner's part of all the rent and of all the expenses.
    var partnerRentShare = 0
    var partnerExpenseShare = 0
    var paidToPartner = 0
    var receivedFromPartner = 0
    /// Corrections, as a change in what I owe.
    var corrections = 0

    var totalRent: Int { rentByMe + rentByPartner }
    var totalExpenses: Int { expensesByMe + expensesByPartner }
    var partnerShare: Int { partnerRentShare - partnerExpenseShare }
    /// What the partner already holds: rent they collected less expenses they paid.
    var partnerHolds: Int { rentByPartner - expensesByPartner }
    /// What I owe my partner for the month's rent and expenses alone.
    var dueForMonth: Int { partnerShare - partnerHolds }
    var opening: Int { month.opening }
    var closing: Int { month.closing }
}

struct PartnerSummary {
    var months: [PartnerMonth]
    /// Positive: I owe my partner. Negative: my partner owes me.
    var balance: Int
}

enum Partnership {
    static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    static func myFraction(_ settings: PartnershipSettings) -> Double {
        clampFraction(settings.myShare / 100)
    }

    /// My part of an expense with this split, from 0 to 1.
    static func myFraction(_ split: ExpenseSplit, settings: PartnershipSettings) -> Double {
        switch split.kind {
        case .shared: return myFraction(settings)
        case .mine: return 1
        case .partners: return 0
        case .custom: return clampFraction(split.myPercent / 100)
        }
    }

    static func shares(of e: Expense, settings: PartnershipSettings) -> (mine: Int, partner: Int) {
        let mine = Int((Double(e.amount) * myFraction(e.split, settings: settings)).rounded())
        return (mine, e.amount - mine)
    }

    /// Change in what I owe my partner caused by an expense: they owe me their part of what
    /// I paid, and I owe them my part of what they paid.
    static func effect(of e: Expense, settings: PartnershipSettings) -> Int {
        let s = shares(of: e, settings: settings)
        return e.paidBy == .me ? -s.partner : s.mine
    }

    /// Rent collected by me is partly my partner's; rent they collected is partly mine.
    static func effect(ofRent entry: PartnerEntry, settings: PartnershipSettings) -> Int {
        let mine = myFraction(settings)
        if entry.party == .me {
            return Int((Double(entry.amount) * (1 - mine)).rounded())
        }
        return -Int((Double(entry.amount) * mine).rounded())
    }

    /// A transfer or adjustment. Money I pass to my partner lowers what I owe them.
    static func effect(of entry: PartnerEntry) -> Int {
        switch entry.kind {
        case .transfer, .adjustment:
            return entry.party == .me ? -entry.amount : entry.amount
        case .rent:
            return 0
        }
    }

    static func entryEffect(_ entry: PartnerEntry, settings: PartnershipSettings) -> Int {
        entry.kind == .rent ? effect(ofRent: entry, settings: settings) : effect(of: entry)
    }

    /// The first month of the settlement, if one is set. Records for earlier months are left
    /// out; what was owed before it is the opening balance.
    static func startMonth(_ settings: PartnershipSettings) -> Date? {
        settings.startDate.map { DateMath.monthStart($0) }
    }

    /// Whether an expense belongs in the settlement: from the start month on, and either paid
    /// by my partner or at least partly theirs.
    static func counts(_ e: Expense, settings: PartnershipSettings) -> Bool {
        guard !e.isArchived, e.amount > 0 else { return false }
        if let start = startMonth(settings), DateMath.monthStart(e.date) < start { return false }
        return e.paidBy == .partner || shares(of: e, settings: settings).partner > 0
    }

    /// Whether an entry is in the settlement period. Voided entries are checked separately.
    static func inPeriod(_ entry: PartnerEntry, settings: PartnershipSettings) -> Bool {
        guard let start = startMonth(settings) else { return true }
        return (monthDate(monthKey(of: entry)) ?? DateMath.monthStart(entry.date)) >= start
    }

    /// The month an entry counts for, e.g. "2026-10", falling back to the month of its date.
    static func monthKey(of entry: PartnerEntry) -> String {
        if let d = monthDate(entry.month) { return DateMath.monthKey(d) }
        return DateMath.monthKey(entry.date)
    }

    static func sourceName(_ entry: PartnerEntry, _ data: PartnershipData) -> String {
        if let id = entry.sourceID, let s = data.sources.first(where: { $0.id == id }) {
            return s.name
        }
        return entry.title.isEmpty ? L("Rent", "Rent") : entry.title
    }

    /// Month by month from the start (or the first record) to this month, oldest first.
    static func summary(_ data: AppData, asOf: Date = Date()) -> PartnerSummary {
        let p = data.partnership
        let settings = p.settings
        var entriesByMonth: [Date: [PartnerEntry]] = [:]
        for entry in p.entries where !entry.isVoided && inPeriod(entry, settings: settings) {
            let month = monthDate(monthKey(of: entry)) ?? DateMath.monthStart(entry.date)
            entriesByMonth[month, default: []].append(entry)
        }
        var expensesByMonth: [Date: [Expense]] = [:]
        for e in data.expenses where counts(e, settings: settings) {
            expensesByMonth[DateMath.monthStart(e.date), default: []].append(e)
        }

        // Every month with a record, and every month from the start to this one
        // (at most ten years of empty months).
        var monthStarts = Set(entriesByMonth.keys).union(expensesByMonth.keys)
        let thisMonth = DateMath.monthStart(asOf)
        if let first = startMonth(settings) ?? monthStarts.min() {
            var m = max(first, DateMath.addMonths(-119, to: thisMonth))
            while m <= thisMonth {
                monthStarts.insert(m)
                m = DateMath.addMonths(1, to: m)
            }
        }

        var months: [PartnerMonth] = []
        var balance = settings.openingBalance
        for start in monthStarts.sorted() {
            var m = PartnerMonth(key: DateMath.monthKey(start), start: start, opening: balance)
            let entries = (entriesByMonth[start] ?? []).sorted { a, b in
                a.date != b.date ? a.date < b.date : a.createdAt < b.createdAt
            }
            for entry in entries {
                switch entry.kind {
                case .rent:
                    m.rent.append(PartnerRentLine(entry: entry, sourceName: sourceName(entry, p),
                                                  effect: effect(ofRent: entry, settings: settings)))
                case .transfer:
                    m.transfers.append(entry)
                case .adjustment:
                    m.adjustments.append(entry)
                }
            }
            for e in (expensesByMonth[start] ?? []).sorted(by: { $0.date < $1.date }) {
                let s = shares(of: e, settings: settings)
                m.expenses.append(PartnerExpenseLine(expense: e, myShare: s.mine, partnerShare: s.partner,
                                                     effect: effect(of: e, settings: settings)))
            }
            balance += m.rentEffect + m.expenseEffect + m.transferEffect + m.adjustmentEffect
            m.closing = balance
            months.append(m)
        }
        return PartnerSummary(months: months, balance: balance)
    }

    /// The balance at the end of a month: the closing of the last month up to it.
    static func balance(_ summary: PartnerSummary, endOf month: Date, opening: Int) -> Int {
        let limit = DateMath.monthStart(month)
        return summary.months.last(where: { $0.start <= limit })?.closing ?? opening
    }

    /// Every record in date order with the balance after each one. Voided entries are
    /// listed, crossed out, without changing the balance.
    static func history(_ data: AppData) -> [PartnerHistoryLine] {
        let p = data.partnership
        let settings = p.settings
        struct TimelineItem {
            var date: Date
            var created: Date
            var line: PartnerHistoryLine
        }
        var items: [TimelineItem] = []
        for entry in p.entries where inPeriod(entry, settings: settings) {
            let effect = entry.isVoided ? 0 : entryEffect(entry, settings: settings)
            let title: String
            switch entry.kind {
            case .rent:
                let who = entry.party == .me ? settings.myName : settings.partnerName
                let source = sourceName(entry, p)
                title = L(source + " · rent collected by " + who, source + " · rent " + who + " ne liya")
            case .transfer:
                let other = settings.partnerName
                title = entry.party == .me ? L("Paid to " + other, other + " ko diye") : L("Received from " + other, other + " se mile")
            case .adjustment:
                title = L("Balance correction", "Balance mein sudhaar")
            }
            var detail = monthLabel(monthKey(of: entry))
            if !entry.note.isEmpty { detail += " · " + entry.note }
            if entry.isVoided {
                detail += " · " + L("voided", "radd") + (entry.voidReason.isEmpty ? "" : ": " + entry.voidReason)
            }
            items.append(TimelineItem(date: DateMath.day(entry.date), created: entry.createdAt,
                              line: PartnerHistoryLine(id: "p-" + entry.id.uuidString, date: DateMath.day(entry.date), title: title,
                                                       detail: detail, effect: effect, balance: 0, voided: entry.isVoided,
                                                       entryID: entry.id, expenseID: nil)))
        }
        for e in data.expenses where counts(e, settings: settings) {
            let s = shares(of: e, settings: settings)
            let who = e.paidBy == .me ? settings.myName : settings.partnerName
            let name = e.title.isEmpty ? (e.vendor.isEmpty ? e.category.label : e.vendor) : e.title
            let detail = L("Paid by ", "Kisne diya: ") + who + " · " + splitText(e.split, settings: settings)
                + " · " + settings.partnerName + " " + Fmt.inr(s.partner)
            items.append(TimelineItem(date: DateMath.day(e.date), created: e.date,
                              line: PartnerHistoryLine(id: "e-" + e.id.uuidString, date: DateMath.day(e.date), title: name,
                                                       detail: detail, effect: effect(of: e, settings: settings), balance: 0,
                                                       voided: false, entryID: nil, expenseID: e.id)))
        }
        items.sort { a, b in a.date != b.date ? a.date < b.date : a.created < b.created }
        var balance = settings.openingBalance
        var lines: [PartnerHistoryLine] = []
        for item in items {
            var line = item.line
            balance += line.effect
            line.balance = balance
            lines.append(line)
        }
        return lines
    }

    // MARK: Monthly statement

    static func statement(_ m: PartnerMonth) -> PartnerStatement {
        var s = PartnerStatement(month: m)
        for line in m.rent {
            if line.entry.party == .me {
                s.rentByMe += line.entry.amount
                s.partnerRentShare += line.effect
            } else {
                s.rentByPartner += line.entry.amount
                s.partnerRentShare += line.entry.amount + line.effect
            }
        }
        for line in m.expenses {
            if line.expense.paidBy == .me {
                s.expensesByMe += line.expense.amount
            } else {
                s.expensesByPartner += line.expense.amount
            }
            s.partnerExpenseShare += line.partnerShare
        }
        for t in m.transfers {
            if t.party == .me {
                s.paidToPartner += t.amount
            } else {
                s.receivedFromPartner += t.amount
            }
        }
        s.corrections = m.adjustmentEffect
        return s
    }

    static func partnerPercentText(_ settings: PartnershipSettings) -> String {
        Fmt.percent(((1 - myFraction(settings)) * 1000).rounded() / 10)
    }

    /// The month as a table for a PDF or Excel statement.
    static func statementTable(_ m: PartnerMonth, data: AppData) -> ReportTable {
        let settings = data.partnership.settings
        let s = statement(m)
        let me = settings.myName
        let other = settings.partnerName
        var rows: [[String]] = []
        rows.append([L("Rent collected", "Kul rent"), "", Fmt.inr(s.totalRent)])
        for line in m.rent {
            rows.append(["   " + line.sourceName, name(line.entry.party, settings), Fmt.inr(line.entry.amount)])
        }
        rows.append([L("Expenses", "Kharche"), "", Fmt.inr(s.totalExpenses)])
        for line in m.expenses {
            let e = line.expense
            let title = e.title.isEmpty ? (e.vendor.isEmpty ? e.category.label : e.vendor) : e.title
            rows.append(["   " + Fmt.date(e.date) + " " + title + " (" + splitText(e.split, settings: settings) + ")",
                         name(e.paidBy, settings), Fmt.inr(e.amount)])
        }
        let percent = partnerPercentText(settings)
        rows.append([L(other + "'s share of the rent (" + percent + ")", "Rent mein " + other + " ka hissa (" + percent + ")"), "",
                     Fmt.inr(s.partnerRentShare)])
        rows.append([L("Less " + other + "'s share of the expenses", "Ghatayein: kharchon mein " + other + " ka hissa"), "",
                     Fmt.inr(-s.partnerExpenseShare)])
        rows.append([L(other + "'s share for the month", "Is mahine " + other + " ka hissa"), "", Fmt.inr(s.partnerShare)])
        rows.append([L("Already with " + other + " (rent collected less expenses paid)",
                       other + " ke paas pehle se (liya rent minus diye kharche)"), "", Fmt.inr(s.partnerHolds)])
        rows.append([L("Due for the month", "Is mahine ka hisaab"), "", Fmt.inr(s.dueForMonth)])
        rows.append([L("Balance brought forward", "Pichla balance"), "", Fmt.inr(s.opening)])
        if s.paidToPartner > 0 {
            rows.append([L("Paid to " + other, other + " ko diye"), "", Fmt.inr(-s.paidToPartner)])
        }
        if s.receivedFromPartner > 0 {
            rows.append([L("Received from " + other, other + " se mile"), "", Fmt.inr(s.receivedFromPartner)])
        }
        if s.corrections != 0 {
            rows.append([L("Corrections", "Sudhaar"), "", Fmt.inr(s.corrections)])
        }
        return ReportTable(title: L("Partner statement", "Partner hisaab") + " · " + Fmt.month(m.start),
                           subtitle: me + " – " + other,
                           columns: [L("Item", "Item"), L("By", "Kisne"), L("Amount", "Amount")],
                           rows: rows,
                           totals: [L("Balance", "Balance"), "", Fmt.inr(s.closing)],
                           note: balanceTextNamed(s.closing, settings) + "\n"
                               + L("Balance: positive means " + me + " owes " + other + "; negative means " + other + " owes " + me + ".",
                                   "Balance: plus matlab " + other + " ko " + me + " se milne hain; minus matlab " + me + " ko " + other + " se milne hain."))
    }

    /// The month as a WhatsApp message from me to my partner.
    static func statementText(_ m: PartnerMonth, settings: PartnershipSettings, language: AppLanguage) -> String {
        func T(_ en: String, _ hi: String) -> String { L(en, hi, in: language) }
        let s = statement(m)
        var lines: [String] = []
        lines.append(T("Rent account for ", "") + Fmt.month(m.start) + T("", " ka rent hisaab"))
        lines.append("")
        lines.append(T("Rent collected: ", "Kul rent: ") + Fmt.inr(s.totalRent))
        lines.append(T("• By me: ", "• Maine liya: ") + Fmt.inr(s.rentByMe))
        lines.append(T("• By you: ", "• Aapne liya: ") + Fmt.inr(s.rentByPartner))
        if !m.expenses.isEmpty {
            lines.append("")
            lines.append(T("Expenses: ", "Kharche: ") + Fmt.inr(s.totalExpenses))
            for line in m.expenses {
                let e = line.expense
                let title = e.title.isEmpty ? (e.vendor.isEmpty ? e.category.label : e.vendor) : e.title
                let who = e.paidBy == .me ? T("paid by me", "maine diye") : T("paid by you", "aapne diye")
                lines.append("• " + title + " " + Fmt.inr(e.amount) + " (" + who + ", " + splitText(e.split, settings: settings) + ")")
            }
        }
        let percent = partnerPercentText(settings)
        lines.append("")
        lines.append(T("Your share of the rent (" + percent + "): ", "Rent mein aapka hissa (" + percent + "): ") + Fmt.inr(s.partnerRentShare))
        if s.partnerExpenseShare != 0 {
            lines.append(T("Less your share of expenses: ", "Ghatayein kharchon mein aapka hissa: ") + Fmt.inr(s.partnerExpenseShare))
        }
        lines.append(T("Your share for the month: ", "Is mahine aapka hissa: ") + Fmt.inr(s.partnerShare))
        lines.append(T("Already with you: ", "Aapke paas pehle se: ") + Fmt.inr(s.partnerHolds))
        lines.append(T("For this month: ", "Is mahine ka: ") + owedText(s.dueForMonth, language: language))
        lines.append("")
        if s.opening != 0 {
            lines.append(T("Earlier balance: ", "Pichla balance: ") + owedText(s.opening, language: language))
        }
        if s.paidToPartner > 0 {
            lines.append(T("Paid to you: ", "Aapko diye: ") + Fmt.inr(s.paidToPartner))
        }
        if s.receivedFromPartner > 0 {
            lines.append(T("Received from you: ", "Aapse mile: ") + Fmt.inr(s.receivedFromPartner))
        }
        if s.corrections != 0 {
            lines.append(T("Corrections: ", "Sudhaar: ") + owedText(s.corrections, language: language))
        }
        lines.append(T("Balance now: ", "Ab ka balance: ") + owedText(s.closing, language: language))
        return lines.joined(separator: "\n")
    }

    /// From me to my partner: "I owe you ₹5,000" / "You owe me ₹5,000" / "Nothing owed".
    static func owedText(_ amount: Int, language: AppLanguage) -> String {
        if amount > 0 {
            return L("I owe you " + Fmt.inr(amount), "mujhe aapko " + Fmt.inr(amount) + " dene hain", in: language)
        }
        if amount < 0 {
            return L("you owe me " + Fmt.inr(-amount), "aapko mujhe " + Fmt.inr(-amount) + " dene hain", in: language)
        }
        return L("nothing owed", "barabar", in: language)
    }

    // MARK: Preparing a month

    /// Active fixed tenants that have no rent recorded for the month yet.
    static func pendingRent(_ p: PartnershipData, month: String) -> [PartnerSource] {
        let done = Set(p.entries.filter { $0.kind == .rent && !$0.isVoided && monthKey(of: $0) == month }.compactMap { $0.sourceID })
        return p.sources.filter { $0.isActive && !done.contains($0.id) }
    }

    static func rentEntry(for source: PartnerSource, month: String, amount: Int, date: Date) -> PartnerEntry {
        var e = PartnerEntry()
        e.kind = .rent
        e.month = month
        e.date = DateMath.day(date)
        e.amount = amount
        e.sourceID = source.id
        e.party = source.collectedBy
        e.title = source.name
        return e
    }

    // MARK: Wording

    static func name(_ partner: Partner, _ settings: PartnershipSettings) -> String {
        partner == .me ? settings.myName : settings.partnerName
    }

    static func splitText(_ split: ExpenseSplit, settings: PartnershipSettings) -> String {
        let mine = Int((myFraction(split, settings: settings) * 100).rounded())
        switch split.kind {
        case .mine: return "100% " + settings.myName
        case .partners: return "100% " + settings.partnerName
        case .shared, .custom: return "\(mine)/\(100 - mine)"
        }
    }

    /// "You owe Brother ₹5,000" / "Brother owes you ₹5,000" / "All settled".
    static func balanceText(_ balance: Int, _ settings: PartnershipSettings) -> String {
        let name = settings.partnerName
        if balance > 0 {
            return L("You owe " + name + " " + Fmt.inr(balance), "Aapko " + name + " ko " + Fmt.inr(balance) + " dene hain")
        }
        if balance < 0 {
            return L(name + " owes you " + Fmt.inr(-balance), name + " se " + Fmt.inr(-balance) + " lene hain")
        }
        return L("All settled", "Hisaab barabar hai")
    }

    /// For documents others read: "Ravi owes Brother ₹5,000" / "Brother owes Ravi ₹5,000".
    static func balanceTextNamed(_ balance: Int, _ settings: PartnershipSettings) -> String {
        let me = settings.myName
        let other = settings.partnerName
        if balance > 0 {
            return L(me + " owes " + other + " " + Fmt.inr(balance), other + " ko " + me + " se " + Fmt.inr(balance) + " milne hain")
        }
        if balance < 0 {
            return L(other + " owes " + me + " " + Fmt.inr(-balance), me + " ko " + other + " se " + Fmt.inr(-balance) + " milne hain")
        }
        return L("All settled", "Hisaab barabar hai")
    }

    static func monthDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        return DateMath.make(y, m, 1)
    }

    static func monthLabel(_ key: String) -> String {
        guard let d = monthDate(key) else { return key }
        return Fmt.month(d)
    }

    // MARK: Allocation rules

    /// The most specific rule that fits: property and category, then either, then a general rule.
    static func rule(propertyID: UUID?, category: ExpenseCategory, rules: [AllocationRule]) -> AllocationRule? {
        var best: AllocationRule? = nil
        var bestScore = -1
        for r in rules {
            if let pid = r.propertyID, pid != propertyID { continue }
            if let cat = r.category, cat != category { continue }
            let score = (r.propertyID == nil ? 0 : 2) + (r.category == nil ? 0 : 1)
            if score > bestScore {
                best = r
                bestScore = score
            }
        }
        return best
    }

    // MARK: Recurring expenses

    /// Entries due up to today that have not been saved or skipped, from the last twelve months.
    static func pendingRecurring(_ data: AppData, asOf: Date = Date(), lookBackMonths: Int = 12) -> [PendingExpense] {
        let today = DateMath.day(asOf)
        var existing = Set<String>()
        for e in data.expenses {
            if let id = e.recurringID, let month = e.recurringMonth {
                existing.insert(id.uuidString + "-" + month)
            }
        }
        let earliest = DateMath.addMonths(-(max(1, lookBackMonths) - 1), to: DateMath.monthStart(today))
        var out: [PendingExpense] = []
        for t in data.recurringExpenses where t.isActive {
            var month = max(DateMath.monthStart(t.startDate), earliest)
            var safety = 0
            while month <= DateMath.monthStart(today) && safety < 60 {
                safety += 1
                if let end = t.endDate, month > DateMath.monthStart(end) { break }
                let key = DateMath.monthKey(month)
                let day = DateMath.dayOfMonth(t.dayOfMonth, in: month)
                let ended = t.endDate.map { day > DateMath.day($0) } ?? false
                if day <= today && day >= DateMath.day(t.startDate) && !ended
                    && !existing.contains(t.id.uuidString + "-" + key) && !t.skippedMonths.contains(key) {
                    out.append(PendingExpense(template: t, month: key, date: day))
                }
                month = DateMath.addMonths(1, to: month)
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    static func makeExpense(_ p: PendingExpense, amount: Int? = nil, date: Date? = nil) -> Expense {
        let t = p.template
        var e = Expense()
        e.title = t.title
        e.category = t.category
        e.propertyID = t.propertyID
        e.unitID = t.unitID
        e.vendor = t.vendor
        e.amount = amount ?? t.amount
        e.date = DateMath.day(date ?? p.date)
        e.isPaid = t.markPaid
        e.paidBy = t.paidBy
        e.split = t.split
        e.recurringID = t.id
        e.recurringMonth = p.month
        return e
    }
}
