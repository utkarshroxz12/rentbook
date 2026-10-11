//  IncreaseViews.swift
//  Rent increases: the schedule, reviewing and approving each increase,
//  skipping or postponing it, and changing the rent by hand.

import SwiftUI

enum IncreaseSheet: Identifiable {
    case review
    case manual
    case rule
    case notice

    var id: Int {
        switch self {
        case .review: return 0
        case .manual: return 1
        case .rule: return 2
        case .notice: return 3
        }
    }
}

enum RentChanges {
    /// Records a new rent from a date. A change already on that same day is replaced,
    /// so the rent on any day is never ambiguous.
    static func apply(_ t: inout Tenant, newRent: Int, effective: Date, reason: String, scheduledFor: Date?) {
        let day = DateMath.day(effective)
        let sameDay = t.rentHistory.filter { DateMath.day($0.effectiveDate) == day }.map { $0.id }
        t.rentHistory.removeAll { sameDay.contains($0.id) }
        Escalation.apply(to: &t, newRent: newRent, effective: day, reason: reason, scheduledFor: scheduledFor)
    }
}

struct IncreasesView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID
    @State private var sheet: IncreaseSheet? = nil
    @State private var pendingRemoval: RentChange? = nil

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func content(_ t: Tenant) -> some View {
        let proposal = Escalation.next(for: t)
        let history = t.rentHistory.sorted { $0.effectiveDate > $1.effectiveDate }
        return List {
            currentSection(t, proposal, hasChanges: history.count > 1)
            scheduleSection(t)
            historySection(t, history)
            eventsSection(t)
        }
        .navigationTitle(L("Rent increases", "Rent badhotri"))
        .sheet(item: $sheet) { which in
            switch which {
            case .review:
                IncreaseReviewView(tenantID: tenantID, manual: false).environmentObject(store)
            case .manual:
                IncreaseReviewView(tenantID: tenantID, manual: true).environmentObject(store)
            case .rule:
                EscalationRuleForm(tenantID: tenantID).environmentObject(store)
            case .notice:
                MessageComposerView(tenantID: tenantID, kind: .increaseNotice).environmentObject(store)
            }
        }
        .confirmationDialog(L("Remove this rent change?", "Yeh rent badlav hatayein?"), isPresented: removalBinding, titleVisibility: .visible) {
            Button(L("Remove rent change", "Rent badlav hatayein"), role: .destructive) {
                if let change = pendingRemoval {
                    remove(change, t)
                }
                pendingRemoval = nil
            }
        } message: {
            Text(L("Rent from that date goes back to the earlier amount, and the months already billed are worked out again. The increase schedule is not changed.", "Us tareekh se rent pehle wale amount par aa jayega, aur bane hue mahine dobara gine jayenge. Badhotri ka schedule nahi badlega."))
        }
    }

    private func currentSection(_ t: Tenant, _ proposal: IncreaseProposal?, hasChanges: Bool) -> some View {
        Section {
            LabeledContent(L("Rent now", "Abhi ka rent"), value: Fmt.inr(Ledger.currentRent(of: t)))
            if let p = proposal {
                proposalRow(p)
                Button {
                    sheet = .review
                } label: {
                    Label(p.isDue ? L("Review and approve", "Review karke approve karein") : L("Review now", "Abhi review karein"), systemImage: "checkmark.seal")
                }
            }
            Button {
                sheet = .manual
            } label: {
                Label(L("Change the rent by hand", "Rent khud badlein"), systemImage: "pencil")
            }
            if proposal != nil || hasChanges {
                Button {
                    sheet = .notice
                } label: {
                    Label(L("Send increase notice on WhatsApp", "Badhotri ka notice WhatsApp par bhejein"), systemImage: "message")
                }
            }
        } footer: {
            Text(L("Increases are never applied by themselves. You approve, change, skip or postpone each one.", "Badhotri kabhi apne aap nahi lagti. Har ek ko aap approve, badal, chhod ya aage badha sakte hain."))
        }
    }

    private func proposalRow(_ p: IncreaseProposal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.isDue ? L("Increase waiting for your approval", "Badhotri aapke approval ka intezaar kar rahi hai") : L("Next scheduled increase", "Agli tay badhotri"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Fmt.inr(p.from) + " → " + Fmt.inr(p.to))
                .font(.title2.weight(.bold))
            Text(L("From " + Fmt.date(p.date) + " · " + Fmt.inr(p.difference) + " more a month",
                   Fmt.date(p.date) + " se · har mahine " + Fmt.inr(p.difference) + " zyada"))
                .font(.caption)
                .foregroundStyle(p.isDue ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    private func scheduleSection(_ t: Tenant) -> some View {
        Section {
            if let rule = t.escalation {
                LabeledContent(L("Increase by", "Kitni badhotri"), value: IncreaseText.rule(rule))
                LabeledContent(L("Next increase", "Agli badhotri"), value: Fmt.date(rule.nextDate))
                if !rule.clause.isEmpty {
                    LabeledContent(L("Agreement clause", "Agreement ki shart"), value: rule.clause)
                }
                Button {
                    sheet = .rule
                } label: {
                    Label(L("Change the schedule", "Schedule badlein"), systemImage: "calendar")
                }
            } else {
                Text(L("No increases scheduled.", "Koi badhotri tay nahi."))
                    .foregroundStyle(.secondary)
                Button {
                    sheet = .rule
                } label: {
                    Label(L("Schedule rent increases", "Rent badhotri tay karein"), systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text(L("Schedule", "Schedule"))
        } footer: {
            Text(L("RentBook reminds you before each increase is due.", "Har badhotri se pehle RentBook yaad dilayega."))
        }
    }

    private func historySection(_ t: Tenant, _ history: [RentChange]) -> some View {
        let first = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.id
        return Section {
            if history.isEmpty {
                Text(L("No rent set yet. Edit the tenant to add it.", "Abhi rent set nahi. Tenant badal kar rent jodein."))
                    .foregroundStyle(.secondary)
            }
            ForEach(history) { change in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From " + Fmt.date(change.effectiveDate))
                        if !change.reason.isEmpty {
                            Text(change.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Fmt.inr(change.amount))
                        .font(.subheadline.weight(.semibold))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if change.id != first {
                        Button {
                            pendingRemoval = change
                        } label: {
                            Label(L("Remove", "Hatayein"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            Text(L("Rent history", "Rent history"))
        } footer: {
            Text(L("Each month is billed at the rent in force on its due date. Swipe left to remove a change entered by mistake.", "Har mahine ka rent uski due date par lagu rent se banta hai. Galti se daala badlav hatane ke liye left swipe karein."))
        }
    }

    @ViewBuilder
    private func eventsSection(_ t: Tenant) -> some View {
        let events = t.escalationEvents.sorted { $0.recordedAt > $1.recordedAt }
        if !events.isEmpty {
            Section(L("Decisions", "Faisle")) {
                ForEach(events) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(IncreaseText.eventTitle(e))
                        Text(IncreaseText.eventDetail(e))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func remove(_ change: RentChange, _ t: Tenant) {
        let details = t.name + ": " + Fmt.inr(change.amount) + " from " + Fmt.date(change.effectiveDate)
        store.updateTenant(t.id, log: "Rent change removed", details: details) { tenant in
            tenant.rentHistory.removeAll { $0.id == change.id }
        }
    }
}

enum IncreaseText {
    static func rule(_ rule: EscalationRule) -> String {
        let amount = rule.mode == .percent ? Fmt.percent(rule.value) : Fmt.inr(wholeRupees(rule.value))
        let months = rule.everyMonths == 1 ? L("every month", "har mahine") : L("every \(rule.everyMonths) months", "har \(rule.everyMonths) mahine")
        return amount + " " + months
    }

    static func eventTitle(_ e: EscalationEvent) -> String {
        switch e.kind {
        case .applied: return L("Approved: ", "Approve kiya: ") + Fmt.inr(e.fromAmount) + " → " + Fmt.inr(e.toAmount)
        case .skipped: return L("Skipped", "Chhoda")
        case .postponed: return L("Postponed", "Aage badhaya") + (e.effectiveDate.map { L(" to ", ": ") + Fmt.date($0) } ?? "")
        case .cancelled: return L("Schedule stopped", "Schedule band")
        }
    }

    static func eventDetail(_ e: EscalationEvent) -> String {
        var parts: [String] = [L("Recorded ", "Record kiya ") + Fmt.date(e.recordedAt)]
        if e.kind == .applied, let d = e.effectiveDate {
            parts.append(L("rent from " + Fmt.date(d), Fmt.date(d) + " se rent"))
        }
        if e.kind != .applied, let s = e.scheduledDate {
            parts.append(L("was due ", "tareekh thi ") + Fmt.date(s))
        }
        if !e.note.isEmpty { parts.append(e.note) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Approve, change, skip or postpone

struct IncreaseReviewView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID
    let manual: Bool

    @State private var rentText = ""
    @State private var effective = Date()
    @State private var reason = ""
    @State private var restartSchedule = false
    @State private var decisionNote = ""
    @State private var showPostpone = false
    @State private var postponeDate = Date()
    @State private var askSkip = false
    @State private var prepared = false

    private var screenTitle: String { manual ? L("Change rent", "Rent badlein") : L("Review increase", "Badhotri review karein") }
    private var saveTitle: String { manual ? L("Save", "Save karein") : L("Approve", "Approve karein") }

    var body: some View {
        NavigationStack {
            Form {
                if let t = store.tenant(tenantID) {
                    let proposal = manual ? nil : Escalation.next(for: t)
                    infoSection(t, proposal)
                    changeSection(t)
                    if proposal != nil {
                        decisionSection
                    }
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) { apply() }
                        .disabled((parseAmount(rentText) ?? 0) <= 0)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .confirmationDialog(L("Skip this increase?", "Yeh badhotri chhodein?"), isPresented: $askSkip, titleVisibility: .visible) {
                Button(L("Skip increase", "Badhotri chhodein"), role: .destructive) { skip() }
            } message: {
                Text(L("The rent stays the same and the following increase is scheduled as usual.", "Rent wahi rahega aur agli badhotri hamesha ki tarah tay hogi."))
            }
        }
    }

    private func infoSection(_ t: Tenant, _ proposal: IncreaseProposal?) -> some View {
        Section {
            LabeledContent(L("Rent now", "Abhi ka rent"), value: Fmt.inr(Ledger.currentRent(of: t)))
            if let p = proposal {
                LabeledContent(L("Suggested by the schedule", "Schedule ka sujhav"), value: Fmt.inr(p.to))
                LabeledContent(L("Scheduled for", "Tay tareekh"), value: Fmt.date(p.date))
                if let rule = t.escalation {
                    LabeledContent(L("Rule", "Rule"), value: IncreaseText.rule(rule))
                }
            }
        }
    }

    private func changeSection(_ t: Tenant) -> some View {
        Section {
            MoneyField(title: L("New monthly rent", "Naya mahine ka rent"), text: $rentText)
            DatePicker(L("Starts from", "Kab se"), selection: $effective, displayedComponents: .date)
            TextField(L("Reason", "Kaaran"), text: $reason)
            if manual && t.escalation != nil {
                Toggle(L("Count the next scheduled increase from this date", "Agli badhotri is tareekh se ginein"), isOn: $restartSchedule)
            }
        } header: {
            Text(manual ? L("New rent", "Naya rent") : L("Approve, or change the amount", "Approve karein, ya amount badlein"))
        } footer: {
            Text(changeSummary(t))
        }
    }

    private var decisionSection: some View {
        Section {
            TextField(L("Note (optional)", "Note (optional)"), text: $decisionNote)
            Button(L("Skip this increase", "Yeh badhotri chhodein")) { askSkip = true }
            Toggle(L("Postpone to a later date", "Baad ki tareekh tak aage badhayein"), isOn: $showPostpone)
            if showPostpone {
                DatePicker(L("New date", "Nayi tareekh"), selection: $postponeDate, displayedComponents: .date)
                Button(L("Postpone to " + Fmt.date(postponeDate), Fmt.date(postponeDate) + " tak aage badhayein")) { postpone() }
            }
        } header: {
            Text(L("Or decide not to increase now", "Ya abhi na badhane ka faisla karein"))
        } footer: {
            Text(L("Skipping moves the schedule on to the following increase. Postponing keeps this increase for a later date.", "Chhodne se schedule agli badhotri par chala jata hai. Aage badhane se yahi badhotri baad ki tareekh par hoti hai."))
        }
    }

    private func changeSummary(_ t: Tenant) -> String {
        guard let newRent = parseAmount(rentText), newRent > 0 else { return L("Enter the new monthly rent.", "Naya mahine ka rent daalein.") }
        let old = Ledger.rent(of: t, on: DateMath.addDays(-1, to: DateMath.day(effective)))
        let diff = newRent - old
        let sign = diff >= 0 ? "+" : "-"
        var text = Fmt.inr(old) + " → " + Fmt.inr(newRent) + " (" + sign + Fmt.inr(abs(diff)) + L(" a month)", " har mahine)")
        if old > 0 && diff != 0 {
            text += ", " + Fmt.percent(Double(diff) * 100 / Double(old))
        }
        text += L(". Rent due from " + Fmt.date(effective) + " uses the new amount; earlier months keep the old rent.",
                  ". " + Fmt.date(effective) + " se naya amount lagega; pehle ke mahine purane rent par rahenge.")
        // Warn when the date is in the past, so months already billed change too.
        var copy = t
        RentChanges.apply(&copy, newRent: newRent, effective: effective, reason: "", scheduledFor: nil)
        let grace = store.settings.gracePeriodDays
        let extra = Ledger.ledger(for: copy, graceDays: grace).totalBilled - Ledger.ledger(for: t, graceDays: grace).totalBilled
        if extra > 0 {
            text += L(" Months already due change too: " + Fmt.inr(extra) + " more becomes owed for them.",
                      " Jo mahine pehle se due hain woh bhi badlenge: unke liye " + Fmt.inr(extra) + " zyada baaki hoga.")
        } else if extra < 0 {
            text += L(" Months already due change too: " + Fmt.inr(-extra) + " less is owed for them.",
                      " Jo mahine pehle se due hain woh bhi badlenge: unke liye " + Fmt.inr(-extra) + " kam baaki hoga.")
        }
        return text
    }

    private func prepare() {
        guard !prepared, let t = store.tenant(tenantID) else { return }
        prepared = true
        if !manual, let p = Escalation.next(for: t) {
            rentText = String(p.to)
            effective = p.date
            let clause = t.escalation?.clause ?? ""
            reason = clause.isEmpty ? "Scheduled increase" : clause
            postponeDate = DateMath.addMonths(1, to: p.date)
        } else {
            let current = Ledger.currentRent(of: t)
            rentText = current > 0 ? String(current) : ""
            effective = DateMath.monthStart(DateMath.addMonths(1, to: Date()))
            reason = ""
            restartSchedule = false
        }
    }

    private func apply() {
        guard let newRent = parseAmount(rentText), newRent > 0, let t = store.tenant(tenantID) else { return }
        let proposal = manual ? nil : Escalation.next(for: t)
        let day = DateMath.day(effective)
        let typed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = typed.isEmpty ? (proposal == nil ? "Rent changed" : "Scheduled increase") : typed
        let keepSchedule = proposal == nil && !restartSchedule
        let old = Ledger.rent(of: t, on: DateMath.addDays(-1, to: day))
        let details = t.name + ": " + Fmt.inr(old) + " → " + Fmt.inr(newRent) + " from " + Fmt.date(day)
        store.updateTenant(tenantID, log: proposal == nil ? "Rent changed" : "Rent increase approved", details: details) { tenant in
            let nextBefore = tenant.escalation?.nextDate
            RentChanges.apply(&tenant, newRent: newRent, effective: day, reason: note, scheduledFor: proposal?.date)
            if keepSchedule, let keep = nextBefore {
                tenant.escalation?.nextDate = keep
            }
        }
        dismiss()
    }

    private func skip() {
        guard let t = store.tenant(tenantID) else { return }
        let note = decisionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTenant(tenantID, log: "Rent increase skipped", details: t.name + (note.isEmpty ? "" : ": " + note)) { tenant in
            Escalation.skip(&tenant, note: note)
        }
        dismiss()
    }

    private func postpone() {
        guard let t = store.tenant(tenantID) else { return }
        let day = DateMath.day(postponeDate)
        let note = decisionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTenant(tenantID, log: "Rent increase postponed", details: t.name + L(" to ", " – ") + Fmt.date(day)) { tenant in
            Escalation.postpone(&tenant, to: day, note: note)
        }
        dismiss()
    }
}

// MARK: - The increase schedule

struct EscalationRuleForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var mode: EscalationMode = .percent
    @State private var valueText = "5"
    @State private var everyMonths = 11
    @State private var nextDate = Date()
    @State private var clause = ""
    @State private var prepared = false
    @State private var askStop = false

    private var hasRule: Bool { store.tenant(tenantID)?.escalation != nil }
    private var valueLabel: String { mode == .percent ? L("Percentage", "Percent") : L("Amount (₹)", "Amount (₹)") }
    private var everyText: String { everyMonths == 1 ? L("Every month", "Har mahine") : L("Every \(everyMonths) months", "Har \(everyMonths) mahine") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Increase by", "Kitni badhotri"), selection: $mode) {
                        ForEach(EscalationMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(valueLabel)
                        Spacer()
                        TextField("5", text: $valueText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    Stepper(everyText, value: $everyMonths, in: 1...120)
                    DatePicker(L("Next increase on", "Agli badhotri ki tareekh"), selection: $nextDate, displayedComponents: .date)
                    TextField(L("Clause from the agreement (optional)", "Agreement ki shart (optional)"), text: $clause, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text(previewText)
                }
                if hasRule {
                    Section {
                        Button(role: .destructive) {
                            askStop = true
                        } label: {
                            Label(L("Stop scheduled increases", "Tay badhotri band karein"), systemImage: "stop.circle")
                        }
                    }
                }
            }
            .navigationTitle(L("Increase schedule", "Badhotri schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled((parseDecimal(valueText) ?? 0) <= 0)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .confirmationDialog(L("Stop scheduled increases?", "Tay badhotri band karein?"), isPresented: $askStop, titleVisibility: .visible) {
                Button(L("Stop increases", "Badhotri band karein"), role: .destructive) { stop() }
            } message: {
                Text(L("The current rent stays. You can set up a new schedule at any time.", "Abhi ka rent rahega. Naya schedule kabhi bhi bana sakte hain."))
            }
        }
    }

    private var previewText: String {
        guard let t = store.tenant(tenantID), let value = parseDecimal(valueText), value > 0 else {
            return L("Enter how much the rent goes up each time.", "Har baar rent kitna badhega, woh daalein.")
        }
        let from = Ledger.rent(of: t, on: DateMath.addDays(-1, to: DateMath.day(nextDate)))
        let to = Escalation.proposedAmount(from: from, mode: mode, value: value)
        return L("Next: " + Fmt.inr(from) + " → " + Fmt.inr(to) + " from " + Fmt.date(nextDate) + ". You approve each increase before it counts.",
                 "Agla: " + Fmt.inr(from) + " → " + Fmt.inr(to) + ", " + Fmt.date(nextDate) + " se. Har badhotri aapke approve karne par hi lagegi.")
    }

    private func prepare() {
        guard !prepared, let t = store.tenant(tenantID) else { return }
        prepared = true
        if let rule = t.escalation {
            mode = rule.mode
            valueText = Fmt.number(rule.value)
            everyMonths = max(1, rule.everyMonths)
            nextDate = rule.nextDate
            clause = rule.clause
            return
        }
        let s = store.settings
        mode = s.defaultEscalationMode
        valueText = Fmt.number(s.defaultEscalationValue)
        everyMonths = max(1, s.defaultEscalationMonths)
        let lastChange = t.rentHistory.map { $0.effectiveDate }.max()
        let base = lastChange ?? t.startDate ?? Date()
        nextDate = DateMath.addMonths(everyMonths, to: DateMath.day(base))
    }

    private func save() {
        guard let value = parseDecimal(valueText), value > 0, let t = store.tenant(tenantID) else { return }
        let rule = EscalationRule(mode: mode, value: value, everyMonths: everyMonths, nextDate: DateMath.day(nextDate),
                                  clause: clause.trimmingCharacters(in: .whitespacesAndNewlines))
        let details = t.name + ": " + IncreaseText.rule(rule) + ", next on " + Fmt.date(rule.nextDate)
        store.updateTenant(tenantID, log: t.escalation == nil ? "Increase schedule set" : "Increase schedule changed", details: details) { tenant in
            tenant.escalation = rule
        }
        dismiss()
    }

    private func stop() {
        guard let t = store.tenant(tenantID) else { return }
        store.updateTenant(tenantID, log: "Increase schedule stopped", details: t.name) { tenant in
            Escalation.cancelSchedule(&tenant, note: "Stopped by landlord")
        }
        dismiss()
    }
}
