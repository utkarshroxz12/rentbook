//  AppStore.swift
//  Keeps RentBook's data on the iPhone, saves every change, backs up to an
//  iCloud Drive folder, stores photos and documents, and schedules reminders.

import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct BackupState: Equatable {
    var folderName: String? = nil
    var lastSuccess: Date? = nil
    var lastError: String? = nil
    var isRunning = false
}

struct RestorePreview: Identifiable {
    let id = UUID()
    var data: AppData
    var files: [EmbeddedFile]
    var stagedAttachments: URL?
    var fromVersion1: Bool

    var summary: String {
        let t = data.tenants.count
        let p = data.properties.count
        var s = "\(t) tenant" + (t == 1 ? "" : "s") + " and \(p) propert" + (p == 1 ? "y" : "ies")
        s += ", last changed " + Fmt.dateTime(data.lastModified)
        if fromVersion1 { s += " (from RentBook 1.0)" }
        return s
    }
}

final class Store: ObservableObject {
    @Published private(set) var data: AppData
    @Published var backup = BackupState()
    @Published var saveError: String? = nil
    @Published var notificationStatus = "Checking…"
    @Published var notificationsAllowed = false
    @Published var upcomingReminders: [PlannedReminder] = []

    let attachmentsDir: URL
    private let dataURL: URL
    private let previousURL: URL
    private let legacyURL: URL
    private let safetyURL: URL
    private var backupWork: DispatchWorkItem?
    private var reminderWork: DispatchWorkItem?
    private var cachedSnapshot: PortfolioSnapshot?
    private var cachedDay: Date?

    static let backupFolderName = "RentBook Backup"
    static let backupDataName = "RentBook-Data.json"
    private static let bookmarkKey = "rentbook.backupFolderBookmark"
    private static let folderNameKey = "rentbook.backupFolderName"
    private static let lastBackupKey = "rentbook.lastBackup"

