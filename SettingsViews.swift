//  SettingsViews.swift
//  Settings: backup and restore, reminders, app lock, defaults, archived
//  records, change history, sample data and erasing.

import SwiftUI
import UniformTypeIdentifiers

enum SettingsText {
    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(n) " + word + (n == 1 ? "" : "s")
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var showErase = false
    @State private var lockProblem = false

    var body: some View {
        List {
            backupSection
            remindersSection
            securitySection
            Section("Rent and receipts") {
                NavigationLink(value: Route.defaults) {
                    Label("Defaults, receipts and numbering", systemImage: "slider.horizontal.3")
                }
            }
            Section("Records") {
                NavigationLink(value: Route.archived) {
                    Label("Archived tenants, properties and expenses", systemImage: "archivebox")
                }
                NavigationLink(value: Route.audit) {
                    Label("Change history", systemImage: "clock.arrow.circlepath")
                }
            }
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showErase) {
            EraseDataView().environmentObject(store)
        }
        .alert("Set a passcode first", isPresented: $lockProblem) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The app lock uses Face ID or your iPhone passcode. Turn on a passcode in iPhone Settings → Face ID & Passcode, then try again.")
        }
    }

    private var backupStatus: String {
        if store.backup.lastError != nil { return "Needs attention" }
        guard store.backup.folderName != nil else { return "Off" }
        if store.backup.isRunning { return "Backing up…" }
        if let last = store.backup.lastSuccess { return SettingsText.ago(last) }
        return "On"
    }

    private var backupSection: some View {
        Section {
            NavigationLink(value: Route.backup) {
                HStack {
                    Label("Backup and restore", systemImage: "icloud")
                    Spacer()
                    Text(backupStatus)
                        .font(.caption)
                        .foregroundStyle(store.backup.lastError == nil ? Color.secondary : Color.red)
                }
            }
        } footer: {
            if store.backup.folderName == nil {
                Text("Turn on automatic backup to iCloud Drive so your records are safe if this iPhone is lost or replaced.")
            }
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            NavigationLink(value: Route.reminders) {
                HStack {
                    Label("Reminder settings", systemImage: "bell")
                    Spacer()
                    Text(store.notificationStatus)
                        .font(.caption)
                        .foregroundStyle(store.notificationsAllowed ? Color.secondary : Color.orange)
                }
            }
            NavigationLink(value: Route.upcomingReminders) {
                HStack {
                    Label("Upcoming reminders", systemImage: "calendar.badge.clock")
                    Spacer()
                    Text("\(store.upcomingReminders.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { store.settings.appLockEnabled },
            set: { on in
                if on && !LockManager.canAuthenticate {
                    lockProblem = true
                    return
                }
                store.change(on ? "App lock turned on" : "App lock turned off") { d in
                    d.settings.appLockEnabled = on
                }
            }
        )
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: lockBinding) {
                Label("Lock with " + LockManager.methodName, systemImage: "lock")
            }
            if store.settings.appLockEnabled {
                Picker("Lock after", selection: store.setting(\.lockAfterMinutes)) {
                    Text("Immediately").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Your records stay on this iPhone and in your own iCloud Drive. There are no accounts, no tenant logins and no public links. With the lock on, the screen is hidden in the app switcher.")
        }
    }

    private var dataSection: some View {
        Section {
            if store.isEmpty {
                Button {
                    store.loadSampleData()
                } label: {
                    Label("Load sample data to try the app", systemImage: "wand.and.stars")
                }
            }
            Button(role: .destructive) {
                showErase = true
            } label: {
                Label("Erase all data…", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Sample data adds made-up properties and tenants. Erase it when you're ready to enter your own.")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : version + " (" + build + ")"
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Text("RentBook keeps rent records for your own properties. Amounts are in rupees and dates are shown as day/month/year.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Erase everything

struct EraseDataView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This removes every property, tenant, payment, expense, photo and document from RentBook on this iPhone. Your settings stay.")
                    Text("Automatic backup is turned off first, so the backup in your iCloud Drive folder is left as it is and can be restored later.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Type DELETE to confirm", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Button(role: .destructive) {
                        store.eraseAll()
                        dismiss()
                    } label: {
                        Text("Erase all data")
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != "DELETE")
                }
            }
            .navigationTitle("Erase all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Backup and restore

enum ImportMode {
    case folder, restoreFile, restoreFolder
}

/// A folder chosen for backups that already holds a RentBook backup.
struct FolderChoice: Identifiable {
    let id = UUID()
    let url: URL
    let existing: RestorePreview
}

enum PendingRestore: Identifiable {
    case backup(RestorePreview)
    case safety(RestorePreview)

    var id: UUID {
        switch self {
        case .backup(let p): return p.id
        case .safety(let p): return p.id
        }
    }

    var preview: RestorePreview {
        switch self {
        case .backup(let p): return p
        case .safety(let p): return p
        }
    }
}

struct BackupView: View {
    @EnvironmentObject var store: Store
    @State private var importMode: ImportMode = .folder
    @State private var showImporter = false
    @State private var pending: PendingRestore? = nil
    @State private var problem: String? = nil
    @State private var share: ShareItem? = nil
    @State private var askStop = false
    @State private var folderChoice: FolderChoice? = nil

    private var folderBinding: Binding<Bool> {
        Binding(get: { folderChoice != nil }, set: { if !$0 { folderChoice = nil } })
    }

    private var importTypes: [UTType] {
        switch importMode {
        case .folder, .restoreFolder: return [.folder]
        case .restoreFile: return [.json]
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var problemBinding: Binding<Bool> {
        Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    }

    var body: some View {
        List {
            autoSection
            fileSection
            restoreSection
            safetySection
        }
        .navigationTitle("Backup")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("Replace your data?", isPresented: pendingBinding, titleVisibility: .visible, presenting: pending) { item in
            Button("Replace with this data", role: .destructive) {
                apply(item)
            }
        } message: { item in
            Text("This holds " + item.preview.summary + ". Everything now in RentBook on this iPhone will be replaced. A copy of the current data is kept, so you can bring it back from this screen.")
        }
        .confirmationDialog("This folder already has a backup", isPresented: folderBinding, titleVisibility: .visible,
                            presenting: folderChoice) { choice in
            Button("Restore it to this iPhone") {
                store.applyRestore(choice.existing)
                store.chooseBackupFolder(choice.url)
            }
            Button("Replace it with this iPhone's data", role: .destructive) {
                store.chooseBackupFolder(choice.url)
            }
        } message: { choice in
            Text("The backup holds " + choice.existing.summary + ". This iPhone has " + store.localSummary
                 + ". Restore the backup here, or replace it with what is on this iPhone.")
        }
        .confirmationDialog("Turn off automatic backup?", isPresented: $askStop, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) {
                store.stopAutoBackup()
            }
        } message: {
            Text("Files already in the backup folder are kept.")
        }
        .alert("Couldn't use that", isPresented: problemBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private var lastBackupText: String {
        guard let last = store.backup.lastSuccess else { return "Not yet" }
        return Fmt.dateTime(last)
    }

    private var autoSection: some View {
        Section {
            if let folder = store.backup.folderName {
                LabeledContent("Backup folder", value: folder)
                LabeledContent("Last backup", value: lastBackupText)
                if store.backup.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Backing up…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = store.backup.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    store.backupNow()
                } label: {
                    Label("Back up now", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(store.backup.isRunning)
                Button {
                    choose(.folder)
                } label: {
                    Label("Choose a different folder", systemImage: "folder")
                }
                Button {
                    askStop = true
                } label: {
                    Label("Turn off automatic backup", systemImage: "icloud.slash")
                }
            } else {
                Button {
                    choose(.folder)
                } label: {
                    Label("Choose an iCloud Drive folder", systemImage: "folder.badge.plus")
                }
                if let error = store.backup.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Automatic backup to iCloud Drive")
        } footer: {
            Text("In the Files window, open iCloud Drive, make a folder (for example “RentBook”) and choose it. After every change RentBook saves a “RentBook Backup” folder there with all records, photos and documents, and keeps a dated copy for each of the last 30 days it backed up. Only you can see it.")
        }
    }

    private var fileSection: some View {
        Section {
            Button {
                if let url = store.exportFullBackup() {
                    share = ShareItem(url: url)
                }
            } label: {
                Label("Export a full backup file", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Backup file")
        } footer: {
            Text("One file with every record, photo and document. Save it in Files or on a computer. Keep it private: it holds your tenants' details.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                choose(.restoreFolder)
            } label: {
                Label("Restore from the backup folder", systemImage: "folder")
            }
            Button {
                choose(.restoreFile)
            } label: {
                Label("Restore from a backup file", systemImage: "doc")
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("For a new iPhone: install RentBook, then choose the folder that holds “RentBook Backup”. You'll see what the backup contains before anything is replaced. Data files from RentBook 1.0 can be restored too.")
        }
    }

    @ViewBuilder
    private var safetySection: some View {
        if let saved = store.safetyCopyDate {
            Section {
                Button {
                    if let p = store.safetyCopyPreview() {
                        pending = .safety(p)
                    } else {
                        problem = "The earlier copy couldn't be read."
                    }
                } label: {
                    Label("Bring back the data from before the last erase or restore", systemImage: "arrow.uturn.backward.circle")
                }
            } footer: {
                Text("Saved on this iPhone on " + Fmt.dateTime(saved) + ".")
            }
        }
    }

    private func choose(_ mode: ImportMode) {
        importMode = mode
        showImporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            problem = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            switch importMode {
            case .folder:
                // Never write over a backup that is already there without asking.
                if let existing = store.existingBackup(in: url) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        folderChoice = FolderChoice(url: url, existing: existing)
                    }
                } else {
                    store.chooseBackupFolder(url)
                }
            case .restoreFile:
                prepare { try store.prepareRestore(fromFile: url) }
            case .restoreFolder:
                prepare { try store.prepareRestore(fromFolder: url) }
            }
        }
    }

    private func prepare(_ load: () throws -> RestorePreview) {
        do {
            let preview = try load()
            // Wait for the Files window to close before asking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pending = .backup(preview)
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func apply(_ item: PendingRestore) {
        switch item {
        case .backup(let p):
            store.applyRestore(p)
        case .safety(let p):
            store.restoreSafetyCopy(p)
        }
        pending = nil
    }
}

// MARK: - Reminders

struct ReminderSettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL

    private var timeBinding: Binding<Date> {
        Binding(
            get: { DateMath.at(Date(), hour: store.settings.reminderHour, minute: store.settings.reminderMinute) },
            set: { newValue in
                let parts = rbCalendar.dateComponents([.hour, .minute], from: newValue)
                store.change { d in
                    d.settings.reminderHour = parts.hour ?? 10
                    d.settings.reminderMinute = parts.minute ?? 0
                }
            }
        )
    }

    private var beforeText: String { SettingsText.plural(store.settings.remindDaysBefore, "day") + " before" }
    private var repeatText: String { "Repeat every " + SettingsText.plural(store.settings.overdueRepeatDays, "day") }
    private var increaseText: String { SettingsText.plural(store.settings.increaseDaysBefore, "day") + " before an increase" }
    private var agreementText: String { "New agreements: " + SettingsText.plural(store.settings.agreementDaysBefore, "day") + " before the end" }

    var body: some View {
        Form {
            permissionSection
            Section("Time of day") {
                DatePicker("Remind me at", selection: timeBinding, displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("Before the due date", isOn: store.setting(\.remindBeforeDue))
                if store.settings.remindBeforeDue {
                    Stepper(beforeText, value: store.setting(\.remindDaysBefore), in: 1...15)
                }
                Toggle("On the due date", isOn: store.setting(\.remindOnDue))
                Toggle("When rent is overdue", isOn: store.setting(\.remindOverdue))
                if store.settings.remindOverdue {
                    Stepper(repeatText, value: store.setting(\.overdueRepeatDays), in: 1...30)
                }
            } header: {
                Text("Rent")
            } footer: {
                Text("Rent counts as overdue after the grace period set in Defaults. Each tenant can have their own timing: open the tenant, tap Edit and look under Reminders.")
            }
            Section("Other reminders") {
                Toggle("Payment promises", isOn: store.setting(\.remindPromises))
                Toggle("Follow-ups", isOn: store.setting(\.remindFollowUps))
                Toggle("Rent increases", isOn: store.setting(\.remindIncreases))
                if store.settings.remindIncreases {
                    Stepper(increaseText, value: store.setting(\.increaseDaysBefore), in: 1...90)
                }
                Toggle("Agreements ending", isOn: store.setting(\.remindAgreements))
                if store.settings.remindAgreements {
                    Stepper(agreementText, value: store.setting(\.agreementDaysBefore), in: 5...120, step: 5)
                }
                Toggle("Vacant units (Mondays)", isOn: store.setting(\.remindVacant))
                Toggle("Deposits to settle (Mondays)", isOn: store.setting(\.remindDeposits))
            }
            Section {
                NavigationLink(value: Route.upcomingReminders) {
                    Text("See upcoming reminders")
                }
            }
        }
        .navigationTitle("Reminders")
        .onAppear {
            store.refreshNotificationStatus()
        }
    }

    private var permissionSection: some View {
        Section {
            LabeledContent("Notifications", value: store.notificationStatus)
            if !store.notificationsAllowed {
                Button("Allow notifications") {
                    store.requestNotificationPermission()
                }
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } footer: {
            Text("Reminders are planned for the next 45 days and refreshed whenever you open RentBook. iPhone keeps up to 64 at a time, so open the app every few weeks.")
        }
    }
}

struct UpcomingRemindersView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let groups = Dictionary(grouping: store.upcomingReminders) { DateMath.day($0.date) }.sorted { $0.key < $1.key }
        List {
            if !store.notificationsAllowed {
                Section {
                    Text("Notifications are off, so these won't appear. Turn them on in Settings → Reminders.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if groups.isEmpty {
                Text("Nothing planned for the next 45 days.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.key) { group in
                Section(Fmt.longDate(group.key)) {
                    ForEach(group.value) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(r.date.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(r.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Upcoming reminders")
        .refreshable { @MainActor in
            store.refreshReminders()
        }
        .onAppear {
            store.refreshReminders()
        }
    }
}

// MARK: - Defaults

struct DefaultsView: View {
    @EnvironmentObject var store: Store
    @State private var landlordName = ""
    @State private var landlordPhone = ""
    @State private var escalationText = ""
    @State private var chargeTitle = ""
    @State private var chargeAmount = ""
    @State private var loaded = false

    private var graceText: String { "Grace period: " + SettingsText.plural(store.settings.gracePeriodDays, "day") }
    private var everyText: String { "Every " + SettingsText.plural(store.settings.defaultEscalationMonths, "month") }
    private var valueLabel: String { store.settings.defaultEscalationMode == .percent ? "Percentage" : "Amount (₹)" }

    var body: some View {
        Form {
            Section {
                Picker("Rent due on", selection: store.setting(\.defaultDueDay)) {
                    ForEach(1...28, id: \.self) { day in
                        Text(Fmt.ordinal(day) + " of the month").tag(day)
                    }
                }
                Toggle("Part-month rent at move-in and move-out", isOn: store.setting(\.defaultProrate))
                Stepper(graceText, value: store.setting(\.gracePeriodDays), in: 0...30)
                Toggle("Settle the oldest dues first", isOn: store.setting(\.autoAllocate))
            } header: {
                Text("Rent")
            } footer: {
                Text("Due date and part-month rent apply to new tenants. Rent becomes overdue after the grace period. With “Settle the oldest dues first” off, the payment screen asks which months each payment is for.")
            }
            Section {
                Picker("Increase by", selection: store.setting(\.defaultEscalationMode)) {
                    ForEach(EscalationMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(valueLabel)
                    Spacer()
                    TextField("5", text: $escalationText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                Stepper(everyText, value: store.setting(\.defaultEscalationMonths), in: 1...120)
            } header: {
                Text("Rent increases for new tenants")
            }
            chargesSection
            Section {
                TextField("Your name", text: $landlordName)
                    .textContentType(.name)
                TextField("Your mobile number", text: $landlordPhone)
                    .keyboardType(.phonePad)
            } header: {
                Text("On receipts and messages")
            } footer: {
                Text("Shown on PDF receipts and at the end of WhatsApp messages. Saved when you leave this screen.")
            }
            Section("Numbering") {
                LabeledContent("Next receipt number", value: "\(store.settings.nextReceiptNumber)")
                LabeledContent("Next property ID", value: store.nextPropertyCode())
            }
        }
        .navigationTitle("Defaults")
        .keyboardDoneButton()
        .onAppear(perform: load)
        .onDisappear(perform: saveText)
    }

    private var chargesSection: some View {
        Section {
            ForEach(store.settings.defaultRecurringCharges) { rc in
                LabeledContent(rc.title, value: Fmt.inr(rc.amount) + " / month")
            }
            .onDelete { offsets in
                store.change { d in
                    d.settings.defaultRecurringCharges.remove(atOffsets: offsets)
                }
            }
            HStack {
                TextField("Name, e.g. Maintenance", text: $chargeTitle)
                TextField("₹", text: $chargeAmount)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                Button {
                    addCharge()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(chargeTitle.trimmingCharacters(in: .whitespaces).isEmpty || (parseAmount(chargeAmount) ?? 0) <= 0)
            }
        } header: {
            Text("Monthly extras for new tenants")
        } footer: {
            Text("Added to each new tenant, for example maintenance or parking. Swipe left to remove one.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        landlordName = store.settings.landlordName
        landlordPhone = store.settings.landlordPhone
        escalationText = Fmt.number(store.settings.defaultEscalationValue)
    }

    private func saveText() {
        let name = landlordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = landlordPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parseDecimal(escalationText)
        let s = store.settings
        let changed = name != s.landlordName || phone != s.landlordPhone || (value != nil && value != s.defaultEscalationValue)
        guard changed else { return }
        store.change { d in
            d.settings.landlordName = name
            d.settings.landlordPhone = phone
            if let v = value, v > 0 {
                d.settings.defaultEscalationValue = v
            }
        }
    }

    private func addCharge() {
        let title = chargeTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let amount = parseAmount(chargeAmount), amount > 0 else { return }
        let charge = RecurringCharge(title: title, amount: amount)
        store.change { d in
            d.settings.defaultRecurringCharges.append(charge)
        }
        chargeTitle = ""
        chargeAmount = ""
    }
}

// MARK: - Archived records

enum ArchivedDelete: Identifiable {
    case tenant(UUID)
    case property(UUID)
    case expense(UUID)

    var id: String {
        switch self {
        case .tenant(let id): return "t-" + id.uuidString
        case .property(let id): return "p-" + id.uuidString
        case .expense(let id): return "e-" + id.uuidString
        }
    }
}

struct ArchivedView: View {
    @EnvironmentObject var store: Store
    @State private var pending: ArchivedDelete? = nil

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    var body: some View {
        let tenants = store.data.tenants.filter { $0.isArchived }.sorted { $0.name < $1.name }
        let properties = store.data.properties.filter { $0.isArchived }.sorted { $0.name < $1.name }
        let expenses = store.data.expenses.filter { $0.isArchived }.sorted { $0.date > $1.date }
        List {
            if tenants.isEmpty && properties.isEmpty && expenses.isEmpty {
                Text("Nothing is archived.")
                    .foregroundStyle(.secondary)
            }
            if !tenants.isEmpty {
                tenantSection(tenants)
            }
            if !properties.isEmpty {
                propertySection(properties)
            }
            if !expenses.isEmpty {
                expenseSection(expenses)
            }
        }
        .navigationTitle("Archived")
        .confirmationDialog("Delete permanently?", isPresented: pendingBinding, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let item = pending {
                    delete(item)
                }
                pending = nil
            }
        } message: {
            Text("This can't be undone. Attached photos and documents are deleted too. You may want to export a backup first.")
        }
    }

    private func tenantSection(_ tenants: [Tenant]) -> some View {
        Section {
            ForEach(tenants) { t in
                NavigationLink(value: Route.tenant(t.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                        Text(t.status.label + (store.place(of: t).isEmpty ? "" : " · " + store.place(of: t)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        store.setTenantArchived(t.id, false)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.blue)
                    Button {
                        pending = .tenant(t.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        } header: {
            Text("Tenants")
        } footer: {
            Text("Swipe left to restore or delete.")
        }
    }

    private func propertySection(_ properties: [RentalProperty]) -> some View {
        Section("Properties") {
            ForEach(properties) { p in
                NavigationLink(value: Route.property(p.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                        Text(p.code + " · " + p.type.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        store.setPropertyArchived(p.id, false)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.blue)
                    Button {
                        pending = .property(p.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func expenseSection(_ expenses: [Expense]) -> some View {
        Section("Expenses") {
            ForEach(expenses) { e in
                NavigationLink(value: Route.expense(e.id)) {
                    ExpenseRow(expense: e, place: ExpensePlace.text(e, store: store))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        store.setExpenseArchived(e.id, false)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.blue)
                    Button {
                        pending = .expense(e.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func delete(_ item: ArchivedDelete) {
        switch item {
        case .tenant(let id): store.deleteTenant(id)
        case .property(let id): store.deleteProperty(id)
        case .expense(let id): store.deleteExpense(id)
        }
    }
}

// MARK: - Change history

struct AuditView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""

    private var entries: [AuditEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.data.audit
        let list = q.isEmpty ? all : all.filter { $0.action.lowercased().contains(q) || $0.details.lowercased().contains(q) }
        return Array(list.prefix(500))
    }

    var body: some View {
        let list = entries
        List {
            Section {
                if list.isEmpty {
                    Text(query.isEmpty ? "No changes recorded yet." : "No changes match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top) {
                            Text(e.action)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(Fmt.dateTime(e.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !e.details.isEmpty {
                            Text(e.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Payments, rent changes, deposits, archiving and restores are recorded here. The latest 3,000 changes are kept.")
            }
        }
        .searchable(text: $query, prompt: "Search changes")
        .navigationTitle("Change history")
    }
}
