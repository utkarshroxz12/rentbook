//  DashboardView.swift
//  The home screen: this month's money, who has paid, and what needs attention.

import SwiftUI

enum DashboardSheet: Identifiable {
    case addTenant
    case addProperty
    case pay(UUID)

    var id: String {
        switch self {
        case .addTenant: return "tenant"
        case .addProperty: return "property"
        case .pay(let id): return "pay-" + id.uuidString
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: DashboardSheet? = nil
    @State private var showAllQuickPay = false

    var body: some View {
        let snap = store.snapshot
        List {
            if store.isEmpty {
                welcomeSection
            }
            Section("This month") {
                totals(snap)
            }
            Section("Tenants") {
                counts(snap)
            }
            alertsSection(snap)
            quickPaySection(snap)
            upcomingSection(snap)
            increasesSection(snap)
            agreementsSection(snap)
            recentSection(snap)
        }
        .navigationTitle("RentBook")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sheet = .addTenant
                    } label: {
                        Label("Add tenant", systemImage: "person.badge.plus")
                    }
                    Button {
                        sheet = .addProperty
                    } label: {
                        Label("Add property", systemImage: "building.2")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $sheet) { which in
            sheetView(which)
        }
        .refreshable { @MainActor in
            store.appBecameActive()
        }
    }

    @ViewBuilder
    private func sheetView(_ which: DashboardSheet) -> some View {
        switch which {
        case .addTenant:
            TenantFormView(tenant: nil).environmentObject(store)
        case .addProperty:
            PropertyFormView(property: nil).environmentObject(store)
        case .pay(let id):
            PaymentFormView(tenantID: id).environmentObject(store)
        }
    }

    private var welcomeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to RentBook")
                    .font(.headline)
                Text("Add a property and its tenants to start tracking rent. You can also load sample data from Settings to look around first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                sheet = .addProperty
            } label: {
                Label("Add a property", systemImage: "building.2")
            }
            Button {
                sheet = .addTenant
            } label: {
                Label("Add a tenant", systemImage: "person.badge.plus")
            }
        }
    }

    private func totals(_ snap: PortfolioSnapshot) -> some View {
        TileGrid {
            StatTile(title: "Rent expected", value: Fmt.inr(snap.expectedThisMonth))
            StatTile(title: "Collected", value: Fmt.inr(snap.collectedThisMonth), tint: .green)
            StatTile(title: "Outstanding", value: Fmt.inr(snap.outstanding), tint: snap.outstanding > 0 ? .orange : .primary)
            StatTile(title: "Overdue", value: Fmt.inr(snap.overdue), tint: snap.overdue > 0 ? .red : .primary)
            StatTile(title: "Deposits held", value: Fmt.inr(snap.depositsHeld))
            StatTile(title: "Advance credit", value: Fmt.inr(snap.credit))
        }
    }

    private func counts(_ snap: PortfolioSnapshot) -> some View {
        HStack(spacing: 8) {
            countBox("Paid", snap.count(.paid), .green)
            countBox("Partly paid", snap.count(.partial), .orange)
            countBox("Unpaid", snap.count(.unpaid), .blue)
            countBox("Overdue", snap.count(.overdue), .red)
        }
        .padding(.vertical, 4)
    }

    private func countBox(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func alertsSection(_ snap: PortfolioSnapshot) -> some View {
        if !snap.alerts.isEmpty {
            Section("Needs attention") {
                ForEach(Array(snap.alerts.prefix(15))) { alert in
                    alertRow(alert)
                }
            }
        }
    }

    @ViewBuilder
    private func alertRow(_ alert: AlertItem) -> some View {
        if alert.kind == .unpaidBill {
            NavigationLink(value: Route.expenses(alert.propertyID)) {
                AlertRowView(alert: alert)
            }
        } else if let tenantID = alert.tenantID {
            NavigationLink(value: Route.tenant(tenantID)) {
                AlertRowView(alert: alert)
            }
        } else if let propertyID = alert.propertyID {
            NavigationLink(value: Route.property(propertyID)) {
                AlertRowView(alert: alert)
            }
        } else {
            AlertRowView(alert: alert)
        }
    }

    @ViewBuilder
    private func quickPaySection(_ snap: PortfolioSnapshot) -> some View {
        let tenants = store.liveTenants.sorted { (snap.ledgers[$0.id]?.net ?? 0) > (snap.ledgers[$1.id]?.net ?? 0) }
        if !tenants.isEmpty {
            Section {
                ForEach(showAllQuickPay ? tenants : Array(tenants.prefix(5))) { t in
                    Button {
                        sheet = .pay(t.id)
                    } label: {
                        QuickPayRow(tenant: t, ledger: snap.ledgers[t.id], place: store.place(of: t))
                    }
                    .buttonStyle(.plain)
                }
                if tenants.count > 5 {
                    Button {
                        showAllQuickPay.toggle()
                    } label: {
                        Text(showAllQuickPay ? "Show fewer" : "Show all \(tenants.count) tenants")
                    }
                }
            } header: {
                Text("Record a payment")
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(_ snap: PortfolioSnapshot) -> some View {
        if !snap.upcomingDues.isEmpty {
            Section("Due in the next 14 days") {
                ForEach(Array(snap.upcomingDues.prefix(15))) { item in
                    NavigationLink(value: Route.tenant(item.tenant.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tenant.name)
                                Text(item.line.charge.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.inr(item.line.outstanding))
                                    .font(.subheadline.weight(.semibold))
                                Text(Fmt.date(item.line.charge.dueDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func increasesSection(_ snap: PortfolioSnapshot) -> some View {
        if !snap.upcomingIncreases.isEmpty {
            Section("Rent increases") {
                ForEach(snap.upcomingIncreases) { item in
                    NavigationLink(value: Route.increases(item.tenant.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tenant.name)
                                Text(Fmt.inr(item.proposal.from) + " → " + Fmt.inr(item.proposal.to))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.proposal.isDue {
                                TagLabel(text: "Review now", color: .orange)
                            } else {
                                Text(Fmt.date(item.proposal.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agreementsSection(_ snap: PortfolioSnapshot) -> some View {
        if !snap.agreements.isEmpty {
            Section("Agreements") {
                ForEach(snap.agreements) { item in
                    NavigationLink(value: Route.agreement(item.tenant.id, item.agreement.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tenant.name)
                                Text("Ends " + (item.agreement.endDate.map { Fmt.date($0) } ?? "—"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TagLabel(text: item.status.label, color: item.status == .expired ? .red : .orange)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentSection(_ snap: PortfolioSnapshot) -> some View {
        if !snap.recentPayments.isEmpty {
            Section("Recent payments") {
                ForEach(snap.recentPayments) { item in
                    NavigationLink(value: Route.payment(item.tenant.id, item.payment.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tenant.name)
                                Text(Fmt.date(item.payment.date) + " · " + (item.payment.kind == .refund ? "Refund" : item.payment.method.label))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((item.payment.kind == .refund ? "-" : "") + Fmt.inr(item.payment.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.payment.kind == .refund ? Color.red : Color.green)
                        }
                    }
                }
            }
        }
    }
}

struct AlertRowView: View {
    let alert: AlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline.weight(.medium))
                Text(alert.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch alert.kind {
        case .overdue: return "exclamationmark.circle.fill"
        case .increaseDue: return "arrow.up.circle.fill"
        case .agreementExpired, .agreementExpiring: return "doc.text.fill"
        case .promiseMissed: return "hand.raised.fill"
        case .followUp: return "bubble.left.fill"
        case .depositToSettle: return "banknote.fill"
        case .unpaidBill: return "wrench.and.screwdriver.fill"
        case .vacantUnit: return "house.fill"
        }
    }

    private var color: Color {
        switch alert.kind {
        case .overdue, .agreementExpired, .promiseMissed: return .red
        case .increaseDue, .agreementExpiring, .depositToSettle, .unpaidBill: return .orange
        case .followUp, .vacantUnit: return .blue
        }
    }
}

struct QuickPayRow: View {
    let tenant: Tenant
    let ledger: TenantLedger?
    let place: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tenant.name)
                if !place.isEmpty {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let ledger = ledger, ledger.net > 0 {
                Text(Fmt.inr(ledger.net))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ledger.overdue > 0 ? Color.red : Color.orange)
            } else {
                Text("Paid up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
        }
        .contentShape(Rectangle())
    }
}
