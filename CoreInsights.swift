//  CoreInsights.swift
//  Rent increases, agreements, promises, occupancy and the dashboard snapshot.
//  Foundation only.

import Foundation

// MARK: - Rent increases

struct IncreaseProposal: Hashable {
    var date: Date
    var from: Int
    var to: Int
    var isDue: Bool
    var difference: Int { to - from }
}

enum Escalation {
    static func proposedAmount(from current: Int, mode: EscalationMode, value: Double) -> Int {
        guard value.isFinite else { return current }
        let result: Double
        switch mode {
        case .percent: result = Double(current) * (1 + value / 100)
        case .fixed: result = Double(current) + value
        }
        guard result.isFinite, abs(result) < 1e12 else { return current }
        return Int(result.rounded())
    }

    /// The next scheduled increase, worked out from the tenant's rule. Never applied by itself.
    static func next(for t: Tenant, asOf: Date = Date()) -> IncreaseProposal? {
        guard let rule = t.escalation, t.status != .vacated, !t.isArchived else { return nil }
        let from = Ledger.rent(of: t, on: DateMath.addDays(-1, to: rule.nextDate))
        guard from > 0 else { return nil }
        let to = proposedAmount(from: from, mode: rule.mode, value: rule.value)
        let date = DateMath.day(rule.nextDate)
        return IncreaseProposal(date: date, from: from, to: to, isDue: date <= DateMath.day(asOf))
    }

    /// Applies an approved increase from its effective date. Earlier months keep their old rent.
    static func apply(to t: inout Tenant, newRent: Int, effective: Date, reason: String, scheduledFor: Date?) {
        let day = DateMath.day(effective)
        let from = Ledger.rent(of: t, on: DateMath.addDays(-1, to: day))
        t.rentHistory.append(RentChange(effectiveDate: day, amount: newRent, reason: reason))
        t.escalationEvents.append(EscalationEvent(kind: .applied, scheduledDate: scheduledFor, effectiveDate: day,
                                                  fromAmount: from, toAmount: newRent, note: reason))
        if var rule = t.escalation {
            rule.nextDate = DateMath.addMonths(max(1, rule.everyMonths), to: day)
            t.escalation = rule
        }
    }

    /// Skips the scheduled increase and moves the schedule to the following one.
    static func skip(_ t: inout Tenant, note: String) {
        guard var rule = t.escalation else { return }
        let current = Ledger.rent(of: t, on: rule.nextDate)
        t.escalationEvents.append(EscalationEvent(kind: .skipped, scheduledDate: rule.nextDate,
                                                  fromAmount: current, toAmount: current, note: note))
        rule.nextDate = DateMath.addMonths(max(1, rule.everyMonths), to: rule.nextDate)
        t.escalation = rule
    }

    static func postpone(_ t: inout Tenant, to newDate: Date, note: String) {
        guard var rule = t.escalation else { return }
        t.escalationEvents.append(EscalationEvent(kind: .postponed, scheduledDate: rule.nextDate,
                                                  effectiveDate: DateMath.day(newDate), note: note))
        rule.nextDate = DateMath.day(newDate)
        t.escalation = rule
    }

    static func cancelSchedule(_ t: inout Tenant, note: String) {
        guard let rule = t.escalation else { return }
        t.escalationEvents.append(EscalationEvent(kind: .cancelled, scheduledDate: rule.nextDate, note: note))
        t.escalation = nil
    }
}

// MARK: - Agreements

enum AgreementStatus: String {
    case upcoming, active, open, expiring, expired
    var label: String {
        switch self {
        case .upcoming: return "Starts later"
        case .active: return "Active"
        case .open: return "No end date"
        case .expiring: return "Expiring soon"
        case .expired: return "Expired"
        }
    }
}

enum Agreements {
    static func status(_ a: Agreement, asOf: Date = Date()) -> AgreementStatus {
        let today = DateMath.day(asOf)
        if DateMath.day(a.startDate) > today { return .upcoming }
        guard let end = a.endDate else { return .open }
        let endDay = DateMath.day(end)
        if endDay < today { return .expired }
        if DateMath.daysBetween(today, endDay) <= max(0, a.reminderDays) { return .expiring }
        return .active
    }

    /// The agreement in force now: the latest one that has started, else the earliest upcoming one.
    static func current(of t: Tenant, asOf: Date = Date()) -> Agreement? {
        let newestFirst = t.agreements.sorted { $0.startDate > $1.startDate }
        let today = DateMath.day(asOf)
        return newestFirst.first { DateMath.day($0.startDate) <= today } ?? newestFirst.last
    }
}

