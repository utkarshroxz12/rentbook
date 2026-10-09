//  CoreReminders.swift
//  Works out which reminders to schedule for the next few weeks.
//  The app hands this plan to iOS. Foundation only, so the plan can be tested.

import Foundation

struct PlannedReminder: Identifiable, Hashable {
    var id: String
    var date: Date
    var title: String
    var body: String
    var tenantID: UUID? = nil
    var kind: String
}

enum ReminderPlanner {
    static let windowDays = 45

    /// iOS keeps at most 64 pending reminders per app, so the plan is capped
    /// and ends with a nudge to open the app, which plans the next weeks.
    static func plan(_ data: AppData, now: Date = Date(), limit: Int = 60) -> [PlannedReminder] {
        let s = data.settings
        let today = DateMath.day(now)
        let windowEnd = DateMath.addDays(windowDays, to: today)
        var out: [PlannedReminder] = []

        func add(_ kind: String, _ day: Date, _ title: String, _ body: String, _ tenantID: UUID?) {
            let when = DateMath.at(day, hour: s.reminderHour, minute: s.reminderMinute)
            guard when > now, DateMath.day(day) <= windowEnd else { return }
            let id = "rb-" + kind + "-" + (tenantID?.uuidString ?? "all") + "-" + DateMath.dayKey(day)
            if out.contains(where: { $0.id == id }) { return }
            out.append(PlannedReminder(id: id, date: when, title: title, body: body, tenantID: tenantID, kind: kind))
        }

        for t in data.tenants where Portfolio.isLive(t) && t.reminders.enabled {
            let ledger = Ledger.ledger(for: t, asOf: now, graceDays: s.gracePeriodDays)
            let daysBefore = t.reminders.useDefaults ? s.remindDaysBefore : t.reminders.daysBefore
            let repeatEvery = max(1, t.reminders.useDefaults ? s.overdueRepeatDays : t.reminders.overdueEveryDays)

            // Charges coming up, after using any advance credit, grouped by due date.
            var creditLeft = ledger.advanceCredit
            var upcoming: [Date: Int] = [:]
            for line in ledger.upcomingLines where line.outstanding > 0 && line.charge.kind != .refundExcess {
                let used = min(creditLeft, line.outstanding)
                creditLeft -= used
                let left = line.outstanding - used
                if left > 0 { upcoming[line.charge.dueDate, default: 0] += left }
            }
            for (due, amount) in upcoming {
                let money = Fmt.inr(amount)
                if s.remindBeforeDue && daysBefore > 0 {
                    add("before", DateMath.addDays(-daysBefore, to: due), "Rent due in \(daysBefore) days",
                        t.name + ": " + money + " due on " + Fmt.date(due) + ".", t.id)
                }
                if s.remindOnDue {
                    add("due", due, "Rent due today", t.name + ": " + money + " is due today.", t.id)
                }
                if s.remindOverdue {
                    add("late", DateMath.addDays(s.gracePeriodDays + 1, to: due), "Rent overdue: " + t.name,
                        money + " was due on " + Fmt.date(due) + ".", t.id)
                }
            }

            // Dues already open.
            if ledger.outstanding > 0 {
                let partly = ledger.unpaidLines.contains { $0.paid > 0 }
                let what = partly ? "Balance pending" : "Unpaid"
                let money = Fmt.inr(ledger.outstanding)
                if s.remindOnDue && ledger.unpaidLines.contains(where: { DateMath.day($0.charge.dueDate) == today }) {
                    add("due", today, "Rent due today", t.name + ": " + money + " to collect.", t.id)
                }
                if s.remindOverdue {
                    if ledger.overdue > 0 {
                        let since = ledger.oldestUnpaid.map { " since " + Fmt.date($0.charge.dueDate) } ?? ""
                        var day = today
                        var count = 0
                        while day <= windowEnd && count < 5 {
                            add("overdue", day, "Overdue rent: " + t.name, what + ": " + money + since + ".", t.id)
                            day = DateMath.addDays(repeatEvery, to: day)
                            count += 1
                        }
                    } else if let oldest = ledger.unpaidLines.first {
                        add("late", DateMath.addDays(s.gracePeriodDays + 1, to: oldest.charge.dueDate),
                            "Rent overdue: " + t.name, what + ": " + money + " was due on " + Fmt.date(oldest.charge.dueDate) + ".", t.id)
                    }
                }
            }

            if s.remindPromises {
                for p in t.promises where Promises.status(p, of: t, asOf: now) == .pending {
                    add("promise", p.promisedDate, "Payment promised today",
                        t.name + " promised " + Fmt.inr(p.amount) + " by today.", t.id)
                }
            }

            if s.remindFollowUps {
                for log in t.contacts where !log.followUpDone {
                    guard let d = log.followUpDate else { continue }
                    add("follow-" + String(log.id.uuidString.prefix(8)), d, "Follow up: " + t.name,
                        log.note.isEmpty ? log.kind.label : log.note, t.id)
                }
            }

            if s.remindIncreases, let proposal = Escalation.next(for: t, asOf: now) {
                let change = Fmt.inr(proposal.from) + " → " + Fmt.inr(proposal.to)
                add("inc-early", DateMath.addDays(-max(1, s.increaseDaysBefore), to: proposal.date), "Rent increase coming up",
                    t.name + ": " + change + " from " + Fmt.date(proposal.date) + ". Review it in RentBook.", t.id)
                add("inc", proposal.date, "Rent increase due today",
                    t.name + ": review and approve " + Fmt.inr(proposal.to) + " in RentBook.", t.id)
            }

            if s.remindAgreements, let a = Agreements.current(of: t, asOf: now), let end = a.endDate {
                add("agr-early", DateMath.addDays(-max(1, a.reminderDays), to: end), "Agreement ending soon",
                    t.name + "'s agreement ends on " + Fmt.date(end) + ". Time to renew?", t.id)
                add("agr", end, "Agreement ends today", t.name + "'s agreement ends today.", t.id)
            }
        }

        let monday = DateMath.day(DateMath.nextWeekday(2, after: now))
        if s.remindDeposits {
            let names = data.tenants
                .filter { !$0.isArchived && $0.status == .vacated && Ledger.deposit(of: $0).held > 0 }
                .map { $0.name }
            if !names.isEmpty {
                add("deposit", monday, "Deposits to settle", names.joined(separator: ", "), nil)
            }
        }
        if s.remindVacant {
            var vacant = 0
            for p in data.properties where !p.isArchived {
                vacant += Portfolio.units(of: p, tenants: data.tenants).filter { $0.occupancy == .vacant }.count
            }
            if vacant > 0 {
                add("vacant", monday, "Vacant units", "\(vacant) unit" + (vacant == 1 ? " is" : "s are") + " vacant.", nil)
            }
        }

        out.sort { $0.date < $1.date }
        let keep = max(0, limit - 1)
        let truncated = out.count > keep
        var result = Array(out.prefix(keep))
        if !data.tenants.isEmpty {
            let base: Date
            if truncated, let last = result.last {
                base = last.date
            } else {
                base = DateMath.at(DateMath.addDays(windowDays - 5, to: today), hour: s.reminderHour, minute: s.reminderMinute)
            }
            let refresh = base.addingTimeInterval(60)
            if refresh > now {
                result.append(PlannedReminder(id: "rb-refresh", date: refresh, title: "Open RentBook",
                                              body: "Open the app to keep your rent reminders up to date.", kind: "refresh"))
            }
        }
        return result
    }
}
