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
                    add("before", DateMath.addDays(-daysBefore, to: due), L("Rent due in \(daysBefore) days", "\(daysBefore) din mein rent"),
                        L(t.name + ": " + money + " due on " + Fmt.date(due) + ".", t.name + ": " + money + ", " + Fmt.date(due) + " ko dena hai."), t.id)
                }
                if s.remindOnDue {
                    add("due", due, L("Rent due today", "Aaj rent ka din"), L(t.name + ": " + money + " is due today.", t.name + ": " + money + " aaj dena hai."), t.id)
                }
                if s.remindOverdue {
                    add("late", DateMath.addDays(s.gracePeriodDays + 1, to: due), L("Rent overdue: ", "Rent overdue: ") + t.name,
                        L(money + " was due on " + Fmt.date(due) + ".", money + ", " + Fmt.date(due) + " ko dena tha."), t.id)
                }
            }

            // Dues already open.
            if ledger.outstanding > 0 {
                let partly = ledger.unpaidLines.contains { $0.paid > 0 }
                let what = partly ? L("Balance pending", "Baaki rakam") : L("Unpaid", "Baaki")
                let money = Fmt.inr(ledger.outstanding)
                if s.remindOnDue && ledger.unpaidLines.contains(where: { DateMath.day($0.charge.dueDate) == today }) {
                    add("due", today, L("Rent due today", "Aaj rent ka din"), L(t.name + ": " + money + " to collect.", t.name + ": " + money + " lena hai."), t.id)
                }
                if s.remindOverdue {
                    if ledger.overdue > 0 {
                        let since = ledger.oldestUnpaid.map { L(" since " + Fmt.date($0.charge.dueDate), ", " + Fmt.date($0.charge.dueDate) + " se") } ?? ""
                        var day = today
                        var count = 0
                        while day <= windowEnd && count < 5 {
                            add("overdue", day, L("Overdue rent: ", "Overdue rent: ") + t.name, what + ": " + money + since + ".", t.id)
                            day = DateMath.addDays(repeatEvery, to: day)
                            count += 1
                        }
                    } else if let oldest = ledger.unpaidLines.first {
                        add("late", DateMath.addDays(s.gracePeriodDays + 1, to: oldest.charge.dueDate),
                            L("Rent overdue: ", "Rent overdue: ") + t.name,
                            what + ": " + money + L(" was due on " + Fmt.date(oldest.charge.dueDate) + ".", ", " + Fmt.date(oldest.charge.dueDate) + " ko dena tha."), t.id)
                    }
                }
            }

            if s.remindPromises {
                for p in t.promises where Promises.status(p, of: t, asOf: now) == .pending {
                    add("promise", p.promisedDate, L("Payment promised today", "Aaj payment ka vaada"),
                        L(t.name + " promised " + Fmt.inr(p.amount) + " by today.", t.name + " ne aaj tak " + Fmt.inr(p.amount) + " dene ka vaada kiya tha."), t.id)
                }
            }

            if s.remindFollowUps {
                for log in t.contacts where !log.followUpDone {
                    guard let d = log.followUpDate else { continue }
                    add("follow-" + String(log.id.uuidString.prefix(8)), d, L("Follow up: ", "Follow up: ") + t.name,
                        log.note.isEmpty ? log.kind.label : log.note, t.id)
                }
            }

            if s.remindIncreases, let proposal = Escalation.next(for: t, asOf: now) {
                let change = Fmt.inr(proposal.from) + " → " + Fmt.inr(proposal.to)
                add("inc-early", DateMath.addDays(-max(1, s.increaseDaysBefore), to: proposal.date), L("Rent increase coming up", "Rent badhotri aane wali hai"),
                    L(t.name + ": " + change + " from " + Fmt.date(proposal.date) + ". Review it in RentBook.",
                      t.name + ": " + change + ", " + Fmt.date(proposal.date) + " se. RentBook mein review karein."), t.id)
                add("inc", proposal.date, L("Rent increase due today", "Aaj rent badhotri ka din"),
                    L(t.name + ": review and approve " + Fmt.inr(proposal.to) + " in RentBook.",
                      t.name + ": RentBook mein " + Fmt.inr(proposal.to) + " review karke approve karein."), t.id)
            }

            if s.remindAgreements, let a = Agreements.current(of: t, asOf: now), let end = a.endDate {
                add("agr-early", DateMath.addDays(-max(1, a.reminderDays), to: end), L("Agreement ending soon", "Agreement jaldi khatam"),
                    L(t.name + "'s agreement ends on " + Fmt.date(end) + ". Time to renew?",
                      t.name + " ka agreement " + Fmt.date(end) + " ko khatam hoga. Renew karna hai?"), t.id)
                add("agr", end, L("Agreement ends today", "Agreement aaj khatam"),
                    L(t.name + "'s agreement ends today.", t.name + " ka agreement aaj khatam ho raha hai."), t.id)
            }
        }

        let monday = DateMath.day(DateMath.nextWeekday(2, after: now))
        if s.remindDeposits {
            let names = data.tenants
                .filter { !$0.isArchived && $0.status == .vacated && Ledger.deposit(of: $0).held > 0 }
                .map { $0.name }
            if !names.isEmpty {
                add("deposit", monday, L("Deposits to settle", "Deposit ka hisaab baaki"), names.joined(separator: ", "), nil)
            }
        }
        if s.remindVacant {
            var vacant = 0
            for p in data.properties where !p.isArchived {
                vacant += Portfolio.units(of: p, tenants: data.tenants).filter { $0.occupancy == .vacant }.count
            }
            if vacant > 0 {
                add("vacant", monday, L("Vacant units", "Khaali units"),
                    L("\(vacant) unit" + (vacant == 1 ? " is" : "s are") + " vacant.", "\(vacant) unit khaali hain."), nil)
            }
        }

        // Recurring expenses on the day each one falls due, until it is saved or skipped.
        if s.remindRecurring {
            var saved = Set<String>()
            for e in data.expenses {
                if let id = e.recurringID, let month = e.recurringMonth { saved.insert(id.uuidString + "-" + month) }
            }
            for r in data.recurringExpenses where r.isActive {
                var month = DateMath.monthStart(today)
                while month <= windowEnd {
                    let key = DateMath.monthKey(month)
                    let day = DateMath.dayOfMonth(r.dayOfMonth, in: month)
                    let ended = r.endDate.map { day > DateMath.day($0) } ?? false
                    if day >= DateMath.day(r.startDate) && !ended && !saved.contains(r.id.uuidString + "-" + key)
                        && !r.skippedMonths.contains(key) {
                        let title = r.title.isEmpty ? r.category.label : r.title
                        add("rec-" + String(r.id.uuidString.prefix(8)), day, L("Recurring expense to review", "Recurring kharcha review karein"),
                            title + ": " + Fmt.inr(r.amount) + L(". Check it and save it in RentBook.", ". RentBook mein dekh kar save karein."), nil)
                    }
                    month = DateMath.addMonths(1, to: month)
                }
            }
        }

        out.sort { $0.date < $1.date }
        let keep = max(0, limit - 1)
        let truncated = out.count > keep
        var result = Array(out.prefix(keep))
        if !data.tenants.isEmpty || !data.recurringExpenses.isEmpty {
            let base: Date
            if truncated, let last = result.last {
                base = last.date
            } else {
                base = DateMath.at(DateMath.addDays(windowDays - 5, to: today), hour: s.reminderHour, minute: s.reminderMinute)
            }
            let refresh = base.addingTimeInterval(60)
            if refresh > now {
                result.append(PlannedReminder(id: "rb-refresh", date: refresh, title: L("Open RentBook", "RentBook kholein"),
                                              body: L("Open the app to keep your rent reminders up to date.", "Rent reminders chalu rakhne ke liye app kholein."),
                                              kind: "refresh"))
            }
        }
        return result
    }
}