// MARK: - Payment promises

enum PromiseStatus: String {
    case pending, kept, missed, cancelled
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .kept: return "Kept"
        case .missed: return "Missed"
        case .cancelled: return "Cancelled"
        }
    }
}

enum Promises {
    /// Kept if enough was paid between making the promise and the promised day.
    static func status(_ p: PaymentPromise, of t: Tenant, asOf: Date = Date()) -> PromiseStatus {
        if p.isCancelled { return .cancelled }
        let start = DateMath.day(p.madeOn)
        let end = DateMath.day(p.promisedDate)
        let paid = t.payments
            .filter { !$0.isReversed && $0.kind == .payment }
            .filter { payment in
                let d = DateMath.day(payment.date)
                return d >= start && d <= end
            }
            .reduce(0) { $0 + $1.amount }
        let kept = p.amount > 0 ? paid >= p.amount : paid > 0
        if kept { return .kept }
        if DateMath.day(asOf) > end { return .missed }
        return .pending
    }
}

// MARK: - Occupancy

enum Occupancy: String {
    case occupied, vacant, maintenance
    var label: String {
        switch self {
        case .occupied: return "Occupied"
        case .vacant: return "Vacant"
        case .maintenance: return "Under maintenance"
        }
    }
}

struct UnitInfo: Identifiable, Hashable {
    var property: RentalProperty
    var unit: RentalUnit?
    var tenant: Tenant?
    var occupancy: Occupancy

    var id: String { property.id.uuidString + "/" + (unit?.id.uuidString ?? "whole") }
    var name: String { unit?.name ?? "Whole property" }
}

struct HistoryItem: Identifiable, Hashable {
    var id: String
    var tenant: Tenant
    var unitName: String
    var from: Date?
    var to: Date?
}

// MARK: - Dashboard snapshot

struct DueItem: Identifiable, Hashable {
    var tenant: Tenant
    var line: ChargeLine
    var id: String { tenant.id.uuidString + line.id }
}

struct IncreaseItem: Identifiable, Hashable {
    var tenant: Tenant
    var proposal: IncreaseProposal
    var id: UUID { tenant.id }
}

struct AgreementItem: Identifiable, Hashable {
    var tenant: Tenant
    var agreement: Agreement
    var status: AgreementStatus
    var id: UUID { agreement.id }
}

struct RecentPayment: Identifiable, Hashable {
    var tenant: Tenant
    var payment: Payment
    var id: UUID { payment.id }
}

enum AlertKind: Int {
    case overdue = 0, increaseDue, agreementExpired, promiseMissed, followUp, depositToSettle, agreementExpiring, unpaidBill, vacantUnit
}

struct AlertItem: Identifiable, Hashable {
    var id: String
    var kind: AlertKind
    var title: String
    var detail: String
    var tenantID: UUID? = nil
    var propertyID: UUID? = nil
}

struct PropertyMoney: Hashable {
    var expectedThisMonth = 0
    var collectedThisMonth = 0
    var outstanding = 0
    var overdue = 0
    var expensesThisYear = 0
    var unitsTotal = 0
    var unitsOccupied = 0
}

struct PortfolioSnapshot {
    var asOf = Date()
    var expectedThisMonth = 0
    var collectedThisMonth = 0
    var outstanding = 0
    var overdue = 0
    var depositsHeld = 0
    var credit = 0
    var counts: [PayStatus: Int] = [:]
    var upcomingDues: [DueItem] = []
    var upcomingIncreases: [IncreaseItem] = []
    var agreements: [AgreementItem] = []
    var recentPayments: [RecentPayment] = []
    var alerts: [AlertItem] = []
    var ledgers: [UUID: TenantLedger] = [:]

    func count(_ status: PayStatus) -> Int { counts[status, default: 0] }
}

enum Portfolio {
    /// A tenant who is still living in the property (not vacated, not archived).
    static func isLive(_ t: Tenant) -> Bool { !t.isArchived && t.status != .vacated }

    static func units(of p: RentalProperty, tenants: [Tenant]) -> [UnitInfo] {
        if p.units.isEmpty {
            let t = tenants.first { isLive($0) && $0.propertyID == p.id }
            return [UnitInfo(property: p, unit: nil, tenant: t, occupancy: t == nil ? .vacant : .occupied)]
        }
        return p.units.map { (u: RentalUnit) -> UnitInfo in
            let t = tenants.first { isLive($0) && $0.unitID == u.id }
            let occupancy: Occupancy
            if t != nil {
                occupancy = .occupied
            } else {
                occupancy = u.underMaintenance ? .maintenance : .vacant
            }
            return UnitInfo(property: p, unit: u, tenant: t, occupancy: occupancy)
        }
    }

