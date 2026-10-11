//  StoreFeatures.swift
//  Store actions for the partnership with your brother, recurring expenses, meter
//  readings, handovers and the rent records worksheets. Every change is saved at once
//  and noted in the change history.

import SwiftUI

extension Store {
    // MARK: - Partnership

    var partnership: PartnershipData { data.partnership }
    var partnerSettings: PartnershipSettings { data.partnership.settings }

    func savePartnershipSettings(_ new: PartnershipSettings) {
        let old = data.partnership.settings
        var changes: [String] = []
        if old.enabled != new.enabled { changes.append(new.enabled ? "turned on" : "turned off") }
        if old.myName != new.myName || old.partnerName != new.partnerName {
            changes.append("names " + new.myName + " and " + new.partnerName)
        }
        if old.myShare != new.myShare {
            changes.append("my share " + Fmt.percent(old.myShare) + " → " + Fmt.percent(new.myShare))
        }
        if old.startDate.map({ DateMath.monthStart($0) }) != new.startDate.map({ DateMath.monthStart($0) }) {
            changes.append("starts " + (new.startDate.map { Fmt.month($0) } ?? "from the first record"))
        }
        if old.openingBalance != new.openingBalance {
            changes.append("opening balance " + Fmt.inr(old.openingBalance) + " → " + Fmt.inr(new.openingBalance))
        }
        var settings = new
        settings.myName = settings.myName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.partnerName = settings.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.myName.isEmpty { settings.myName = "Me" }
        if settings.partnerName.isEmpty { settings.partnerName = "Brother" }
        settings.myShare = min(max(settings.myShare.isFinite ? settings.myShare : 50, 0), 100)
        settings.startDate = settings.startDate.map { DateMath.monthStart($0) }
        let finished = settings
        change("Partnership settings changed", details: changes.isEmpty ? "No changes" : changes.joined(separator: ", ")) { d in
            d.partnership.settings = finished
        }
    }

    func partnerSource(_ id: UUID?) -> PartnerSource? {
        guard let id = id else { return nil }
        return data.partnership.sources.first { $0.id == id }
    }

    func saveSource(_ s: PartnerSource, isNew: Bool) {
        let who = Partnership.name(s.collectedBy, partnerSettings)
        let details = s.name + " · " + Fmt.inr(s.monthlyRent) + " a month · collected by " + who
        change(isNew ? "Partnership tenant added" : "Partnership tenant updated", details: details) { d in
            if let i = d.partnership.sources.firstIndex(where: { $0.id == s.id }) {
                d.partnership.sources[i] = s
            } else {
                d.partnership.sources.append(s)
            }
        }
    }

    func setSourceActive(_ id: UUID, _ active: Bool) {
        guard let s = partnerSource(id) else { return }
        change(active ? "Partnership tenant restarted" : "Partnership tenant stopped", details: s.name) { d in
            if let i = d.partnership.sources.firstIndex(where: { $0.id == id }) {
                d.partnership.sources[i].isActive = active
            }
        }
    }

    /// Whether any rent has been recorded for a fixed tenant (then it can only be stopped).
    func sourceHasRecords(_ id: UUID) -> Bool {
        data.partnership.entries.contains { $0.sourceID == id }
    }

    func deleteSource(_ id: UUID) {
        guard let s = partnerSource(id) else { return }
        if sourceHasRecords(id) {
            setSourceActive(id, false)
            return
        }
        change("Partnership tenant removed", details: s.name) { d in
            d.partnership.sources.removeAll { $0.id == id }
        }
    }

    /// "Gupta Traders, Oct 2026: ₹18,000 collected by Brother", for screens and the change history.
    func entryText(_ e: PartnerEntry) -> String {
        let settings = partnerSettings
        let who = Partnership.name(e.party, settings)
        let other = settings.partnerName
        let amount = Fmt.inr(e.amount)
        switch e.kind {
        case .rent:
            let head = Partnership.sourceName(e, data.partnership) + ", " + Partnership.monthLabel(Partnership.monthKey(of: e)) + ": " + amount
            return head + L(" collected by " + who, ", liya: " + who)
        case .transfer:
            if e.party == .me {
                return L("Paid to " + other + " " + amount + " on " + Fmt.date(e.date), other + " ko " + amount + " diye, " + Fmt.date(e.date))
            }
            return L("Received from " + other + " " + amount + " on " + Fmt.date(e.date), other + " se " + amount + " mile, " + Fmt.date(e.date))
        case .adjustment:
            return L("Correction of " + amount + " in favour of " + who, "Sudhaar " + amount + ", " + who + " ke haq mein")
        }
    }