    init() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dataURL = documents.appendingPathComponent("rentbook-v2.json")
        previousURL = documents.appendingPathComponent("rentbook-v2-previous.json")
        legacyURL = documents.appendingPathComponent("rentbook-data.json")
        safetyURL = documents.appendingPathComponent("rentbook-before-restore.json")
        attachmentsDir = documents.appendingPathComponent("Attachments", isDirectory: true)
        try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        var loaded: AppData? = nil
        var problem: String? = nil
        var needsSave = false
        if fm.fileExists(atPath: dataURL.path) {
            if let raw = try? Data(contentsOf: dataURL), let decoded = try? BackupCodec.decode(raw) {
                loaded = decoded.data
            } else {
                // Keep the unreadable save aside so nothing written later replaces it.
                let stamp = DateMath.dayKey(Date()) + "-" + String(Int(Date().timeIntervalSince1970))
                try? fm.copyItem(at: dataURL, to: documents.appendingPathComponent("rentbook-unreadable-" + stamp + ".json"))
                if let raw = try? Data(contentsOf: previousURL), let decoded = try? BackupCodec.decode(raw) {
                    loaded = decoded.data
                    needsSave = true
                    problem = "Your latest save could not be read, so the save before it was opened. Check your most recent entries."
                } else {
                    problem = "Your saved data could not be read. A copy was kept on this iPhone. Restore your records from Settings → Backup."
                }
            }
        } else if fm.fileExists(atPath: legacyURL.path) {
            // First launch of version 2: move the data over from RentBook 1.0. The old file is kept.
            if let raw = try? Data(contentsOf: legacyURL), let decoded = try? BackupCodec.decode(raw) {
                loaded = decoded.data
                needsSave = true
            } else {
                problem = "Your RentBook 1.0 data could not be read. It is still on this iPhone. Restore a backup from Settings → Backup."
            }
        }
        data = loaded ?? AppData()
        saveError = problem
        backup.folderName = UserDefaults.standard.string(forKey: Store.folderNameKey)
        backup.lastSuccess = UserDefaults.standard.object(forKey: Store.lastBackupKey) as? Date
        if needsSave {
            persist(backUp: false)
        } else {
            refreshReminders()
        }
    }

    // MARK: - Reading

    var settings: AppSettings { data.settings }

    var snapshot: PortfolioSnapshot {
        let today = DateMath.day(Date())
        if let cached = cachedSnapshot, cachedDay == today { return cached }
        let fresh = Portfolio.snapshot(data, asOf: today)
        cachedSnapshot = fresh
        cachedDay = today
        return fresh
    }

    var activeProperties: [RentalProperty] {
        data.properties.filter { !$0.isArchived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var liveTenants: [Tenant] {
        data.tenants.filter { Portfolio.isLive($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func tenant(_ id: UUID) -> Tenant? {
        data.tenants.first { $0.id == id }
    }

    func property(_ id: UUID?) -> RentalProperty? {
        guard let id = id else { return nil }
        return data.properties.first { $0.id == id }
    }

    func expense(_ id: UUID) -> Expense? {
        data.expenses.first { $0.id == id }
    }

    func attachment(_ id: UUID) -> AttachmentMeta? {
        data.attachments.first { $0.id == id }
    }

    func fileURL(_ meta: AttachmentMeta) -> URL {
        attachmentsDir.appendingPathComponent(meta.fileName)
    }

    func place(of t: Tenant) -> String {
        guard let p = property(t.propertyID) else { return "" }
        let unit = Portfolio.unitName(t.unitID, in: p)
        return unit.isEmpty ? p.name : unit + ", " + p.name
    }

    /// The tenant's ledger for today (cached until the data changes).
    func ledger(of id: UUID) -> TenantLedger? {
        if let cached = snapshot.ledgers[id] { return cached }
        guard let t = tenant(id) else { return nil }
        return Ledger.ledger(for: t, graceDays: settings.gracePeriodDays)
    }

    func freshLedger(for t: Tenant) -> TenantLedger {
        Ledger.ledger(for: t, graceDays: settings.gracePeriodDays)
    }

    // MARK: - Writing

    /// Every change goes through here: it is saved at once, noted in the change
    /// history when an action is given, backed up and the reminders refreshed.
    func change(_ action: String = "", details: String = "", tenant: UUID? = nil, property: UUID? = nil,
                _ edit: (inout AppData) -> Void) {
        var copy = data
        edit(&copy)
        if !action.isEmpty {
            copy.audit.insert(AuditEntry(date: Date(), tenantID: tenant, propertyID: property, action: action, details: details), at: 0)
            if copy.audit.count > 3000 {
                copy.audit.removeLast(copy.audit.count - 3000)
            }
        }
        copy.lastModified = Date()
        data = copy
        persist(backUp: true)
    }

    func updateTenant(_ id: UUID, log action: String = "", details: String = "", _ edit: (inout Tenant) -> Void) {
        change(action, details: details, tenant: id) { d in
            guard let i = d.tenants.firstIndex(where: { $0.id == id }) else { return }
            edit(&d.tenants[i])
        }
    }

    func updateProperty(_ id: UUID, log action: String = "", details: String = "", _ edit: (inout RentalProperty) -> Void) {
        change(action, details: details, property: id) { d in
            guard let i = d.properties.firstIndex(where: { $0.id == id }) else { return }
            edit(&d.properties[i])
        }
    }

    func updateExpense(_ id: UUID, log action: String = "", details: String = "", _ edit: (inout Expense) -> Void) {
        change(action, details: details) { d in
            guard let i = d.expenses.firstIndex(where: { $0.id == id }) else { return }
            edit(&d.expenses[i])
        }
    }

    func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.data.settings[keyPath: keyPath] },
            set: { newValue in self.change { $0.settings[keyPath: keyPath] = newValue } }
        )
    }

    func saveTenant(_ t: Tenant, isNew: Bool, changes: String = "") {
        var tenant = t
        if !isNew, let old = self.tenant(t.id), old.propertyID != nil,
           old.propertyID != t.propertyID || old.unitID != t.unitID {
            let from = old.assignments.last?.to ?? old.startDate ?? old.createdAt
            tenant.assignments.append(UnitAssignment(propertyID: old.propertyID, unitID: old.unitID, from: from, to: Date()))
        }
        let details = tenant.name + (changes.isEmpty ? "" : ": " + changes)
        change(isNew ? "Tenant added" : "Tenant updated", details: details, tenant: tenant.id) { d in
            if let i = d.tenants.firstIndex(where: { $0.id == tenant.id }) {
                d.tenants[i] = tenant
            } else {
                d.tenants.append(tenant)
            }
        }
    }

    func nextPropertyCode() -> String {
        let n = max(settings.nextPropertyNumber, data.properties.count + 1)
        let digits = String(n)
        return "P" + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }

    func saveProperty(_ p: RentalProperty, isNew: Bool) {
        change(isNew ? "Property added" : "Property updated", details: p.name, property: p.id) { d in
            if let i = d.properties.firstIndex(where: { $0.id == p.id }) {
                d.properties[i] = p
            } else {
                d.properties.append(p)
                d.settings.nextPropertyNumber = max(d.settings.nextPropertyNumber, d.properties.count) + 1
            }
        }
    }

    func saveExpense(_ e: Expense, isNew: Bool) {
        let details = e.category.label + " · " + Fmt.inr(e.amount) + (e.vendor.isEmpty ? "" : " · " + e.vendor)
        change(isNew ? "Expense added" : "Expense updated", details: details, property: e.propertyID) { d in
            if let i = d.expenses.firstIndex(where: { $0.id == e.id }) {
                d.expenses[i] = e
            } else {
                d.expenses.append(e)
            }
        }
    }

    // MARK: Payments

    @discardableResult
    func recordPayment(_ payment: Payment, tenantID: UUID) -> Payment {
        var p = payment
        p.createdAt = Date()
        if p.kind == .payment {
            p.receiptNumber = settings.nextReceiptNumber
        }
        let name = tenant(tenantID)?.name ?? ""
        let action = p.kind == .refund ? "Refund recorded" : "Payment recorded"
        let details = name + ": " + Fmt.inr(p.amount) + " on " + Fmt.date(p.date) + " (" + p.method.label + ")"
        change(action, details: details, tenant: tenantID) { d in
            if p.kind == .payment {
                d.settings.nextReceiptNumber += 1
            }
            if let i = d.tenants.firstIndex(where: { $0.id == tenantID }) {
                d.tenants[i].payments.append(p)
            }
        }
        return p
    }

    func editPayment(_ updated: Payment, tenantID: UUID) {
        guard let t = tenant(tenantID), let old = t.payments.first(where: { $0.id == updated.id }) else { return }
        var changes: [String] = []
        if old.amount != updated.amount { changes.append("amount " + Fmt.inr(old.amount) + " → " + Fmt.inr(updated.amount)) }
        if DateMath.day(old.date) != DateMath.day(updated.date) { changes.append("date " + Fmt.date(old.date) + " → " + Fmt.date(updated.date)) }
        if old.method != updated.method { changes.append("method " + old.method.label + " → " + updated.method.label) }
        if old.reference != updated.reference { changes.append("reference changed") }
        if old.note != updated.note { changes.append("note changed") }
        if old.manualAllocations != updated.manualAllocations { changes.append("months changed") }
        var p = updated
        p.editedAt = Date()
        let number = p.receiptNumber > 0 ? " #\(p.receiptNumber)" : ""
        let details = t.name + number + ": " + (changes.isEmpty ? "no changes" : changes.joined(separator: ", "))
        updateTenant(tenantID, log: "Payment edited", details: details) { tenant in
            if let i = tenant.payments.firstIndex(where: { $0.id == p.id }) {
                tenant.payments[i] = p
            }
            // A payment taken from the deposit keeps its deposit entry in step.
            for j in tenant.deposits.indices where tenant.deposits[j].linkedPaymentID == p.id {
                tenant.deposits[j].amount = p.amount
                tenant.deposits[j].date = DateMath.day(p.date)
            }
        }
    }

    func reversePayment(_ id: UUID, tenantID: UUID, reason: String) {
        guard let t = tenant(tenantID), let p = t.payments.first(where: { $0.id == id }) else { return }
        let details = t.name + ": " + Fmt.inr(p.amount) + " on " + Fmt.date(p.date) + (reason.isEmpty ? "" : " (" + reason + ")")
        updateTenant(tenantID, log: "Payment reversed", details: details) { tenant in
            if let i = tenant.payments.firstIndex(where: { $0.id == id }) {
                tenant.payments[i].isReversed = true
                tenant.payments[i].reversalReason = reason
            }
            // A payment taken from the deposit puts the money back in the deposit.
            for j in tenant.deposits.indices where tenant.deposits[j].linkedPaymentID == id {
                tenant.deposits[j].isReversed = true
            }
        }
    }

    func applyDepositToRent(tenantID: UUID, amount: Int, date: Date, note: String) {
        guard amount > 0 else { return }
        var p = Payment()
        p.amount = amount
        p.date = date
        p.method = .deposit
        p.note = note.isEmpty ? "Adjusted from the security deposit" : note
        p.receiptNumber = settings.nextReceiptNumber
        p.createdAt = Date()
        let entry = DepositEntry(kind: .deduction, date: date, amount: amount, reason: "Adjusted against rent", linkedPaymentID: p.id)
        let name = tenant(tenantID)?.name ?? ""
        change("Deposit used for rent", details: name + ": " + Fmt.inr(amount), tenant: tenantID) { d in
            d.settings.nextReceiptNumber += 1
            if let i = d.tenants.firstIndex(where: { $0.id == tenantID }) {
                d.tenants[i].payments.append(p)
                d.tenants[i].deposits.append(entry)
            }
        }
    }

    // MARK: Archive and delete

    func setTenantArchived(_ id: UUID, _ archived: Bool) {
        updateTenant(id, log: archived ? "Tenant archived" : "Tenant restored", details: tenant(id)?.name ?? "") { t in
            t.isArchived = archived
        }
    }

    func deleteTenant(_ id: UUID) {
        guard let t = tenant(id) else { return }
        var files = t.documentIDs
        files += t.payments.flatMap { $0.attachmentIDs }
        files += t.agreements.flatMap { $0.attachmentIDs }
        if let photo = t.photoID { files.append(photo) }
        change("Tenant deleted", details: t.name) { d in
            d.tenants.removeAll { $0.id == id }
        }
        for file in files { deleteAttachment(file) }
    }

    func setPropertyArchived(_ id: UUID, _ archived: Bool) {
        updateProperty(id, log: archived ? "Property archived" : "Property restored", details: property(id)?.name ?? "") { p in
            p.isArchived = archived
        }
    }

    func deleteProperty(_ id: UUID) {
        guard let p = property(id) else { return }
        let files = p.photoIDs + p.documentIDs
        change("Property deleted", details: p.name) { d in
            d.properties.removeAll { $0.id == id }
            for i in d.tenants.indices where d.tenants[i].propertyID == id {
                d.tenants[i].propertyID = nil
                d.tenants[i].unitID = nil
            }
            for i in d.expenses.indices where d.expenses[i].propertyID == id {
                d.expenses[i].propertyID = nil
                d.expenses[i].unitID = nil
            }
        }
        for file in files { deleteAttachment(file) }
    }

    func setExpenseArchived(_ id: UUID, _ archived: Bool) {
        guard let e = expense(id) else { return }
        let details = e.category.label + " · " + Fmt.inr(e.amount) + (e.vendor.isEmpty ? "" : " · " + e.vendor)
        change(archived ? "Expense archived" : "Expense restored", details: details, property: e.propertyID) { d in
            if let i = d.expenses.firstIndex(where: { $0.id == id }) {
                d.expenses[i].isArchived = archived
            }
        }
    }

    func deleteExpense(_ id: UUID) {
        guard let e = expense(id) else { return }
        let details = e.category.label + " · " + Fmt.inr(e.amount) + (e.vendor.isEmpty ? "" : " · " + e.vendor)
        change("Expense deleted", details: details, property: e.propertyID) { d in
            d.expenses.removeAll { $0.id == id }
        }
        for file in e.attachmentIDs { deleteAttachment(file) }
    }

    // MARK: Attachments

    @discardableResult
    func addAttachment(_ raw: Data, ext: String, name: String, kind: AttachmentKind, category: String) -> UUID? {
        let id = UUID()
        let fileName = id.uuidString + "." + (ext.isEmpty ? "dat" : ext)
        do {
            try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            try raw.write(to: attachmentsDir.appendingPathComponent(fileName),
                          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            saveError = "Couldn't save the file: " + error.localizedDescription
            return nil
        }
        let meta = AttachmentMeta(id: id, fileName: fileName, originalName: name, kind: kind, category: category,
                                  addedAt: Date(), byteCount: raw.count)
        change { d in d.attachments.append(meta) }
        return id
    }

    func importAttachment(from url: URL, category: String) -> UUID? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else {
            saveError = "Couldn't read that file."
            return nil
        }
        let ext = url.pathExtension.lowercased()
        let isImage = UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
        return addAttachment(raw, ext: ext, name: url.lastPathComponent, kind: isImage ? .photo : .document, category: category)
    }

    func deleteAttachment(_ id: UUID) {
        if let meta = attachment(id) {
            try? FileManager.default.removeItem(at: fileURL(meta))
        }
        change { d in
            d.attachments.removeAll { $0.id == id }
            for i in d.tenants.indices {
                d.tenants[i].documentIDs.removeAll { $0 == id }
                if d.tenants[i].photoID == id { d.tenants[i].photoID = nil }
                for j in d.tenants[i].payments.indices {
                    d.tenants[i].payments[j].attachmentIDs.removeAll { $0 == id }
                }
                for j in d.tenants[i].agreements.indices {
                    d.tenants[i].agreements[j].attachmentIDs.removeAll { $0 == id }
                }
            }
            for i in d.properties.indices {
                d.properties[i].photoIDs.removeAll { $0 == id }
                d.properties[i].documentIDs.removeAll { $0 == id }
            }
            for i in d.expenses.indices {
                d.expenses[i].attachmentIDs.removeAll { $0 == id }
            }
        }
    }

    func writeTemporary(_ text: String, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            saveError = "Couldn't create the file: " + error.localizedDescription
            return nil
        }
    }

    // MARK: Sample data and erasing

    var isEmpty: Bool { data.tenants.isEmpty && data.properties.isEmpty && data.expenses.isEmpty }

    func loadSampleData() {
        guard isEmpty else { return }
        let sample = SampleData.make()
        change("Sample data loaded", details: "Made-up properties and tenants for trying the app") { d in
            d.properties = sample.properties
            d.tenants = sample.tenants
            d.expenses = sample.expenses
            d.settings.nextReceiptNumber = sample.settings.nextReceiptNumber
            d.settings.nextPropertyNumber = sample.settings.nextPropertyNumber
        }
    }

    /// Erases every record. Automatic backup is turned off first so the iCloud Drive
    /// backup is left untouched, and the photos and documents are moved aside so
    /// "bring back" in Backup can restore everything.
    func eraseAll() {
        guard writeSafetyCopy() else {
            saveError = "A safety copy couldn't be saved, so nothing was erased."
            return
        }
        stopAutoBackup()
        let fm = FileManager.default
        try? fm.removeItem(at: erasedFilesDir)
        if (try? fm.moveItem(at: attachmentsDir, to: erasedFilesDir)) == nil,
           let names = try? fm.contentsOfDirectory(atPath: attachmentsDir.path) {
            for name in names {
                try? fm.removeItem(at: attachmentsDir.appendingPathComponent(name))
            }
        }
        try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        change("All data erased", details: "A copy was kept on this iPhone") { d in
            let keep = d.settings
            d = AppData()
            d.settings = keep
        }
    }

    private var erasedFilesDir: URL {
        attachmentsDir.deletingLastPathComponent().appendingPathComponent("Attachments-erased", isDirectory: true)
    }

    /// Keeps a copy of the current data before an erase or restore. Empty data is not
    /// copied, so an earlier copy is never replaced by nothing.
    @discardableResult
    private func writeSafetyCopy() -> Bool {
        guard !isEmpty else { return true }
        guard let raw = try? BackupCodec.encoder.encode(data) else { return false }
        do {
            try raw.write(to: safetyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// "3 tenants and 2 properties" for messages about replacing data.
    var localSummary: String {
        let t = data.tenants.count
        let p = data.properties.count
        return "\(t) tenant" + (t == 1 ? "" : "s") + " and \(p) propert" + (p == 1 ? "y" : "ies")
    }

    /// When the copy kept before the last erase or restore was saved, if there is one.
    var safetyCopyDate: Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: safetyURL.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    func safetyCopyPreview() -> RestorePreview? {
        guard let raw = try? Data(contentsOf: safetyURL), let decoded = try? BackupCodec.decode(raw) else { return nil }
        return RestorePreview(data: decoded.data, files: [], stagedAttachments: nil, fromVersion1: decoded.fromVersion1)
    }

    /// Brings back the data from before the last erase or restore. The current data
    /// becomes the new safety copy, so this can be undone the same way.
    func restoreSafetyCopy(_ preview: RestorePreview) {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: erasedFilesDir.path) {
            try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            for name in names {
                let target = attachmentsDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: target.path) {
                    try? fm.moveItem(at: erasedFilesDir.appendingPathComponent(name), to: target)
                }
            }
        }
        writeSafetyCopy()
        var restored = preview.data
        restored.settings.nextReceiptNumber = max(restored.settings.nextReceiptNumber, data.settings.nextReceiptNumber)
        let finished = restored
        change("Earlier data brought back", details: preview.summary) { d in
            d = finished
        }
    }

    // MARK: - Saving

    private func persist(backUp: Bool) {
        do {
            let raw = try BackupCodec.encoder.encode(data)
            let fm = FileManager.default
            if fm.fileExists(atPath: dataURL.path) {
                try? fm.removeItem(at: previousURL)
                try? fm.copyItem(at: dataURL, to: previousURL)
            }
            try raw.write(to: dataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            saveError = "Couldn't save: " + error.localizedDescription
        }
        cachedSnapshot = nil
        if backUp { scheduleAutoBackup() }
        refreshReminders()
    }

    func appBecameActive() {
        cachedSnapshot = nil
        objectWillChange.send()
        refreshNotificationStatus()
        refreshReminders()
        if let last = backup.lastSuccess, Date().timeIntervalSince(last) < 12 * 3600 { return }
        backupNow()
    }

    // MARK: - iCloud Drive backup

    var hasBackupFolder: Bool {
        UserDefaults.standard.data(forKey: Store.bookmarkKey) != nil
    }

    private func scheduleAutoBackup() {
        guard hasBackupFolder else { return }
        backupWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.backupNow() }
        backupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// The backup already inside a folder the user is about to choose, if it holds any records.
    func existingBackup(in url: URL) -> RestorePreview? {
        guard let preview = try? prepareRestore(fromFolder: url) else { return nil }
        let d = preview.data
        if d.tenants.isEmpty && d.properties.isEmpty && d.expenses.isEmpty {
            if let staged = preview.stagedAttachments {
                try? FileManager.default.removeItem(at: staged)
            }
            return nil
        }
        return preview
    }

    func chooseBackupFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Store.bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Store.folderNameKey)
            backup.folderName = url.lastPathComponent
            backup.lastError = nil
        } catch {
            backup.lastError = "Couldn't use that folder: " + error.localizedDescription
            return
        }
        backupNow()
    }

    func stopAutoBackup() {
        UserDefaults.standard.removeObject(forKey: Store.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Store.folderNameKey)
        backup.folderName = nil
        backup.lastError = nil
    }

    private func resolveBackupFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Store.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            let access = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Store.bookmarkKey)
            }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    func backupNow() {
        guard hasBackupFolder else { return }
        guard let folder = resolveBackupFolder() else {
            backup.lastError = "The backup folder can't be reached. Choose it again."
            return
        }
        if backup.isRunning {
            scheduleAutoBackup()
            return
        }
        backup.isRunning = true
        let snapshot = data
        let source = attachmentsDir
        DispatchQueue.global(qos: .utility).async {
            let failure = Store.writeBackup(snapshot, attachments: source, into: folder)
            DispatchQueue.main.async {
                self.backup.isRunning = false
                if let failure = failure {
                    self.backup.lastError = failure
                } else {
                    let now = Date()
                    self.backup.lastError = nil
                    self.backup.lastSuccess = now
                    UserDefaults.standard.set(now, forKey: Store.lastBackupKey)
                }
            }
        }
    }

    /// Writes the data file, a dated copy (the last 30 are kept) and any new attachments.
    private static func writeBackup(_ snapshot: AppData, attachments: URL, into folder: URL) -> String? {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var failure: String? = nil
        var coordinationError: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { dir in
            do {
                let fm = FileManager.default
                // Choosing the "RentBook Backup" folder itself works too.
                let base = folder.lastPathComponent == Store.backupFolderName
                    ? dir : dir.appendingPathComponent(Store.backupFolderName, isDirectory: true)
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                let target = base.appendingPathComponent(Store.backupDataName)
                if Store.hasNoRecords(snapshot), let existing = try? Data(contentsOf: target),
                   let decoded = try? BackupCodec.decode(existing), !Store.hasNoRecords(decoded.data) {
                    failure = "Backup paused: this iPhone has no records but the backup folder has some. Restore them in Settings → Backup."
                    return
                }
                let raw = try BackupCodec.encoder.encode(snapshot)
                try raw.write(to: target, options: .atomic)

                let history = base.appendingPathComponent("History", isDirectory: true)
                try fm.createDirectory(at: history, withIntermediateDirectories: true)
                try raw.write(to: history.appendingPathComponent("RentBook-" + DateMath.dayKey(Date()) + ".json"), options: .atomic)
                let dated = ((try? fm.contentsOfDirectory(atPath: history.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
                if dated.count > 30 {
                    for name in dated.prefix(dated.count - 30) {
                        try? fm.removeItem(at: history.appendingPathComponent(name))
                    }
                }

                let files = base.appendingPathComponent("Attachments", isDirectory: true)
                try fm.createDirectory(at: files, withIntermediateDirectories: true)
                for meta in snapshot.attachments {
                    let target = files.appendingPathComponent(meta.fileName)
                    if !fm.fileExists(atPath: target.path) {
                        try? fm.copyItem(at: attachments.appendingPathComponent(meta.fileName), to: target)
                    }
                }
            } catch {
                failure = error.localizedDescription
            }
        }
        if let error = coordinationError { return error.localizedDescription }
        return failure
    }

    static func hasNoRecords(_ d: AppData) -> Bool {
        d.tenants.isEmpty && d.properties.isEmpty && d.expenses.isEmpty
    }

    /// One file with every record and every photo and document, for sharing or keeping elsewhere.
    func exportFullBackup() -> URL? {
        var files: [EmbeddedFile] = []
        for meta in data.attachments {
            if let raw = try? Data(contentsOf: fileURL(meta)) {
                files.append(EmbeddedFile(id: meta.id, fileName: meta.fileName, base64: raw.base64EncodedString()))
            }
        }
        do {
            let raw = try BackupCodec.package(data, files: files)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("RentBook Backup " + DateMath.dayKey(Date()) + ".json")
            try raw.write(to: url, options: .atomic)
            return url
        } catch {
            saveError = "Couldn't create the backup: " + error.localizedDescription
            return nil
        }
    }

    // MARK: - Restore

    func prepareRestore(fromFile url: URL) throws -> RestorePreview {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var raw: Data? = nil
        var coordinationError: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            raw = try? Data(contentsOf: readable)
        }
        guard let bytes = raw else { throw BackupError.unrecognised }
        let decoded = try BackupCodec.decode(bytes)
        return RestorePreview(data: decoded.data, files: decoded.files, stagedAttachments: nil, fromVersion1: decoded.fromVersion1)
    }

    /// Accepts the "RentBook Backup" folder itself or the folder that contains it.
    func prepareRestore(fromFolder url: URL) throws -> RestorePreview {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        var base = url
        if !fm.fileExists(atPath: base.appendingPathComponent(Store.backupDataName).path) {
            base = url.appendingPathComponent(Store.backupFolderName, isDirectory: true)
        }
        let coordinator = NSFileCoordinator()
        var raw: Data? = nil
        var coordinationError: NSError? = nil
        coordinator.coordinate(readingItemAt: base.appendingPathComponent(Store.backupDataName), options: [], error: &coordinationError) { readable in
            raw = try? Data(contentsOf: readable)
        }
        guard let bytes = raw else { throw BackupError.unrecognised }
        let decoded = try BackupCodec.decode(bytes)

        // Copy the attachments now, while the folder is open to the app.
        let staging = fm.temporaryDirectory.appendingPathComponent("Restore-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let source = base.appendingPathComponent("Attachments", isDirectory: true)
        for meta in decoded.data.attachments {
            var fileError: NSError? = nil
            coordinator.coordinate(readingItemAt: source.appendingPathComponent(meta.fileName), options: [], error: &fileError) { readable in
                try? fm.copyItem(at: readable, to: staging.appendingPathComponent(meta.fileName))
            }
        }
        return RestorePreview(data: decoded.data, files: decoded.files, stagedAttachments: staging, fromVersion1: decoded.fromVersion1)
    }

    func applyRestore(_ preview: RestorePreview) {
        guard writeSafetyCopy() else {
            saveError = "A safety copy of your current data couldn't be saved, so nothing was restored."
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        for file in preview.files {
            if let raw = Data(base64Encoded: file.base64) {
                try? raw.write(to: attachmentsDir.appendingPathComponent(file.fileName),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        if let staged = preview.stagedAttachments, let names = try? fm.contentsOfDirectory(atPath: staged.path) {
            for name in names {
                let target = attachmentsDir.appendingPathComponent(name)
                try? fm.removeItem(at: target)
                try? fm.copyItem(at: staged.appendingPathComponent(name), to: target)
            }
            try? fm.removeItem(at: staged)
        }
        var restored = preview.data
        let current = data.settings
        if preview.fromVersion1 {
            // RentBook 1.0 had no settings, so keep this iPhone's.
            let receipts = restored.settings.nextReceiptNumber
            let properties = restored.settings.nextPropertyNumber
            restored.settings = current
            restored.settings.nextReceiptNumber = receipts
            restored.settings.nextPropertyNumber = properties
        }
        // Never hand out a receipt number that was already used.
        restored.settings.nextReceiptNumber = max(restored.settings.nextReceiptNumber, current.nextReceiptNumber)
        restored.settings.nextPropertyNumber = max(restored.settings.nextPropertyNumber, current.nextPropertyNumber)
        fetchMissingAttachments(restored.attachments)
        let finished = restored
        change("Data restored", details: preview.summary) { d in
            d = finished
        }
    }

    /// Copies photos and documents the restored records need from the backup folder
    /// when they are not on this iPhone yet (after restoring a single data file).
    private func fetchMissingAttachments(_ metas: [AttachmentMeta]) {
        let fm = FileManager.default
        let missing = metas.filter { !fm.fileExists(atPath: fileURL($0).path) }
        guard !missing.isEmpty, let folder = resolveBackupFolder() else { return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let base = folder.lastPathComponent == Store.backupFolderName
            ? folder : folder.appendingPathComponent(Store.backupFolderName, isDirectory: true)
        let source = base.appendingPathComponent("Attachments", isDirectory: true)
        let coordinator = NSFileCoordinator()
        for meta in missing {
            let target = fileURL(meta)
            var fileError: NSError? = nil
            coordinator.coordinate(readingItemAt: source.appendingPathComponent(meta.fileName), options: [], error: &fileError) { readable in
                try? fm.copyItem(at: readable, to: target)
            }
        }
    }

    // MARK: - Reminders

    func refreshReminders() {
        reminderWork?.cancel()
        let snapshot = data
        let work = DispatchWorkItem { [weak self] in
            let plan = ReminderPlanner.plan(snapshot)
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                var parts = rbCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                parts.calendar = rbCalendar
                parts.timeZone = rbCalendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger), withCompletionHandler: nil)
            }
            DispatchQueue.main.async {
                self?.upcomingReminders = plan
            }
        }
        reminderWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                self.refreshNotificationStatus()
                self.refreshReminders()
            }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let text: String
            switch status {
            case .authorized: text = "Allowed"
            case .provisional: text = "Allowed quietly"
            case .ephemeral: text = "Allowed for now"
            case .denied: text = "Turned off in iPhone Settings"
            case .notDetermined: text = "Not asked yet"
            @unknown default: text = "Unknown"
            }
            DispatchQueue.main.async {
                self.notificationStatus = text
                self.notificationsAllowed = status == .authorized || status == .provisional || status == .ephemeral
            }
        }
    }
}