    static func unitName(_ unitID: UUID?, in p: RentalProperty?) -> String {
        guard let p = p, let unitID = unitID else { return "" }
        return p.units.first { $0.id == unitID }?.name ?? ""
    }

    /// Every tenant who has lived in the property, newest first.
    static func history(of p: RentalProperty, tenants: [Tenant]) -> [HistoryItem] {
        var items: [HistoryItem] = []
        for t in tenants {
            for a in t.assignments where a.propertyID == p.id {
                items.append(HistoryItem(id: a.id.uuidString, tenant: t, unitName: unitName(a.unitID, in: p),
                                         from: a.from, to: a.to))
            }
            if t.propertyID == p.id {
                items.append(HistoryItem(id: t.id.uuidString, tenant: t, unitName: unitName(t.unitID, in: p),
                                         from: t.startDate, to: t.endDate))
            }
        }
        return items.sorted { ($0.from ?? .distantPast) > ($1.from ?? .distantPast) }
    }

    static func money(of p: RentalProperty, data: AppData, snapshot: PortfolioSnapshot) -> PropertyMoney {
        var m = PropertyMoney()
        let today = DateMath.day(snapshot.asOf)
        let monthStart = DateMath.monthStart(today)
        let monthEnd = DateMath.monthEnd(today)
        let yearStart = DateMath.financialYearStart(today)
        let unitList = units(of: p, tenants: data.tenants)
        m.unitsTotal = unitList.count
        m.unitsOccupied = unitList.filter { $0.occupancy == .occupied }.count
        for t in data.tenants where !t.isArchived && t.propertyID == p.id {
            guard let ledger = snapshot.ledgers[t.id] else { continue }
            m.outstanding += ledger.outstanding
            m.overdue += ledger.overdue
            m.expectedThisMonth += ledger.lines
                .filter { $0.charge.dueDate >= monthStart && $0.charge.dueDate <= monthEnd && $0.charge.kind != .refundExcess }
                .reduce(0) { $0 + $1.charge.amount }
            m.collectedThisMonth += netCollected(t, from: monthStart, to: monthEnd)
        }
        m.expensesThisYear = data.expenses
            .filter { !$0.isArchived && $0.propertyID == p.id && DateMath.day($0.date) >= yearStart }
            .reduce(0) { $0 + $1.amount }
        return m
    }

    /// Payments received minus refunds paid out between two days (inclusive).
    static func netCollected(_ t: Tenant, from: Date, to: Date) -> Int {
        let start = DateMath.day(from)
        let end = DateMath.day(to)
        var total = 0
        for p in t.payments where !p.isReversed {
            let d = DateMath.day(p.date)
            guard d >= start && d <= end else { continue }
            total += p.kind == .payment ? p.amount : -p.amount
        }
        return total
    }