    func addPartnerEntries(_ entries: [PartnerEntry]) {
        let list = entries.filter { $0.amount > 0 }
        guard let first = list.first else { return }
        let action: String
        switch first.kind {
        case .rent: action = "Partnership rent recorded"
        case .transfer: action = "Partnership payment recorded"
        case .adjustment: action = "Partnership balance corrected"
        }
        let details = list.map { entryText($0) }.joined(separator: "; ")
        let now = Date()
        change(action, details: details) { d in
            for var e in list {
                e.createdAt = now
                e.date = DateMath.day(e.date)
                if e.month.isEmpty || Partnership.monthDate(e.month) == nil {
                    e.month = DateMath.monthKey(e.date)
                }
                d.partnership.entries.append(e)
            }
        }
    }

    /// Voided entries stay in the history, crossed out, and no longer count.
    func voidPartnerEntry(_ id: UUID, reason: String) {
        guard let e = data.partnership.entries.first(where: { $0.id == id }), !e.isVoided else { return }
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        change("Partnership entry voided", details: entryText(e) + (why.isEmpty ? "" : " (" + why + ")")) { d in
            if let i = d.partnership.entries.firstIndex(where: { $0.id == id }) {
                d.partnership.entries[i].isVoided = true
                d.partnership.entries[i].voidReason = why
            }
        }
    }

    /// Replaces an entry: the original is voided and kept, and the new one points back to it.
    func correctPartnerEntry(_ id: UUID, with replacement: PartnerEntry, reason: String) {
        guard let old = data.partnership.entries.first(where: { $0.id == id }), !old.isVoided else { return }
        var fresh = replacement
        fresh.id = UUID()
        fresh.correctionOf = id
        fresh.isVoided = false
        fresh.voidReason = ""
        fresh.createdAt = Date()
        fresh.date = DateMath.day(fresh.date)
        if fresh.month.isEmpty || Partnership.monthDate(fresh.month) == nil {
            fresh.month = DateMath.monthKey(fresh.date)
        }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = trimmed.isEmpty ? "Corrected" : trimmed
        let finished = fresh
        change("Partnership entry corrected", details: entryText(old) + " → " + entryText(finished) + " (" + why + ")") { d in
            if let i = d.partnership.entries.firstIndex(where: { $0.id == id }) {
                d.partnership.entries[i].isVoided = true
                d.partnership.entries[i].voidReason = why
            }
            d.partnership.entries.append(finished)
        }
    }

    func partnerEntry(_ id: UUID?) -> PartnerEntry? {
        guard let id = id else { return nil }
        return data.partnership.entries.first { $0.id == id }
    }

    // MARK: Allocation rules

    func ruleText(_ r: AllocationRule) -> String {
        var parts: [String] = []
        if let p = property(r.propertyID) { parts.append(p.name) }
        if let c = r.category { parts.append(c.label) }
        if parts.isEmpty { parts.append(L("All expenses", "Saare kharche")) }
        parts.append(Partnership.splitText(r.split, settings: partnerSettings))
        if let who = r.paidBy { parts.append(L("paid by ", "dene wala: ") + Partnership.name(who, partnerSettings)) }
        return parts.joined(separator: " · ")
    }

    func saveRule(_ r: AllocationRule, isNew: Bool) {
        change(isNew ? "Sharing rule added" : "Sharing rule updated", details: (r.name.isEmpty ? "" : r.name + ": ") + ruleText(r)) { d in
            if let i = d.partnership.rules.firstIndex(where: { $0.id == r.id }) {
                d.partnership.rules[i] = r
            } else {
                d.partnership.rules.append(r)
            }
        }
    }

    func deleteRule(_ id: UUID) {
        guard let r = data.partnership.rules.first(where: { $0.id == id }) else { return }
        change("Sharing rule removed", details: (r.name.isEmpty ? "" : r.name + ": ") + ruleText(r)) { d in
            d.partnership.rules.removeAll { $0.id == id }
        }
    }

