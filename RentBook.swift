//  RentBook.swift
//  Personal tenant & rent tracker for iPhone (SwiftUI, iOS 16+).
//  The whole app is in this one file. All data stays on your iPhone.

import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Data

struct RentChange: Identifiable, Codable, Hashable {
    var id = UUID()
    var effectiveDate = Date()
    var amount = 0
}

struct Payment: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var amount = 0
    var method = "UPI"
    var note = ""
}

struct Tenant: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var phone = ""
    var unit = ""
    var startDate = Date()              // rent is counted from this date
    var dueDay = 5                      // day of the month rent is due (1-28)
    var deposit = 0
    var openingBalance = 0              // unpaid rent from before startDate
    var rentHistory: [RentChange] = []
    var payments: [Payment] = []
    var incrementPercent: Double = 5
    var incrementEveryMonths = 11
    var nextIncrementDate: Date? = nil
    var moveOutDate: Date? = nil
    var notes = ""
}

extension Tenant {
    var isActive: Bool { moveOutDate == nil }

    var safeDueDay: Int { min(max(dueDay, 1), 28) }

    var sortedRentHistory: [RentChange] {
        rentHistory.sorted { $0.effectiveDate < $1.effectiveDate }
    }

    /// Monthly rent that applies on a given day.
    func rent(on date: Date) -> Int {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let history = sortedRentHistory
        guard var amount = history.first?.amount else { return 0 }
        for change in history where cal.startOfDay(for: change.effectiveDate) <= day {
            amount = change.amount
        }
        return amount
    }

    var currentRent: Int { rent(on: Date()) }

    /// Every rent due date from the start date up to today (or the move-out date).
    func dueDates(upTo cutoff: Date = Date()) -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        var end = cal.startOfDay(for: cutoff)
        if let out = moveOutDate {
            end = min(end, cal.startOfDay(for: out))
        }
        var result: [Date] = []
        var monthStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        while result.count < 1200 {
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            comps.day = safeDueDay
            guard var due = cal.date(from: comps) else { break }
            if due < start { due = start }
            if due > end { break }
            result.append(due)
            guard let next = cal.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }
        return result
    }

    var totalBilled: Int { dueDates().reduce(0) { $0 + rent(on: $1) } }

    var totalPaid: Int { payments.reduce(0) { $0 + $1.amount } }

    /// Positive = rent pending, negative = paid in advance.
    var balance: Int { openingBalance + totalBilled - totalPaid }

    var nextDueDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.year, .month], from: today)
        comps.day = safeDueDay
        let thisMonth = cal.date(from: comps) ?? today
        if thisMonth >= today { return thisMonth }
        return cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
    }

    var isIncrementDue: Bool {
        guard isActive, let date = nextIncrementDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: date) <= cal.startOfDay(for: Date())
    }
}

// MARK: - Helpers

private let rupeeFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "en_IN")
    f.currencyCode = "INR"
    f.currencySymbol = "₹"
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()

func inr(_ amount: Int) -> String {
    rupeeFormatter.string(from: NSNumber(value: amount)) ?? "₹\(amount)"
}

func parseAmount(_ text: String) -> Int? {
    let digits = text.filter { $0.isASCII && $0.isNumber }
    return digits.isEmpty ? nil : Int(digits)
}

func parsePercent(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
}

func ordinal(_ n: Int) -> String {
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

func shortDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
}

/// Digits only, with India's country code added to 10-digit numbers.
func phoneDigits(_ phone: String) -> String {
    var digits = phone.filter { $0.isASCII && $0.isNumber }
    if digits.count == 11 && digits.hasPrefix("0") { digits.removeFirst() }
    if digits.count == 10 { digits = "91" + digits }
    return digits
}

func whatsappURL(for t: Tenant) -> URL? {
    let digits = phoneDigits(t.phone)
    guard digits.count >= 11 else { return nil }
    let message: String
    if t.balance > 0 {
        message = "Hello \(t.name), this is a gentle reminder that rent of \(inr(t.balance)) is pending. Kindly pay at the earliest. Thank you."
    } else {
        message = "Hello \(t.name), a reminder that your monthly rent of \(inr(t.currentRent)) is due on the \(ordinal(t.safeDueDay)). Thank you."
    }
    var comps = URLComponents()
    comps.scheme = "https"
    comps.host = "wa.me"
    comps.path = "/" + digits
    comps.queryItems = [URLQueryItem(name: "text", value: message)]
    return comps.url
}

