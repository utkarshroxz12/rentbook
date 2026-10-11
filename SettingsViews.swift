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
            languageSection
            backupSection
            remindersSection
            securitySection
            Section(L("Rent and receipts", "Rent aur raseed")) {
                NavigationLink(value: Route.defaults) {
                    Label(L("Defaults, receipts and numbering", "Defaults, raseed aur numbering"), systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: Route.partnership) {
                    Label(L("Hisaab with your brother", "Bhai ke saath hisaab"), systemImage: "person.2")
                }
            }
            Section(L("Records", "Record")) {
                NavigationLink(value: Route.archived) {
                    Label(L("Archived tenants, properties and expenses", "Archive kiye tenants, properties aur kharche"), systemImage: "archivebox")
                }
                NavigationLink(value: Route.audit) {
                    Label(L("Change history", "Badlav ki history"), systemImage: "clock.arrow.circlepath")
                }
            }
            dataSection
            aboutSection
        }
        .navigationTitle(L("Settings", "Settings"))
        .sheet(isPresented: $showErase) {
            EraseDataView().environmentObject(store)
        }
        .alert(L("Set a passcode first", "Pehle passcode set karein"), isPresented: $lockProblem) {
            Button(L("OK", "Theek hai"), role: .cancel) {}
        } message: {
            Text(L("The app lock uses Face ID or your iPhone passcode. Turn on a passcode in iPhone Settings → Face ID & Passcode, then try again.", "App lock Face ID ya iPhone passcode use karta hai. iPhone Settings → Face ID & Passcode mein passcode chalu karke dobara try karein."))
        }
    }

    private var languageSection: some View {
        Section {
            Picker(L("Language", "Bhasha"), selection: store.setting(\.language)) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L("Language", "Bhasha"))
        } footer: {
            Text(L("Hinglish is Hindi written in English letters. Messages can be sent in either language.",
                   "Hinglish matlab Hindi English letters mein. Message dono bhasha mein bhej sakte hain."))
        }
    }

    private var backupStatus: String {
        if store.backup.lastError != nil { return L("Needs attention", "Dhyan dein") }
        guard store.backup.folderName != nil else { return L("Off", "Band") }
        if store.backup.isRunning { return L("Backing up…", "Backup ho raha hai…") }
        if let last = store.backup.lastSuccess { return SettingsText.ago(last) }
        return L("On", "Chalu")
    }

    private var backupSection: some View {
        Section {
            NavigationLink(value: Route.backup) {
                HStack {
                    Label(L("Backup and restore", "Backup aur restore"), systemImage: "icloud")
                    Spacer()
                    Text(backupStatus)
                        .font(.caption)
                        .foregroundStyle(store.backup.lastError == nil ? Color.secondary : Color.red)
                }
            }
        } footer: {
            if store.backup.folderName == nil {
                Text(L("Turn on automatic backup to iCloud Drive so your records are safe if this iPhone is lost or replaced.", "iCloud Drive mein automatic backup chalu karein taaki iPhone kho jaye ya badle to bhi record surakshit rahein."))
            }
        }
    }

    private var remindersSection: some View {
        Section(L("Reminders", "Reminders")) {
            NavigationLink(value: Route.reminders) {
                HStack {
                    Label(L("Reminder settings", "Reminder settings"), systemImage: "bell")
                    Spacer()
                    Text(store.notificationStatus)
                        .font(.caption)
                        .foregroundStyle(store.notificationsAllowed ? Color.secondary : Color.orange)
                }
            }
            NavigationLink(value: Route.upcomingReminders) {
                HStack {
                    Label(L("Upcoming reminders", "Aane wale reminders"), systemImage: "calendar.badge.clock")
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
                Label(L("Lock with " + LockManager.methodName, LockManager.methodName + " se lock karein"), systemImage: "lock")
            }
            if store.settings.appLockEnabled {
                Picker(L("Lock after", "Kitni der baad lock"), selection: store.setting(\.lockAfterMinutes)) {
                    Text(L("Immediately", "Turant")).tag(0)
                    Text(L("1 minute", "1 minute")).tag(1)
                    Text(L("5 minutes", "5 minute")).tag(5)
                    Text(L("15 minutes", "15 minute")).tag(15)
                    Text(L("1 hour", "1 ghanta")).tag(60)
                }
            }
        } header: {
            Text(L("Privacy", "Privacy"))
        } footer: {
            Text(L("Your records stay on this iPhone and in your own iCloud Drive. There are no accounts, no tenant logins and no public links. With the lock on, the screen is hidden in the app switcher.", "Aapke record sirf is iPhone aur aapke apne iCloud Drive mein rehte hain. Koi account, tenant login ya public link nahi hai. Lock chalu ho to app switcher mein screen chhupi rehti hai."))
        }
    }

    private var dataSection: some View {
        Section {
            if store.isEmpty {
                Button {
                    store.loadSampleData()
                } label: {
                    Label(L("Load sample data to try the app", "App try karne ke liye sample data load karein"), systemImage: "wand.and.stars")
                }
            }
            Button(role: .destructive) {
                showErase = true
            } label: {
                Label(L("Erase all data…", "Saara data mitayein…"), systemImage: "trash")
            }
        } header: {
            Text(L("Data", "Data"))
        } footer: {
            Text(L("Sample data adds made-up properties and tenants. Erase it when you're ready to enter your own.", "Sample data mein banawati properties aur tenants judte hain. Apna data daalne se pehle ise mita dein."))
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : version + " (" + build + ")"
    }

    private var aboutSection: some View {
        Section(L("About", "Jaankari")) {
            LabeledContent(L("Version", "Version"), value: appVersion)
            Text(L("RentBook keeps rent records for your own properties. Amounts are in rupees and dates are shown as day/month/year.", "RentBook aapki apni properties ka rent record rakhta hai. Amount rupaye mein aur tareekh din/mahina/saal mein dikhti hai."))
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
                    Text(L("This removes every property, tenant, payment, expense, photo and document from RentBook on this iPhone. Your settings stay.", "Isse is iPhone par RentBook ki har property, tenant, payment, kharcha, photo aur document hat jayega. Settings rahengi."))
                    Text(L("Automatic backup is turned off first, so the backup in your iCloud Drive folder is left as it is and can be restored later.", "Pehle automatic backup band hoga, taaki iCloud Drive folder ka backup waisa hi rahe aur baad mein restore ho sake."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField(L("Type DELETE to confirm", "Pakka karne ke liye DELETE likhein"), text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Button(role: .destructive) {
                        store.eraseAll()
                        dismiss()
                    } label: {
                        Text(L("Erase all data", "Saara data mitayein"))
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != "DELETE")
                }
            }
            .navigationTitle(L("Erase all data", "Saara data mitayein"))
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
    @State private var pending: PendingRestore? = nil
    @State private var problem: String? = nil
    @State private var share: ShareItem? = nil
    @State private var askStop = false
    @State private var folderChoice: FolderChoice? = nil

    private var folderBinding: Binding<Bool> {
        Binding(get: { folderChoice != nil }, set: { if !$0 { folderChoice = nil } })
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
        .navigationTitle(L("Backup", "Backup"))
        .sheet(item: $share) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog(L("Replace your data?", "Apna data badlein?"), isPresented: pendingBinding, titleVisibility: .visible, presenting: pending) { item in
            Button(L("Replace with this data", "Is data se badlein"), role: .destructive) {
                apply(item)
            }
        } message: { item in
            Text(L("This holds " + item.preview.summary + ". Everything now in RentBook on this iPhone will be replaced. A copy of the current data is kept, so you can bring it back from this screen.",
                   "Ismein " + item.preview.summary + " hai. Is iPhone par RentBook ka abhi ka sab data badal jayega. Abhi ke data ki copy rakhi jayegi, jise isi screen se wapas la sakte hain."))
        }
        .confirmationDialog(L("This folder already has a backup", "Is folder mein pehle se backup hai"), isPresented: folderBinding, titleVisibility: .visible,
                            presenting: folderChoice) { choice in
            Button(L("Restore it to this iPhone", "Ise is iPhone par wapas layein")) {
                store.applyRestore(choice.existing)
                store.chooseBackupFolder(choice.url)
            }
            Button(L("Replace it with this iPhone's data", "Ise is iPhone ke data se badlein"), role: .destructive) {
                store.chooseBackupFolder(choice.url)
            }
        } message: { choice in
            Text(L("The backup holds " + choice.existing.summary + ". This iPhone has " + store.localSummary
                   + ". Restore the backup here, or replace it with what is on this iPhone.",
                   "Backup mein " + choice.existing.summary + " hai. Is iPhone par " + store.localSummary
                   + " hai. Backup yahan wapas layein, ya use is iPhone ke data se badlein."))
        }
        .confirmationDialog(L("Turn off automatic backup?", "Automatic backup band karein?"), isPresented: $askStop, titleVisibility: .visible) {
            Button(L("Turn off", "Band karein"), role: .destructive) {
                store.stopAutoBackup()
            }
        } message: {
            Text(L("Files already in the backup folder are kept.", "Backup folder mein pehle se rakhi files rahengi."))
        }
        .alert(L("Couldn't use that", "Yeh use nahi ho paya"), isPresented: problemBinding) {
            Button(L("OK", "Theek hai"), role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private var lastBackupText: String {
        guard let last = store.backup.lastSuccess else { return L("Not yet", "Abhi nahi") }
        return Fmt.dateTime(last)
    }

    private var autoSection: some View {
        Section {
            if let folder = store.backup.folderName {
                LabeledContent(L("Backup folder", "Backup folder"), value: folder)
                LabeledContent(L("Last backup", "Aakhri backup"), value: lastBackupText)
                if store.backup.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L("Backing up…", "Backup ho raha hai…"))
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
                    Label(L("Back up now", "Abhi backup karein"), systemImage: "arrow.clockwise.icloud")
                }
                .disabled(store.backup.isRunning)
                Button {
                    choose(.folder)
                } label: {
                    Label(L("Choose a different folder", "Doosra folder chunein"), systemImage: "folder")
                }
                Button {
                    askStop = true
                } label: {
                    Label(L("Turn off automatic backup", "Automatic backup band karein"), systemImage: "icloud.slash")
                }
            } else {
                Button {
                    choose(.folder)
                } label: {
                    Label(L("Choose an iCloud Drive folder", "iCloud Drive folder chunein"), systemImage: "folder.badge.plus")
                }
                if let error = store.backup.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text(L("Automatic backup to iCloud Drive", "iCloud Drive mein automatic backup"))
        } footer: {
            Text(L("In the Files window, open iCloud Drive, make a folder (for example “RentBook”) and choose it. After every change RentBook saves a “RentBook Backup” folder there with all records, photos and documents, and keeps a dated copy for each of the last 30 days it backed up. Only you can see it.", "Files window mein iCloud Drive kholein, ek folder banayein (jaise “RentBook”) aur use chunein. Har badlav ke baad RentBook wahan “RentBook Backup” folder mein saare record, photo aur documents save karta hai, aur pichhle 30 backup dino ki tareekh wali copy rakhta hai. Ise sirf aap dekh sakte hain."))
        }
    }

    private var fileSection: some View {
        Section {
            Button {
                if let url = store.exportFullBackup() {
                    share = ShareItem(url: url)
                }
            } label: {
                Label(L("Export a full backup file", "Poori backup file export karein"), systemImage: "square.and.arrow.up")
            }
        } header: {
            Text(L("Backup file", "Backup file"))
        } footer: {
            Text(L("One file with every record, photo and document. Save it in Files or on a computer. Keep it private: it holds your tenants' details.", "Ek file jismein har record, photo aur document hai. Files ya computer mein save karein. Ise private rakhein: ismein tenants ki details hain."))
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                choose(.restoreFolder)
            } label: {
                Label(L("Restore from the backup folder", "Backup folder se restore karein"), systemImage: "folder")
            }
            Button {
                choose(.restoreFile)
            } label: {
                Label(L("Restore from a backup file", "Backup file se restore karein"), systemImage: "doc")
            }
        } header: {
            Text(L("Restore", "Restore"))
        } footer: {
            Text(L("For a new iPhone: install RentBook, then choose the folder that holds “RentBook Backup”. You'll see what the backup contains before anything is replaced. Data files from RentBook 1.0 can be restored too.", "Naye iPhone ke liye: RentBook install karein, phir “RentBook Backup” wala folder chunein. Kuch badalne se pehle aap dekh payenge ki backup mein kya hai. RentBook 1.0 ki data files bhi restore ho sakti hain."))
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
                        problem = L("The earlier copy couldn't be read.", "Pehle ki copy padhi nahi gayi.")
                    }
                } label: {
                    Label(L("Bring back the data from before the last erase or restore", "Aakhri mitane ya restore se pehle ka data wapas layein"), systemImage: "arrow.uturn.backward.circle")
                }
            } footer: {
                Text(L("Saved on this iPhone on " + Fmt.dateTime(saved) + ".", "Is iPhone par " + Fmt.dateTime(saved) + " ko save hua."))
            }
        }
    }

    private func choose(_ mode: ImportMode) {
        importMode = mode
        let types: [UTType]
        switch mode {
        case .folder, .restoreFolder: types = [.folder]
        case .restoreFile: types = [.json]
        }
        // A folder is opened where it is, so backups can keep being written to it; a backup
        // file is read from a copy.
        FilePicker.shared.pick(types, asCopy: mode == .restoreFile) { urls in
            handleImport(.success(urls))
        }
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

    private var beforeText: String {
        let n = store.settings.remindDaysBefore
        return L(SettingsText.plural(n, "day") + " before", "\(n) din pehle")
    }
    private var repeatText: String {
        let n = store.settings.overdueRepeatDays
        return L("Repeat every " + SettingsText.plural(n, "day"), "Har \(n) din mein dobara")
    }
    private var increaseText: String {
        let n = store.settings.increaseDaysBefore
        return L(SettingsText.plural(n, "day") + " before an increase", "Badhotri se \(n) din pehle")
    }
    private var agreementText: String {
        let n = store.settings.agreementDaysBefore
        return L("New agreements: " + SettingsText.plural(n, "day") + " before the end", "Naye agreement: khatam hone se \(n) din pehle")
    }

    var body: some View {
        Form {
            permissionSection
            Section(L("Time of day", "Din ka samay")) {
                DatePicker(L("Remind me at", "Kab yaad dilayein"), selection: timeBinding, displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle(L("Before the due date", "Due date se pehle"), isOn: store.setting(\.remindBeforeDue))
                if store.settings.remindBeforeDue {
                    Stepper(beforeText, value: store.setting(\.remindDaysBefore), in: 1...15)
                }
                Toggle(L("On the due date", "Due date par"), isOn: store.setting(\.remindOnDue))
                Toggle(L("When rent is overdue", "Jab rent overdue ho"), isOn: store.setting(\.remindOverdue))
                if store.settings.remindOverdue {
                    Stepper(repeatText, value: store.setting(\.overdueRepeatDays), in: 1...30)
                }
            } header: {
                Text("Rent")
            } footer: {
                Text(L("Rent counts as overdue after the grace period set in Defaults. Each tenant can have their own timing: open the tenant, tap Edit and look under Reminders.", "Defaults mein set grace period ke baad rent overdue mana jata hai. Har tenant ka alag samay ho sakta hai: tenant kholein, Edit dabayein aur Reminders dekhein."))
            }
            Section(L("Other reminders", "Doosre reminders")) {
                Toggle(L("Payment promises", "Payment ke vaade"), isOn: store.setting(\.remindPromises))
                Toggle(L("Follow-ups", "Follow-up"), isOn: store.setting(\.remindFollowUps))
                Toggle(L("Rent increases", "Rent badhotri"), isOn: store.setting(\.remindIncreases))
                if store.settings.remindIncreases {
                    Stepper(increaseText, value: store.setting(\.increaseDaysBefore), in: 1...90)
                }
                Toggle(L("Agreements ending", "Khatam hote agreements"), isOn: store.setting(\.remindAgreements))
                if store.settings.remindAgreements {
                    Stepper(agreementText, value: store.setting(\.agreementDaysBefore), in: 5...120, step: 5)
                }
                Toggle(L("Vacant units (Mondays)", "Khaali units (Somvaar)"), isOn: store.setting(\.remindVacant))
                Toggle(L("Deposits to settle (Mondays)", "Deposit ka hisaab (Somvaar)"), isOn: store.setting(\.remindDeposits))
                Toggle(L("Recurring expenses to review", "Review ke liye recurring kharche"), isOn: store.setting(\.remindRecurring))
            }
            Section {
                NavigationLink(value: Route.upcomingReminders) {
                    Text(L("See upcoming reminders", "Aane wale reminders dekhein"))
                }
            }
        }
        .navigationTitle(L("Reminders", "Reminders"))
        .onAppear {
            store.refreshNotificationStatus()
        }
    }

    private var permissionSection: some View {
        Section {
            LabeledContent(L("Notifications", "Notifications"), value: store.notificationStatus)
            if !store.notificationsAllowed {
                Button(L("Allow notifications", "Notifications chalu karein")) {
                    store.requestNotificationPermission()
                }
                Button(L("Open iPhone Settings", "iPhone Settings kholein")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } footer: {
            Text(L("Reminders are planned for the next 45 days and refreshed whenever you open RentBook. iPhone keeps up to 64 at a time, so open the app every few weeks.", "Reminders agle 45 din ke liye bante hain aur RentBook kholne par update hote hain. iPhone ek saath 64 tak rakhta hai, isliye kuch hafton mein app kholte rahein."))
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
                    Text(L("Notifications are off, so these won't appear. Turn them on in Settings → Reminders.", "Notifications band hain, isliye yeh nahi dikhenge. Settings → Reminders mein chalu karein."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if groups.isEmpty {
                Text(L("Nothing planned for the next 45 days.", "Agle 45 din ke liye kuch nahi."))
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
        .navigationTitle(L("Upcoming reminders", "Aane wale reminders"))
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
    @State private var electricityText = ""
    @State private var waterText = ""
    @State private var loaded = false

    private var graceText: String {
        let n = store.settings.gracePeriodDays
        return L("Grace period: " + SettingsText.plural(n, "day"), "Grace period: \(n) din")
    }
    private var everyText: String {
        let n = store.settings.defaultEscalationMonths
        return L("Every " + SettingsText.plural(n, "month"), "Har \(n) mahine")
    }
    private var valueLabel: String { store.settings.defaultEscalationMode == .percent ? L("Percentage", "Percent") : L("Amount (₹)", "Amount (₹)") }

    var body: some View {
        Form {
            Section {
                Picker(L("Rent due on", "Rent ki tareekh"), selection: store.setting(\.defaultDueDay)) {
                    ForEach(1...28, id: \.self) { day in
                        Text(L(Fmt.ordinal(day) + " of the month", "Mahine ki \(day) tareekh")).tag(day)
                    }
                }
                Toggle(L("Part-month rent at move-in and move-out", "Aane aur jaane par aadhe mahine ka rent"), isOn: store.setting(\.defaultProrate))
                Stepper(graceText, value: store.setting(\.gracePeriodDays), in: 0...30)
                Toggle(L("Settle the oldest dues first", "Pehle purana baaki chukayein"), isOn: store.setting(\.autoAllocate))
            } header: {
                Text("Rent")
            } footer: {
                Text(L("Due date and part-month rent apply to new tenants. Rent becomes overdue after the grace period. With “Settle the oldest dues first” off, the payment screen asks which months each payment is for.", "Due date aur part-month rent naye tenants par lagte hain. Grace period ke baad rent overdue hota hai. “Pehle purana baaki chukayein” band ho to payment screen poochegi har payment kis mahine ka hai."))
            }
            Section {
                Picker(L("Increase by", "Kitni badhotri"), selection: store.setting(\.defaultEscalationMode)) {
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
                Text(L("Rent increases for new tenants", "Naye tenants ke liye rent badhotri"))
            }
            chargesSection
            Section {
                rateField(L("Electricity, per unit", "Bijli, har unit"), $electricityText)
                rateField(L("Water, per unit", "Paani, har unit"), $waterText)
            } header: {
                Text(L("Electricity and water rates", "Bijli aur paani ke rate"))
            } footer: {
                Text(L("Used to bill meter readings, unless a tenant has their own rate. Saved when you leave this screen.",
                       "Meter reading ke bill ke liye, jab tak tenant ka alag rate na ho. Screen chhodne par save hota hai."))
            }
            Section {
                TextField(L("Your name", "Aapka naam"), text: $landlordName)
                    .textContentType(.name)
                TextField(L("Your mobile number", "Aapka mobile number"), text: $landlordPhone)
                    .keyboardType(.phonePad)
            } header: {
                Text(L("On receipts and messages", "Raseed aur messages par"))
            } footer: {
                Text(L("Shown on PDF receipts and at the end of WhatsApp messages. Saved when you leave this screen.", "PDF raseed par aur WhatsApp messages ke ant mein dikhta hai. Screen chhodne par save hota hai."))
            }
            Section(L("Numbering", "Numbering")) {
                LabeledContent(L("Next receipt number", "Agla raseed number"), value: "\(store.settings.nextReceiptNumber)")
                LabeledContent(L("Next property ID", "Agli property ID"), value: store.nextPropertyCode())
            }
        }
        .navigationTitle(L("Defaults", "Defaults"))
        .keyboardDoneButton()
        .onAppear(perform: load)
        .onDisappear(perform: saveText)
    }

    private var chargesSection: some View {
        Section {
            ForEach(store.settings.defaultRecurringCharges) { rc in
                LabeledContent(rc.title, value: Fmt.inr(rc.amount) + L(" / month", " / mahina"))
            }
            .onDelete { offsets in
                store.change { d in
                    d.settings.defaultRecurringCharges.remove(atOffsets: offsets)
                }
            }
            HStack {
                TextField(L("Name, e.g. Maintenance", "Naam, jaise Maintenance"), text: $chargeTitle)
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
            Text(L("Monthly extras for new tenants", "Naye tenants ke mahine ke extra"))
        } footer: {
            Text(L("Added to each new tenant, for example maintenance or parking. Swipe left to remove one.", "Har naye tenant mein judta hai, jaise maintenance ya parking. Hatane ke liye left swipe karein."))
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        landlordName = store.settings.landlordName
        landlordPhone = store.settings.landlordPhone
        escalationText = Fmt.number(store.settings.defaultEscalationValue)
        electricityText = store.settings.defaultElectricityRate > 0 ? Fmt.number(store.settings.defaultElectricityRate) : ""
        waterText = store.settings.defaultWaterRate > 0 ? Fmt.number(store.settings.defaultWaterRate) : ""
    }

    private func rateField(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("₹").foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func saveText() {
        let name = landlordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = landlordPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parseDecimal(escalationText)
        let electricity = max(0, parseDecimal(electricityText) ?? 0)
        let water = max(0, parseDecimal(waterText) ?? 0)
        let s = store.settings
        let changed = name != s.landlordName || phone != s.landlordPhone || (value != nil && value != s.defaultEscalationValue)
            || electricity != s.defaultElectricityRate || water != s.defaultWaterRate
        guard changed else { return }
        store.change { d in
            d.settings.landlordName = name
            d.settings.landlordPhone = phone
            if let v = value, v > 0 {
                d.settings.defaultEscalationValue = v
            }
            d.settings.defaultElectricityRate = electricity
            d.settings.defaultWaterRate = water
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
                Text(L("Nothing is archived.", "Kuch archive nahi hai."))
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
        .navigationTitle(L("Archived", "Archive"))
        .confirmationDialog(L("Delete permanently?", "Hamesha ke liye delete karein?"), isPresented: pendingBinding, titleVisibility: .visible) {
            Button(L("Delete permanently", "Hamesha ke liye delete karein"), role: .destructive) {
                if let item = pending {
                    delete(item)
                }
                pending = nil
            }
        } message: {
            Text(L("This can't be undone. Attached photos and documents are deleted too. You may want to export a backup first.", "Yeh wapas nahi hoga. Jude photo aur documents bhi delete honge. Pehle backup export kar lena achha rahega."))
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
                        Label(L("Restore", "Restore"), systemImage: "arrow.uturn.backward")
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
            Text(L("Swipe left to restore or delete.", "Restore ya delete ke liye left swipe karein."))
        }
    }

    private func propertySection(_ properties: [RentalProperty]) -> some View {
        Section(L("Properties", "Properties")) {
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
                        Label(L("Restore", "Restore"), systemImage: "arrow.uturn.backward")
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
        Section(L("Expenses", "Kharche")) {
            ForEach(expenses) { e in
                NavigationLink(value: Route.expense(e.id)) {
                    ExpenseRow(expense: e, place: ExpensePlace.text(e, store: store))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        store.setExpenseArchived(e.id, false)
                    } label: {
                        Label(L("Restore", "Restore"), systemImage: "arrow.uturn.backward")
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
                    Text(query.isEmpty ? L("No changes recorded yet.", "Abhi koi badlav record nahi.") : L("No changes match.", "Aisa koi badlav nahi mila."))
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
                Text(L("Payments, rent changes, deposits, archiving and restores are recorded here. The latest 3,000 changes are kept.", "Payment, rent badlav, deposit, archive aur restore yahan record hote hain. Aakhri 3,000 badlav rakhe jaate hain."))
            }
        }
        .searchable(text: $query, prompt: L("Search changes", "Badlav dhoondhein"))
        .navigationTitle(L("Change history", "Badlav ki history"))
    }
}