    /// The saved rule that fits an expense, if the partnership is on.
    func suggestedRule(propertyID: UUID?, category: ExpenseCategory) -> AllocationRule? {
        guard partnerSettings.enabled else { return nil }
        return Partnership.rule(propertyID: propertyID, category: category, rules: data.partnership.rules)
    }

    // MARK: - Recurring expenses

    var pendingRecurring: [PendingExpense] {
        Partnership.pendingRecurring(data, asOf: Date())
    }

    func recurring(_ id: UUID) -> RecurringExpense? {
        data.recurringExpenses.first { $0.id == id }
    }

    func saveRecurring(_ r: RecurringExpense, isNew: Bool) {
        let details = (r.title.isEmpty ? r.category.label : r.title) + " · " + Fmt.inr(r.amount) + " on day \(r.dayOfMonth)"
        var template = r
        template.startDate = DateMath.day(template.startDate)
        template.endDate = template.endDate.map { DateMath.day($0) }
        template.dayOfMonth = min(max(template.dayOfMonth, 1), 31)
        let finished = template
        change(isNew ? "Recurring expense added" : "Recurring expense updated", details: details, property: r.propertyID) { d in
            if let i = d.recurringExpenses.firstIndex(where: { $0.id == finished.id }) {
                d.recurringExpenses[i] = finished
            } else {
                d.recurringExpenses.append(finished)
            }
        }
    }

    func setRecurringActive(_ id: UUID, _ active: Bool) {
        guard let r = recurring(id) else { return }
        change(active ? "Recurring expense restarted" : "Recurring expense paused", details: r.title.isEmpty ? r.category.label : r.title) { d in
            if let i = d.recurringExpenses.firstIndex(where: { $0.id == id }) {
                d.recurringExpenses[i].isActive = active
            }
        }
    }

    /// Removes the schedule. Expenses already saved from it stay.
    func deleteRecurring(_ id: UUID) {
        guard let r = recurring(id) else { return }
        change("Recurring expense removed", details: r.title.isEmpty ? r.category.label : r.title) { d in
            d.recurringExpenses.removeAll { $0.id == id }
        }
    }

    /// Saves reviewed entries as expenses, each with the amount and date chosen.
    func savePending(_ items: [(pending: PendingExpense, amount: Int, date: Date)]) {
        let list = items.filter { $0.amount > 0 }
        guard !list.isEmpty else { return }
        let expenses = list.map { Partnership.makeExpense($0.pending, amount: $0.amount, date: $0.date) }
        let details = expenses.map { ($0.title.isEmpty ? $0.category.label : $0.title) + " " + Fmt.inr($0.amount) + " (" + Fmt.date($0.date) + ")" }
            .joined(separator: "; ")
        change("Recurring expenses saved", details: details) { d in
            for e in expenses {
                let key = (e.recurringID?.uuidString ?? "") + "-" + (e.recurringMonth ?? "")
                let exists = d.expenses.contains { ($0.recurringID?.uuidString ?? "") + "-" + ($0.recurringMonth ?? "") == key }
                if !exists {
                    d.expenses.append(e)
                }
            }
        }
    }

    func skipPending(_ p: PendingExpense) {
        let title = p.template.title.isEmpty ? p.template.category.label : p.template.title
        change("Recurring expense skipped", details: title + " for " + Partnership.monthLabel(p.month)) { d in
            if let i = d.recurringExpenses.firstIndex(where: { $0.id == p.template.id }),
               !d.recurringExpenses[i].skippedMonths.contains(p.month) {
                d.recurringExpenses[i].skippedMonths.append(p.month)
            }
        }
    }

    // MARK: - Electricity and water

    /// The reading before a new one of the same meter, if any.
    func previousReading(_ kind: MeterKind, tenantID: UUID, before date: Date, excluding id: UUID? = nil) -> MeterReading? {
        guard let t = tenant(tenantID) else { return nil }
        let day = DateMath.day(date)
        return t.meterReadings
            .filter { $0.kind == kind && $0.id != id && DateMath.day($0.date) <= day }
            .max { $0.date < $1.date }
    }

