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
            Text("This tenant was removed.")
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
        .navigationTitle("Rent increases")
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
        .confirmationDialog("Remove this rent change?", isPresented: removalBinding, titleVisibility: .visible) {
            Button("Remove rent change", role: .destructive) {
                if let change = pendingRemoval {
                    remove(change, t)
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Rent from that date goes back to the earlier amount, and the months already billed are worked out again. The increase schedule is not changed.")
        }
    }

    private func currentSection(_ t: Tenant, _ proposal: IncreaseProposal?, hasChanges: Bool) -> some View {
        Section {
            LabeledContent("Rent now", value: Fmt.inr(Ledger.currentRent(of: t)))
            if let p = proposal {
                proposalRow(p)
                Button {
                    sheet = .review
                } label: {
                    Label(p.isDue ? "Review and approve" : "Review now", systemImage: "checkmark.seal")
                }
            }
            Button {
                sheet = .manual
            } label: {
                Label("Change the rent by hand", systemImage: "pencil")
            }
            if proposal != nil || hasChanges {
                Button {
                    sheet = .notice
                } label: {
                    Label("Send increase notice on WhatsApp", systemImage: "message")
                }
            }
        } footer: {
            Text("Increases are never applied by themselves. You approve, change, skip or postpone each one.")
        }
    }

    private func proposalRow(_ p: IncreaseProposal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.isDue ? "Increase waiting for your approval" : "Next scheduled increase")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Fmt.inr(p.from) + " → " + Fmt.inr(p.to))
                .font(.title2.weight(.bold))
            Text("From " + Fmt.date(p.date) + " · " + Fmt.inr(p.difference) + " more a month")
                .font(.caption)
                .foregroundStyle(p.isDue ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    private func scheduleSection(_ t: Tenant) -> some View {
        Section {
            if let rule = t.escalation {
                LabeledContent("Increase by", value: IncreaseText.rule(rule))
                LabeledContent("Next increase", value: Fmt.date(rule.nextDate))
                if !rule.clause.isEmpty {
                    LabeledContent("Agreement clause", value: rule.clause)
                }
                Button {
                    sheet = .rule
                } label: {
                    Label("Change the schedule", systemImage: "calendar")
                }
            } else {
                Text("No increases scheduled.")
                    .foregroundStyle(.secondary)
                Button {
                    sheet = .rule
                } label: {
                    Label("Schedule rent increases", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("RentBook reminds you before each increase is due.")
        }
    }

    private func historySection(_ t: Tenant, _ history: [RentChange]) -> some View {
        let first = t.rentHistory.min { $0.effectiveDate < $1.effectiveDate }?.id
        return Section {
            if history.isEmpty {
                Text("No rent set yet. Edit the tenant to add it.")
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
                            Label("Remove", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            Text("Rent history")
        } footer: {
            Text("Each month is billed at the rent in force on its due date. Swipe left to remove a change entered by mistake.")
        }
    }

    @ViewBuilder
    private func eventsSection(_ t: Tenant) -> some View {
        let events = t.escalationEvents.sorted { $0.recordedAt > $1.recordedAt }
        if !events.isEmpty {
            Section("Decisions") {
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
        let months = rule.everyMonths == 1 ? "every month" : "every \(rule.everyMonths) months"
        return amount + " " + months
    }

    static func eventTitle(_ e: EscalationEvent) -> String {
        switch e.kind {
        case .applied: return "Approved: " + Fmt.inr(e.fromAmount) + " → " + Fmt.inr(e.toAmount)
        case .skipped: return "Skipped"
        case .postponed: return "Postponed" + (e.effectiveDate.map { " to " + Fmt.date($0) } ?? "")
        case .cancelled: return "Schedule stopped"
        }
    }

    static func eventDetail(_ e: EscalationEvent) -> String {
        var parts: [String] = ["Recorded " + Fmt.date(e.recordedAt)]
        if e.kind == .applied, let d = e.effectiveDate {
            parts.append("rent from " + Fmt.date(d))
        }
        if e.kind != .applied, let s = e.scheduledDate {
            parts.append("was due " + Fmt.date(s))
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

    private var screenTitle: String { manual ? "Change rent" : "Review increase" }
    private var saveTitle: String { manual ? "Save" : "Approve" }

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
            .confirmationDialog("Skip this increase?", isPresented: $askSkip, titleVisibility: .visible) {
                Button("Skip increase", role: .destructive) { skip() }
            } message: {
                Text("The rent stays the same and the following increase is scheduled as usual.")
            }
        }
    }

    private func infoSection(_ t: Tenant, _ proposal: IncreaseProposal?) -> some View {
        Section {
            LabeledContent("Rent now", value: Fmt.inr(Ledger.currentRent(of: t)))
            if let p = proposal {
                LabeledContent("Suggested by the schedule", value: Fmt.inr(p.to))
                LabeledContent("Scheduled for", value: Fmt.date(p.date))
                if let rule = t.escalation {
                    LabeledContent("Rule", value: IncreaseText.rule(rule))
                }
            }
        }
    }

    private func changeSection(_ t: Tenant) -> some View {
        Section {
            MoneyField(title: "New monthly rent", text: $rentText)
            DatePicker("Starts from", selection: $effective, displayedComponents: .date)
            TextField("Reason", text: $reason)
            if manual && t.escalation != nil {
                Toggle("Count the next scheduled increase from this date", isOn: $restartSchedule)
            }
        } header: {
            Text(manual ? "New rent" : "Approve, or change the amount")
        } footer: {
            Text(changeSummary(t))
        }
    }

    private var decisionSection: some View {
        Section {
            TextField("Note (optional)", text: $decisionNote)
            Button("Skip this increase") { askSkip = true }
            Toggle("Postpone to a later date", isOn: $showPostpone)
            if showPostpone {
                DatePicker("New date", selection: $postponeDate, displayedComponents: .date)
                Button("Postpone to " + Fmt.date(postponeDate)) { postpone() }
            }
        } header: {
            Text("Or decide not to increase now")
        } footer: {
            Text("Skipping moves the schedule on to the following increase. Postponing keeps this increase for a later date.")
        }
    }

    private func changeSummary(_ t: Tenant) -> String {
        guard let newRent = parseAmount(rentText), newRent > 0 else { return "Enter the new monthly rent." }
        let old = Ledger.rent(of: t, on: DateMath.addDays(-1, to: DateMath.day(effective)))
        let diff = newRent - old
        let sign = diff >= 0 ? "+" : "-"
        var text = Fmt.inr(old) + " → " + Fmt.inr(newRent) + " (" + sign + Fmt.inr(abs(diff)) + " a month)"
        if old > 0 && diff != 0 {
            text += ", " + Fmt.percent(Double(diff) * 100 / Double(old))
        }
        text += ". Rent due from " + Fmt.date(effective) + " uses the new amount; earlier months keep the old rent."
        // Warn when the date is in the past, so months already billed change too.
        var copy = t
        RentChanges.apply(&copy, newRent: newRent, effective: effective, reason: "", scheduledFor: nil)
        let grace = store.settings.gracePeriodDays
        let extra = Ledger.ledger(for: copy, graceDays: grace).totalBilled - Ledger.ledger(for: t, graceDays: grace).totalBilled
        if extra > 0 {
            text += " Months already due change too: " + Fmt.inr(extra) + " more becomes owed for them."
        } else if extra < 0 {
            text += " Months already due change too: " + Fmt.inr(-extra) + " less is owed for them."
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
        store.updateTenant(tenantID, log: "Rent increase postponed", details: t.name + " to " + Fmt.date(day)) { tenant in
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
    private var valueLabel: String { mode == .percent ? "Percentage" : "Amount (₹)" }
    private var everyText: String { everyMonths == 1 ? "Every month" : "Every \(everyMonths) months" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Increase by", selection: $mode) {
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
                    DatePicker("Next increase on", selection: $nextDate, displayedComponents: .date)
                    TextField("Clause from the agreement (optional)", text: $clause, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text(previewText)
                }
                if hasRule {
                    Section {
                        Button(role: .destructive) {
                            askStop = true
                        } label: {
                            Label("Stop scheduled increases", systemImage: "stop.circle")
                        }
                    }
                }
            }
            .navigationTitle("Increase schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((parseDecimal(valueText) ?? 0) <= 0)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .confirmationDialog("Stop scheduled increases?", isPresented: $askStop, titleVisibility: .visible) {
                Button("Stop increases", role: .destructive) { stop() }
            } message: {
                Text("The current rent stays. You can set up a new schedule at any time.")
            }
        }
    }

    private var previewText: String {
        guard let t = store.tenant(tenantID), let value = parseDecimal(valueText), value > 0 else {
            return "Enter how much the rent goes up each time."
        }
        let from = Ledger.rent(of: t, on: DateMath.addDays(-1, to: DateMath.day(nextDate)))
        let to = Escalation.proposedAmount(from: from, mode: mode, value: value)
        return "Next: " + Fmt.inr(from) + " → " + Fmt.inr(to) + " from " + Fmt.date(nextDate) + ". You approve each increase before it counts."
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
