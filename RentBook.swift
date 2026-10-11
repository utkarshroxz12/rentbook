//  RentBook.swift
//  App entry point, tabs and navigation.

import SwiftUI

@main
struct RentBookApp: App {
    @StateObject private var store = Store()
    @StateObject private var lock = LockManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(lock)
        }
    }
}

/// Every screen a list row can open.
enum Route: Hashable {
    case tenant(UUID)
    case tenantLedger(UUID)
    case payment(UUID, UUID)
    case deposits(UUID)
    case increases(UUID)
    case agreements(UUID)
    case agreement(UUID, UUID)
    case communication(UUID)
    case charges(UUID)
    case property(UUID)
    case expenses(UUID?)
    case expense(UUID)
    case report(ReportKind)
    case reports
    case oneTap
    case tax
    case partnership
    case partnerMonth(String)
    case partnerSources
    case partnerRules
    case partnerHistory
    case recurring
    case recurringReview
    case repairs
    case utilities(UUID)
    case handovers(UUID)
    case finalSettlement(UUID)
    case rentSheets
    case rentSheet(UUID)
    case backup
    case reminders
    case upcomingReminders
    case defaults
    case archived
    case audit
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .tenant(let id): TenantDetailView(tenantID: id)
        case .tenantLedger(let id): TenantLedgerView(tenantID: id)
        case .payment(let tenantID, let paymentID): PaymentDetailView(tenantID: tenantID, paymentID: paymentID)
        case .deposits(let id): DepositView(tenantID: id)
        case .increases(let id): IncreasesView(tenantID: id)
        case .agreements(let id): AgreementsView(tenantID: id)
        case .agreement(let tenantID, let agreementID): AgreementDetailView(tenantID: tenantID, agreementID: agreementID)
        case .communication(let id): CommunicationView(tenantID: id)
        case .charges(let id): ChargesView(tenantID: id)
        case .property(let id): PropertyDetailView(propertyID: id)
        case .expenses(let propertyID): ExpenseListView(propertyID: propertyID)
        case .expense(let id): ExpenseDetailView(expenseID: id)
        case .report(let kind): ReportView(kind: kind)
        case .reports: ReportsListView()
        case .oneTap: OneTapReportsView()
        case .tax: TaxSummaryView()
        case .partnership: PartnershipHomeView()
        case .partnerMonth(let key): PartnerMonthView(monthKey: key)
        case .partnerSources: PartnerSourcesView()
        case .partnerRules: AllocationRulesView()
        case .partnerHistory: PartnerHistoryView()
        case .recurring: RecurringListView()
        case .recurringReview: RecurringReviewView()
        case .repairs: RepairsView()
        case .utilities(let id): UtilitiesView(tenantID: id)
        case .handovers(let id): HandoversView(tenantID: id)
        case .finalSettlement(let id): FinalSettlementView(tenantID: id)
        case .rentSheets: RentSheetsView()
        case .rentSheet(let id): RentSheetView(sheetID: id)
        case .backup: BackupView()
        case .reminders: ReminderSettingsView()
        case .upcomingReminders: UpcomingRemindersView()
        case .defaults: DefaultsView()
        case .archived: ArchivedView()
        case .audit: AuditView()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var lock: LockManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                stack { DashboardView() }
                    .tabItem { Label(L("Home", "Home"), systemImage: "house") }
                    .tag(0)
                stack { TenantListView() }
                    .tabItem { Label(L("Tenants", "Tenants"), systemImage: "person.2") }
                    .badge(store.snapshot.count(.overdue))
                    .tag(1)
                stack { PropertyListView() }
                    .tabItem { Label(L("Properties", "Properties"), systemImage: "building.2") }
                    .tag(2)
                stack { AccountsHomeView() }
                    .tabItem { Label(L("Accounts", "Hisaab"), systemImage: "indianrupeesign.circle") }
                    .badge(store.snapshot.pendingRecurring)
                    .tag(3)
                stack { SettingsView() }
                    .tabItem { Label(L("Settings", "Settings"), systemImage: "gearshape") }
                    .tag(4)
            }
            // A new language redraws every screen.
            .id(store.settings.language)
            if store.settings.appLockEnabled && scenePhase != .active && !lock.isLocked {
                PrivacyCover()
            }
            if lock.isLocked {
                LockScreen()
            }
        }
        .alert(L("Something went wrong", "Kuch gadbad hui"), isPresented: problemBinding) {
            Button(L("OK", "Theek hai"), role: .cancel) {}
        } message: {
            Text(store.saveError ?? "")
        }
        .onAppear {
            lock.appLaunched(enabled: store.settings.appLockEnabled)
            store.requestNotificationPermission()
            store.appBecameActive()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                lock.didEnterBackground()
                lock.isCovered = store.settings.appLockEnabled
            case .active:
                lock.didBecomeActive(enabled: store.settings.appLockEnabled, afterMinutes: store.settings.lockAfterMinutes)
                lock.isCovered = false
                store.appBecameActive()
            default:
                lock.isCovered = store.settings.appLockEnabled
            }
        }
    }

    private var problemBinding: Binding<Bool> {
        Binding(get: { store.saveError != nil && !lock.isLocked }, set: { if !$0 { store.saveError = nil } })
    }

    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
    }
}