    /// Adds a reading and, when asked, bills the units used since the last reading as an
    /// extra charge on the tenant's account, due on the day given.
    func addMeterReading(tenantID: UUID, reading: MeterReading, bill: Bool, dueDate: Date) {
        guard let t = tenant(tenantID) else { return }
        var r = reading
        r.date = DateMath.day(r.date)
        var charge: Adjustment? = nil
        if bill, let previous = previousReading(r.kind, tenantID: tenantID, before: r.date) {
            let units = max(0, r.reading - previous.reading)
            let amount = Utilities.bill(units: units, rate: r.rate)
            if amount > 0 {
                var a = Adjustment()
                a.kind = .extraCharge
                a.date = DateMath.day(dueDate)
                a.amount = amount
                a.title = Utilities.chargeTitle(r.kind, from: previous.reading, to: r.reading, rate: r.rate)
                a.reason = "Meter reading on " + Fmt.date(r.date)
                r.chargeID = a.id
                r.billedAmount = amount
                charge = a
            }
        }
        var details = t.name + ": " + r.kind.label + " " + Fmt.number(r.reading) + " on " + Fmt.date(r.date)
        if let a = charge { details += ", billed " + Fmt.inr(a.amount) }
        let finished = r
        updateTenant(tenantID, log: "Meter reading added", details: details) { tenant in
            tenant.meterReadings.append(finished)
            if let a = charge {
                tenant.adjustments.append(a)
            }
        }
    }

    /// Removes a reading. A bill made from it is reversed, and stays in the history.
    func deleteMeterReading(tenantID: UUID, readingID: UUID) {
        guard let t = tenant(tenantID), let r = t.meterReadings.first(where: { $0.id == readingID }) else { return }
        var details = t.name + ": " + r.kind.label + " " + Fmt.number(r.reading) + " on " + Fmt.date(r.date)
        if r.billedAmount > 0 { details += ", bill of " + Fmt.inr(r.billedAmount) + " reversed" }
        updateTenant(tenantID, log: "Meter reading removed", details: details) { tenant in
            tenant.meterReadings.removeAll { $0.id == readingID }
            if let chargeID = r.chargeID, let i = tenant.adjustments.firstIndex(where: { $0.id == chargeID }) {
                tenant.adjustments[i].isReversed = true
                tenant.adjustments[i].reason += (tenant.adjustments[i].reason.isEmpty ? "" : " · ") + "Reading removed"
            }
        }
    }

    func setUtilityRates(tenantID: UUID, electricity: Double?, water: Double?) {
        guard let t = tenant(tenantID) else { return }
        let text = "electricity " + (electricity.map { "₹" + Fmt.number($0) } ?? "default") + ", water "
            + (water.map { "₹" + Fmt.number($0) } ?? "default")
        updateTenant(tenantID, log: "Utility rates changed", details: t.name + ": " + text) { tenant in
            tenant.electricityRate = electricity
            tenant.waterRate = water
        }
    }

    // MARK: - Handovers