func callURL(for t: Tenant) -> URL? {
    let digits = phoneDigits(t.phone)
    guard digits.count >= 10 else { return nil }
    return URL(string: "tel:+" + digits)
}

// MARK: - Storage

final class Store: ObservableObject {
    @Published var tenants: [Tenant] = [] {
        didSet { save() }
    }

    let backupURL: URL
    private let dataURL: URL

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dataURL = documents.appendingPathComponent("rentbook-data.json")
        backupURL = FileManager.default.temporaryDirectory.appendingPathComponent("RentBook-Backup.json")
        if let data = try? Data(contentsOf: dataURL),
           let saved = try? Store.decoder.decode([Tenant].self, from: data) {
            tenants = saved
        }
        save()
    }

    private func save() {
        guard let data = try? Store.encoder.encode(tenants) else { return }
        try? data.write(to: dataURL, options: .atomic)
        try? data.write(to: backupURL, options: .atomic)
        Reminders.schedule(for: tenants)
    }

    func tenant(_ id: UUID) -> Tenant? {
        tenants.first { $0.id == id }
    }

    func upsert(_ tenant: Tenant) {
        if let i = tenants.firstIndex(where: { $0.id == tenant.id }) {
            tenants[i] = tenant
        } else {
            tenants.append(tenant)
        }
    }

    func delete(_ id: UUID) {
        tenants.removeAll { $0.id == id }
    }

    func addPayment(_ payment: Payment, to id: UUID) {
        guard let i = tenants.firstIndex(where: { $0.id == id }) else { return }
        tenants[i].payments.append(payment)
    }

    func deletePayments(_ ids: [UUID], from id: UUID) {
        guard let i = tenants.firstIndex(where: { $0.id == id }) else { return }
        tenants[i].payments.removeAll { ids.contains($0.id) }
    }

    func deleteRentChanges(_ ids: [UUID], from id: UUID) {
        guard let i = tenants.firstIndex(where: { $0.id == id }) else { return }
        let remaining = tenants[i].rentHistory.filter { !ids.contains($0.id) }
        guard !remaining.isEmpty else { return }
        tenants[i].rentHistory = remaining
    }

    func applyIncrement(to id: UUID, newRent: Int, from date: Date, nextIncrement: Date?, percent: Double?) {
        guard let i = tenants.firstIndex(where: { $0.id == id }) else { return }
        var t = tenants[i]
        t.rentHistory.append(RentChange(effectiveDate: date, amount: newRent))
        t.nextIncrementDate = nextIncrement
        if let percent = percent { t.incrementPercent = percent }
        tenants[i] = t
    }

    func readBackup(at url: URL) throws -> [Tenant] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try Store.decoder.decode([Tenant].self, from: data)
    }

    func replaceAll(with list: [Tenant]) {
        tenants = list
    }
}

// MARK: - Reminders (local notifications)

enum Reminders {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// A reminder at 10 AM on each tenant's due day, plus one on the increment date.
    static func schedule(for tenants: [Tenant]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let today = Calendar.current.startOfDay(for: Date())

        for t in tenants where t.isActive {
            let unitText = t.unit.isEmpty ? "" : " (\(t.unit))"

            let due = UNMutableNotificationContent()
            due.title = "Rent due today"
            due.body = "\(t.name)\(unitText) - \(inr(t.currentRent))"
            due.sound = .default
            var dueTime = DateComponents()
            dueTime.day = t.safeDueDay
            dueTime.hour = 10
            dueTime.minute = 0
            let dueTrigger = UNCalendarNotificationTrigger(dateMatching: dueTime, repeats: true)
            center.add(UNNotificationRequest(identifier: "due-\(t.id.uuidString)", content: due, trigger: dueTrigger),
                       withCompletionHandler: nil)

            if let incDate = t.nextIncrementDate, Calendar.current.startOfDay(for: incDate) >= today {
                let inc = UNMutableNotificationContent()
                inc.title = "Rent increment due"
                inc.body = "\(t.name)\(unitText): increment due today. Current rent \(inr(t.currentRent))."
                inc.sound = .default
                var incTime = Calendar.current.dateComponents([.year, .month, .day], from: incDate)
                incTime.hour = 10
                incTime.minute = 0
                let incTrigger = UNCalendarNotificationTrigger(dateMatching: incTime, repeats: false)
                center.add(UNNotificationRequest(identifier: "inc-\(t.id.uuidString)", content: inc, trigger: incTrigger),
                           withCompletionHandler: nil)
            }
        }
    }
}