    static func snapshot(_ data: AppData, asOf: Date = Date()) -> PortfolioSnapshot {
        var s = PortfolioSnapshot()
        let today = DateMath.day(asOf)
        s.asOf = today
        let monthStart = DateMath.monthStart(today)
        let monthEnd = DateMath.monthEnd(today)
        let soon = DateMath.addDays(14, to: today)
        let grace = data.settings.gracePeriodDays
        var recent: [RecentPayment] = []

        for t in data.tenants where !t.isArchived {
            let ledger = Ledger.ledger(for: t, asOf: today, graceDays: grace)
            s.ledgers[t.id] = ledger
            s.outstanding += ledger.outstanding
            s.overdue += ledger.overdue
            s.credit += ledger.credit
            s.depositsHeld += Ledger.deposit(of: t).held
            s.expectedThisMonth += ledger.lines
                .filter { $0.charge.dueDate >= monthStart && $0.charge.dueDate <= monthEnd && $0.charge.kind != .refundExcess }
                .reduce(0) { $0 + $1.charge.amount }
            s.collectedThisMonth += netCollected(t, from: monthStart, to: monthEnd)
            if t.status != .vacated {
                s.counts[ledger.status, default: 0] += 1
            }

            for line in ledger.lines where line.outstanding > 0 && line.charge.dueDate >= today && line.charge.dueDate <= soon {
                s.upcomingDues.append(DueItem(tenant: t, line: line))
            }

            if let proposal = Escalation.next(for: t, asOf: today),
               DateMath.daysBetween(today, proposal.date) <= 60 {
                s.upcomingIncreases.append(IncreaseItem(tenant: t, proposal: proposal))
                if proposal.isDue {
                    s.alerts.append(AlertItem(id: "inc-" + t.id.uuidString, kind: .increaseDue,
                                              title: "Rent increase to review: " + t.name,
                                              detail: Fmt.inr(proposal.from) + " → " + Fmt.inr(proposal.to) + " from " + Fmt.date(proposal.date),
                                              tenantID: t.id))
                }
            }

            if t.status != .vacated, let agreement = Agreements.current(of: t, asOf: today) {
                let status = Agreements.status(agreement, asOf: today)
                if status == .expiring || status == .expired {
                    s.agreements.append(AgreementItem(tenant: t, agreement: agreement, status: status))
                    let end = agreement.endDate.map { Fmt.date($0) } ?? ""
                    s.alerts.append(AlertItem(id: "agr-" + agreement.id.uuidString,
                                              kind: status == .expired ? .agreementExpired : .agreementExpiring,
                                              title: (status == .expired ? "Agreement expired: " : "Agreement ending: ") + t.name,
                                              detail: "End date " + end, tenantID: t.id))
                }
            }

            for p in t.payments where !p.isReversed {
                recent.append(RecentPayment(tenant: t, payment: p))
            }

            if ledger.overdue > 0 {
                let since = ledger.oldestUnpaid.map { " since " + Fmt.date($0.charge.dueDate) } ?? ""
                s.alerts.append(AlertItem(id: "due-" + t.id.uuidString, kind: .overdue,
                                          title: t.name + " owes " + Fmt.inr(ledger.overdue),
                                          detail: "Overdue \(ledger.daysOverdue) days" + since, tenantID: t.id))
            }

            for promise in t.promises where Promises.status(promise, of: t, asOf: today) == .missed {
                guard DateMath.daysBetween(promise.promisedDate, today) <= 30 else { continue }
                s.alerts.append(AlertItem(id: "pro-" + promise.id.uuidString, kind: .promiseMissed,
                                          title: "Missed promise: " + t.name,
                                          detail: "Promised " + Fmt.inr(promise.amount) + " by " + Fmt.date(promise.promisedDate),
                                          tenantID: t.id))
            }

            for log in t.contacts where !log.followUpDone {
                guard let follow = log.followUpDate, DateMath.day(follow) <= today else { continue }
                s.alerts.append(AlertItem(id: "fol-" + log.id.uuidString, kind: .followUp,
                                          title: "Follow up with " + t.name,
                                          detail: log.note.isEmpty ? "Due " + Fmt.date(follow) : log.note,
                                          tenantID: t.id))
            }

            let held = Ledger.deposit(of: t).held
            if t.status == .vacated && held > 0 {
                s.alerts.append(AlertItem(id: "dep-" + t.id.uuidString, kind: .depositToSettle,
                                          title: "Settle deposit: " + t.name,
                                          detail: Fmt.inr(held) + " still held", tenantID: t.id))
            }
        }

        for p in data.properties where !p.isArchived {
            let vacant = units(of: p, tenants: data.tenants).filter { $0.occupancy == .vacant }
            if !vacant.isEmpty {
                let names = vacant.map { $0.name }.joined(separator: ", ")
                s.alerts.append(AlertItem(id: "vac-" + p.id.uuidString, kind: .vacantUnit,
                                          title: p.name + ": \(vacant.count) vacant",
                                          detail: names, propertyID: p.id))
            }
        }

        for e in data.expenses where !e.isArchived && !e.isPaid {
            let due = e.dueDate.map { " · due " + Fmt.date($0) } ?? ""
            let vendor = e.vendor.isEmpty ? e.category.label : e.vendor
            s.alerts.append(AlertItem(id: "bil-" + e.id.uuidString, kind: .unpaidBill,
                                      title: "Unpaid bill: " + vendor,
                                      detail: Fmt.inr(e.amount) + due, propertyID: e.propertyID))
        }

        s.upcomingDues.sort { $0.line.charge.dueDate < $1.line.charge.dueDate }
        s.upcomingIncreases.sort { $0.proposal.date < $1.proposal.date }
        s.recentPayments = Array(recent.sorted { Ledger.paymentOrder($1.payment, $0.payment) }.prefix(10))
        s.alerts.sort { $0.kind.rawValue < $1.kind.rawValue }
        return s
    }
}