    /// Saves a move-in or move-out handover. Its meter readings are added to the tenant's
    /// readings (without a bill) unless that meter already has a reading on that day.
    func saveHandover(_ h: Handover, tenantID: UUID) {
        guard let t = tenant(tenantID) else { return }
        var handover = h
        handover.date = DateMath.day(handover.date)
        handover.keys = handover.keys.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.count > 0 }
        let isNew = !t.handovers.contains { $0.id == h.id }
        let finished = handover
        updateTenant(tenantID, log: isNew ? "Handover recorded" : "Handover updated",
                     details: t.name + ": " + finished.kind.label + " on " + Fmt.date(finished.date)) { tenant in
            if let i = tenant.handovers.firstIndex(where: { $0.id == finished.id }) {
                tenant.handovers[i] = finished
            } else {
                tenant.handovers.append(finished)
            }
            Store.addHandoverReadings(finished, to: &tenant)
        }
    }

    static func addHandoverReadings(_ h: Handover, to tenant: inout Tenant) {
        let pairs: [(MeterKind, Double?)] = [(.electricity, h.electricityReading), (.water, h.waterReading)]
        for (kind, value) in pairs {
            guard let value = value, value.isFinite, value >= 0 else { continue }
            let day = DateMath.day(h.date)
            let exists = tenant.meterReadings.contains { $0.kind == kind && DateMath.day($0.date) == day }
            if !exists {
                tenant.meterReadings.append(MeterReading(kind: kind, date: day, reading: value, note: h.kind.label))
            }
        }
    }

    func handover(_ kind: HandoverKind, of t: Tenant) -> Handover? {
        t.handovers.filter { $0.kind == kind }.max { $0.date < $1.date }
    }

    // MARK: - Rent records worksheets

    func rentSheet(_ id: UUID) -> RentSheet? {
        data.rentSheets.first { $0.id == id }
    }

    func saveRentSheet(_ sheet: RentSheet, isNew: Bool) {
        var s = sheet
        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.name.isEmpty { s.name = L("Rent records", "Rent records") }
        let finished = s
        change(isNew ? "Worksheet added" : "Worksheet renamed", details: finished.name) { d in
            if let i = d.rentSheets.firstIndex(where: { $0.id == finished.id }) {
                d.rentSheets[i].name = finished.name
            } else {
                d.rentSheets.append(finished)
            }
        }
    }

    func saveSheetRow(_ row: RentSheetRow, sheetID: UUID) {
        guard let sheet = rentSheet(sheetID) else { return }
        let isNew = !sheet.rows.contains { $0.id == row.id }
        let details = sheet.name + ": " + (row.tenantName.isEmpty ? "row" : row.tenantName) + " · rent " + Fmt.inr(row.currentRent > 0 ? row.currentRent : row.rent)
        change(isNew ? "Worksheet row added" : "Worksheet row updated", details: details) { d in
            guard let i = d.rentSheets.firstIndex(where: { $0.id == sheetID }) else { return }
            if let j = d.rentSheets[i].rows.firstIndex(where: { $0.id == row.id }) {
                d.rentSheets[i].rows[j] = row
            } else {
                d.rentSheets[i].rows.append(row)
            }
        }
    }

    func addSheetRows(_ rows: [RentSheetRow], sheetID: UUID) {
        guard !rows.isEmpty, let sheet = rentSheet(sheetID) else { return }
        change("Worksheet rows added", details: sheet.name + ": " + rows.map { $0.tenantName }.joined(separator: ", ")) { d in
            guard let i = d.rentSheets.firstIndex(where: { $0.id == sheetID }) else { return }
            d.rentSheets[i].rows += rows
        }
    }

    func deleteSheetRow(_ rowID: UUID, sheetID: UUID) {
        guard let sheet = rentSheet(sheetID), let row = sheet.rows.first(where: { $0.id == rowID }) else { return }
        change("Worksheet row removed", details: sheet.name + ": " + (row.tenantName.isEmpty ? "row" : row.tenantName)) { d in
            guard let i = d.rentSheets.firstIndex(where: { $0.id == sheetID }) else { return }
            d.rentSheets[i].rows.removeAll { $0.id == rowID }
        }
    }

    func moveSheetRows(sheetID: UUID, from: IndexSet, to: Int) {
        change { d in
            guard let i = d.rentSheets.firstIndex(where: { $0.id == sheetID }) else { return }
            d.rentSheets[i].rows.move(fromOffsets: from, toOffset: to)
        }
    }

    @discardableResult
    func duplicateRentSheet(_ id: UUID) -> UUID? {
        guard let sheet = rentSheet(id) else { return nil }
        var copy = sheet
        copy.id = UUID()
        copy.name = sheet.name + L(" (copy)", " (copy)")
        copy.createdAt = Date()
        copy.rows = sheet.rows.map { row in
            var r = row
            r.id = UUID()
            return r
        }
        let finished = copy
        change("Worksheet copied", details: sheet.name + " → " + finished.name) { d in
            d.rentSheets.append(finished)
        }
        return finished.id
    }

    func deleteRentSheet(_ id: UUID) {
        guard let sheet = rentSheet(id) else { return }
        change("Worksheet deleted", details: sheet.name + " (\(sheet.rows.count) rows)") { d in
            d.rentSheets.removeAll { $0.id == id }
        }
    }

    // MARK: - Files for sharing

    func writeTemporary(data raw: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(PDFMaker.safeName(name))
        do {
            try raw.write(to: url, options: .atomic)
            return url
        } catch {
            saveError = L("Couldn't create the file: ", "File nahi ban payi: ") + error.localizedDescription
            return nil
        }
    }

    /// An Excel file with one sheet per table.
    func excelFile(_ tables: [ReportTable], named name: String) -> URL? {
        writeTemporary(data: Excel.workbook(tables.map { Excel.sheet($0) }), named: name + ".xlsx")
    }

    func excelFile(sheets: [XLSXSheet], named name: String) -> URL? {
        writeTemporary(data: Excel.workbook(sheets), named: name + ".xlsx")
    }
}