// MARK: - App

@main
struct RentBookApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onAppear { Reminders.requestPermission() }
        }
    }
}

// MARK: - Home screen

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var pendingRestore: [Tenant] = []
    @State private var showingRestoreAlert = false
    @State private var showingError = false

    private var activeTenants: [Tenant] {
        store.tenants
            .filter { $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pastTenants: [Tenant] {
        store.tenants
            .filter { !$0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var incrementDue: [Tenant] {
        activeTenants.filter { $0.isIncrementDue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryView(tenants: store.tenants)
                }
                incrementSection
                tenantSection
                pastSection
            }
            .navigationTitle("RentBook")
            .navigationDestination(for: UUID.self) { id in
                TenantDetailView(tenantID: id)
            }
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("Replace current data?", isPresented: $showingRestoreAlert) {
                Button("Replace", role: .destructive) {
                    store.replaceAll(with: pendingRestore)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This backup has \(pendingRestore.count) tenant(s). Everything now in RentBook will be replaced.")
            }
        }
        .sheet(isPresented: $showingAdd) {
            TenantFormView(tenant: nil)
                .environmentObject(store)
        }
        .alert("That file isn't a RentBook backup.", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        }
    }

    @ViewBuilder
    private var incrementSection: some View {
        if !incrementDue.isEmpty {
            Section("Increment due") {
                ForEach(incrementDue) { t in
                    NavigationLink(value: t.id) {
                        Label("\(t.name) - since \(shortDate(t.nextIncrementDate ?? Date()))", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        }
    }

    private var tenantSection: some View {
        Section("Tenants") {
            if activeTenants.isEmpty {
                Text("Tap + to add your first tenant.")
                    .foregroundStyle(.secondary)
            }
            ForEach(activeTenants) { t in
                NavigationLink(value: t.id) {
                    TenantRow(tenant: t)
                }
            }
        }
    }

    @ViewBuilder
    private var pastSection: some View {
        if !pastTenants.isEmpty {
            Section("Moved out") {
                ForEach(pastTenants) { t in
                    NavigationLink(value: t.id) {
                        TenantRow(tenant: t)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                ShareLink(item: store.backupURL) {
                    Label("Backup data", systemImage: "square.and.arrow.up")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Restore from backup", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            pendingRestore = try store.readBackup(at: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingRestoreAlert = true
            }
        } catch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingError = true
            }
        }
    }
}

struct SummaryView: View {
    let tenants: [Tenant]

    private var totalPending: Int {
        tenants.map { max($0.balance, 0) }.reduce(0, +)
    }

    private var monthlyRentRoll: Int {
        tenants.filter { $0.isActive }.map { $0.currentRent }.reduce(0, +)
    }

    private var collectedThisMonth: Int {
        let cal = Calendar.current
        let now = Date()
        return tenants
            .flatMap { $0.payments }
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .map { $0.amount }
            .reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total pending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(inr(totalPending))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(totalPending > 0 ? Color.red : Color.green)
            }
            HStack(alignment: .top) {
                stat("Collected this month", inr(collectedThisMonth))
                Spacer()
                stat("Monthly rent (all)", inr(monthlyRentRoll))
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}

struct TenantRow: View {
    let tenant: Tenant

    private var balance: Int { tenant.balance }

    private var subtitle: String {
        var parts: [String] = []
        if !tenant.unit.isEmpty { parts.append(tenant.unit) }
        parts.append("\(inr(tenant.currentRent))/month")
        if tenant.isActive { parts.append("due \(ordinal(tenant.safeDueDay))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(tenant.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if balance > 0 {
                amountLabel(inr(balance), caption: "pending", color: .red)
            } else if balance < 0 {
                amountLabel(inr(-balance), caption: "advance", color: .green)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.vertical, 2)
    }

    private func amountLabel(_ amount: String, caption: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(amount)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tenant screen

enum DetailSheet: String, Identifiable {
    case payment, edit, increment
    var id: String { rawValue }
}

struct TenantDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let tenantID: UUID

    @State private var sheet: DetailSheet? = nil
    @State private var confirmDelete = false

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text("This tenant was deleted.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        List {
            statusSection(t)
            detailsSection(t)
            totalsSection(t)
            paymentsSection(t)
            rentSection(t)
        }
        .navigationTitle(t.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { sheet = .edit } label: {
                        Label("Edit tenant", systemImage: "pencil")
                    }
                    Button { sheet = .increment } label: {
                        Label("Change rent / increment", systemImage: "arrow.up.circle")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete tenant", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { which in
            sheetContent(which, tenant: t)
                .environmentObject(store)
        }
        .confirmationDialog("Delete \(t.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete tenant and all payments", role: .destructive) {
                store.delete(t.id)
                dismiss()
            }
        } message: {
            Text("This can't be undone. Make a backup first if you're unsure.")
        }
    }

    private func statusSection(_ t: Tenant) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(t))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(inr(abs(t.balance)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(t.balance > 0 ? Color.red : Color.green)
                if t.isIncrementDue {
                    Label("Rent increment is due", systemImage: "arrow.up.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(.vertical, 4)

            Button { sheet = .payment } label: {
                Label("Record payment", systemImage: "indianrupeesign.circle")
            }
            if t.isIncrementDue {
                Button { sheet = .increment } label: {
                    Label("Apply rent increment", systemImage: "arrow.up.circle")
                }
            }
            if let url = whatsappURL(for: t) {
                Button { openURL(url) } label: {
                    Label("WhatsApp reminder", systemImage: "message")
                }
            }
            if let url = callURL(for: t) {
                Button { openURL(url) } label: {
                    Label("Call", systemImage: "phone")
                }
            }
        }
    }

    private func detailsSection(_ t: Tenant) -> some View {
        Section("Details") {
            LabeledContent("Monthly rent", value: inr(t.currentRent))
            if t.isActive {
                LabeledContent("Due on", value: "\(ordinal(t.safeDueDay)) of every month")
                LabeledContent("Next due date", value: shortDate(t.nextDueDate))
            }
            LabeledContent("Rent counted from", value: shortDate(t.startDate))
            if let out = t.moveOutDate {
                LabeledContent("Moved out", value: shortDate(out))
            }
            if let next = t.nextIncrementDate, t.isActive {
                LabeledContent("Next increment", value: "\(shortDate(next)) · +\(t.incrementPercent.formatted())%")
            }
            if t.deposit > 0 {
                LabeledContent("Security deposit", value: inr(t.deposit))
            }
            if !t.unit.isEmpty {
                LabeledContent("Room / flat", value: t.unit)
            }
            if !t.phone.isEmpty {
                LabeledContent("Phone", value: t.phone)
            }
            if !t.notes.isEmpty {
                Text(t.notes)
                    .font(.callout)
            }
        }
    }

    private func totalsSection(_ t: Tenant) -> some View {
        Section("Totals") {
            if t.openingBalance != 0 {
                LabeledContent("Older dues", value: inr(t.openingBalance))
            }
            LabeledContent("Rent since \(shortDate(t.startDate))", value: inr(t.totalBilled))
            LabeledContent("Total paid", value: inr(t.totalPaid))
        }
    }

    private func paymentsSection(_ t: Tenant) -> some View {
        let list = t.payments.sorted { $0.date > $1.date }
        return Section {
            if list.isEmpty {
                Text("No payments recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { p in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(inr(p.amount))
                            .font(.headline)
                        Spacer()
                        Text(shortDate(p.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(p.note.isEmpty ? p.method : "\(p.method) · \(p.note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                store.deletePayments(offsets.map { list[$0].id }, from: t.id)
            }
        } header: {
            Text("Payments")
        } footer: {
            Text("Swipe left on an entry to delete it.")
        }
    }

    private func rentSection(_ t: Tenant) -> some View {
        let list = Array(t.sortedRentHistory.reversed())
        return Section("Rent history") {
            ForEach(list) { r in
                LabeledContent(shortDate(r.effectiveDate), value: inr(r.amount))
            }
            .onDelete { offsets in
                store.deleteRentChanges(offsets.map { list[$0].id }, from: t.id)
            }
            .deleteDisabled(list.count <= 1)
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: DetailSheet, tenant t: Tenant) -> some View {
        switch which {
        case .payment:
            PaymentFormView(tenant: t)
        case .edit:
            TenantFormView(tenant: t)
        case .increment:
            IncrementView(tenant: t)
        }
    }

    private func statusTitle(_ t: Tenant) -> String {
        if t.balance > 0 { return "Pending" }
        if t.balance < 0 { return "Paid in advance" }
        return "All clear"
    }
}

// MARK: - Record a payment

struct PaymentFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenant: Tenant

    @State private var amountText: String
    @State private var date = Date()
    @State private var method = "UPI"
    @State private var note = ""

    private let methods = ["UPI", "Cash", "Bank transfer", "Cheque", "Other"]

    init(tenant: Tenant) {
        self.tenant = tenant
        let suggested = tenant.balance > 0 ? tenant.balance : tenant.currentRent
        _amountText = State(initialValue: String(suggested))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount (₹)", text: $amountText)
                        .keyboardType(.numberPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Paid by", selection: $method) {
                        ForEach(methods, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Pending before this payment: \(inr(max(tenant.balance, 0)))")
                }
            }
            .navigationTitle(tenant.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((parseAmount(amountText) ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        if let amount = parseAmount(amountText), amount > 0 {
            let payment = Payment(date: date, amount: amount, method: method,
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            store.addPayment(payment, to: tenant.id)
        }
        dismiss()
    }
}

// MARK: - Add / edit a tenant

struct TenantFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let existing: Tenant?

    @State private var name: String
    @State private var phone: String
    @State private var unit: String
    @State private var rentText: String
    @State private var depositText: String
    @State private var openingText: String
    @State private var startDate: Date
    @State private var dueDay: Int
    @State private var tracksIncrement: Bool
    @State private var nextIncrement: Date
    @State private var percentText: String
    @State private var everyMonths: Int
    @State private var movedOut: Bool
    @State private var moveOutDate: Date
    @State private var notes: String

    init(tenant: Tenant?) {
        existing = tenant
        let t = tenant ?? Tenant()
        let firstRent = t.sortedRentHistory.first?.amount ?? 0
        let defaultNext = Calendar.current.date(byAdding: .month, value: t.incrementEveryMonths, to: t.startDate) ?? t.startDate
        _name = State(initialValue: t.name)
        _phone = State(initialValue: t.phone)
        _unit = State(initialValue: t.unit)
        _rentText = State(initialValue: firstRent > 0 ? String(firstRent) : "")
        _depositText = State(initialValue: t.deposit > 0 ? String(t.deposit) : "")
        _openingText = State(initialValue: t.openingBalance > 0 ? String(t.openingBalance) : "")
        _startDate = State(initialValue: t.startDate)
        _dueDay = State(initialValue: t.safeDueDay)
        _tracksIncrement = State(initialValue: tenant == nil || t.nextIncrementDate != nil)
        _nextIncrement = State(initialValue: t.nextIncrementDate ?? defaultNext)
        _percentText = State(initialValue: t.incrementPercent.formatted())
        _everyMonths = State(initialValue: t.incrementEveryMonths)
        _movedOut = State(initialValue: t.moveOutDate != nil)
        _moveOutDate = State(initialValue: t.moveOutDate ?? Date())
        _notes = State(initialValue: t.notes)
    }

    private var screenTitle: String { existing == nil ? "New tenant" : "Edit tenant" }
    private var rentLabel: String { existing == nil ? "Monthly rent (₹)" : "Starting rent (₹)" }

    var body: some View {
        NavigationStack {
            Form {
                tenantSection
                rentSection
                incrementSection
                moveOutSection
                Section("Notes") {
                    TextField("Agreement details, ID proof, etc.", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var tenantSection: some View {
        Section("Tenant") {
            TextField("Name", text: $name)
            TextField("Phone (for WhatsApp & calls)", text: $phone)
                .keyboardType(.phonePad)
            TextField("Room / flat (optional)", text: $unit)
        }
    }

    private var rentSection: some View {
        Section {
            TextField(rentLabel, text: $rentText)
                .keyboardType(.numberPad)
            DatePicker("Count rent from", selection: $startDate, displayedComponents: .date)
            Picker("Rent due on", selection: $dueDay) {
                ForEach(1...28, id: \.self) { day in
                    Text("\(ordinal(day)) of month").tag(day)
                }
            }
            TextField("Older pending dues (₹, optional)", text: $openingText)
                .keyboardType(.numberPad)
            TextField("Security deposit (₹, optional)", text: $depositText)
                .keyboardType(.numberPad)
        } header: {
            Text("Rent")
        } footer: {
            Text("New tenant: pick the move-in date. Existing tenant: pick this month, and enter any unpaid rent from before as older dues.")
        }
    }

    private var incrementSection: some View {
        Section("Increment") {
            Toggle("Remind me about increments", isOn: $tracksIncrement)
            if tracksIncrement {
                DatePicker("Next increment", selection: $nextIncrement, displayedComponents: .date)
                HStack {
                    Text("Increase by")
                    Spacer()
                    TextField("5", text: $percentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("%")
                }
                Stepper("Every \(everyMonths) months", value: $everyMonths, in: 1...60)
            }
        }
    }

    private var moveOutSection: some View {
        Section {
            Toggle("Moved out", isOn: $movedOut)
            if movedOut {
                DatePicker("Move-out date", selection: $moveOutDate, displayedComponents: .date)
            }
        } footer: {
            Text("Rent stops adding up after the move-out date.")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parseAmount(rentText) ?? 0) > 0
    }

    private func save() {
        var t = existing ?? Tenant()
        let rent = parseAmount(rentText) ?? 0
        t.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        t.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        t.deposit = parseAmount(depositText) ?? 0
        t.openingBalance = parseAmount(openingText) ?? 0
        t.startDate = startDate
        t.dueDay = dueDay
        t.incrementEveryMonths = everyMonths
        if let pct = parsePercent(percentText) { t.incrementPercent = pct }
        t.nextIncrementDate = tracksIncrement ? nextIncrement : nil
        t.moveOutDate = movedOut ? moveOutDate : nil
        t.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let history = t.rentHistory
        if let first = history.indices.min(by: { history[$0].effectiveDate < history[$1].effectiveDate }) {
            t.rentHistory[first].amount = rent
            t.rentHistory[first].effectiveDate = startDate
        } else {
            t.rentHistory = [RentChange(effectiveDate: startDate, amount: rent)]
        }
        store.upsert(t)
        dismiss()
    }
}

// MARK: - Rent increment / change

struct IncrementView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenant: Tenant

    @State private var percentText: String
    @State private var exactText = ""
    @State private var effectiveDate: Date
    @State private var scheduleNext: Bool
    @State private var nextDate: Date

    init(tenant: Tenant) {
        self.tenant = tenant
        let effective = tenant.nextIncrementDate ?? Date()
        _percentText = State(initialValue: tenant.incrementPercent.formatted())
        _effectiveDate = State(initialValue: effective)
        _scheduleNext = State(initialValue: tenant.isActive)
        _nextDate = State(initialValue: Calendar.current.date(byAdding: .month, value: tenant.incrementEveryMonths, to: effective) ?? effective)
    }

    private var calculatedRent: Int {
        let pct = parsePercent(percentText) ?? 0
        return Int((Double(tenant.currentRent) * (1 + pct / 100)).rounded())
    }

    private var newRent: Int {
        if let exact = parseAmount(exactText), exact > 0 { return exact }
        return calculatedRent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current rent", value: inr(tenant.currentRent))
                    HStack {
                        Text("Increase by")
                        Spacer()
                        TextField("5", text: $percentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("%")
                    }
                    TextField("Or type the exact new rent (₹)", text: $exactText)
                        .keyboardType(.numberPad)
                    LabeledContent("New rent", value: inr(newRent))
                        .font(.headline)
                    DatePicker("Effective from", selection: $effectiveDate, displayedComponents: .date)
                }
                Section {
                    Toggle("Remind me about the next one", isOn: $scheduleNext)
                    if scheduleNext {
                        DatePicker("Next increment", selection: $nextDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Earlier months keep the old rent; the new rent counts from the effective date.")
                }
            }
            .navigationTitle("Rent increment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(newRent <= 0)
                }
            }
        }
    }

    private func apply() {
        let usedPercent = parseAmount(exactText) == nil ? parsePercent(percentText) : nil
        store.applyIncrement(to: tenant.id,
                             newRent: newRent,
                             from: effectiveDate,
                             nextIncrement: scheduleNext ? nextDate : nil,
                             percent: usedPercent)
        dismiss()
    }
}
