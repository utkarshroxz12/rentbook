//  UtilityViews.swift
//  Electricity and water meters for a tenant: readings, units used, the bill worked
//  out as (current reading - previous reading) x rate and added to the tenant's dues,
//  and the usage history.

import SwiftUI
import Charts

struct UtilitiesView: View {
    @EnvironmentObject var store: Store
    let tenantID: UUID

    @State private var adding: MeterKind? = nil
    @State private var editingRates = false
    @State private var deleting: MeterReading? = nil

    var body: some View {
        if let t = store.tenant(tenantID) {
            content(t)
        } else {
            Text(L("This tenant was removed.", "Yeh tenant hata diya gaya."))
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ t: Tenant) -> some View {
        List {
            ratesSection(t)
            ForEach(MeterKind.allCases) { kind in
                meterSection(kind, t)
            }
        }
        .navigationTitle(L("Electricity and water", "Bijli aur paani"))
        .sheet(item: $adding) { kind in
            MeterReadingFormView(tenantID: tenantID, kind: kind).environmentObject(store)
        }
        .sheet(isPresented: $editingRates) {
            UtilityRatesForm(tenantID: tenantID).environmentObject(store)
        }
        .confirmationDialog(L("Remove this reading?", "Yeh reading hatayein?"), isPresented: deleteBinding, titleVisibility: .visible) {
            Button(L("Remove reading", "Reading hatayein"), role: .destructive) {
                if let r = deleting {
                    store.deleteMeterReading(tenantID: tenantID, readingID: r.id)
                }
                deleting = nil
            }
        } message: {
            if let r = deleting, r.billedAmount > 0 {
                Text(L("The bill of ", "Iska ") + Fmt.inr(r.billedAmount) + L(" made from it is reversed. It stays in the tenant's history.",
                                                                              " ka bill wapas ho jayega. Tenant ki history mein dikhega."))
            } else {
                Text(L("Usage is worked out again from the other readings.", "Baaki readings se usage dobara nikala jayega."))
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func ratesSection(_ t: Tenant) -> some View {
        let settings = store.settings
        return Section {
            LabeledContent(L("Electricity rate", "Bijli rate"), value: rateText(t.electricityRate, settings.defaultElectricityRate))
            LabeledContent(L("Water rate", "Paani rate"), value: rateText(t.waterRate, settings.defaultWaterRate))
            Button(L("Change rates", "Rate badlein")) {
                editingRates = true
            }
        } footer: {
            Text(L("Rates are per unit. The default rates are in Settings → Defaults.", "Rate har unit ka hai. Default rate Settings → Defaults mein hain."))
        }
    }

    private func rateText(_ own: Double?, _ fallback: Double) -> String {
        if let own = own { return "₹" + Fmt.number(own) + L(" a unit", " per unit") }
        if fallback > 0 { return "₹" + Fmt.number(fallback) + L(" a unit (default)", " per unit (default)") }
        return L("Not set", "Set nahi")
    }

    private func meterSection(_ kind: MeterKind, _ t: Tenant) -> some View {
        let lines = Utilities.usage(kind, of: t)
        let recent = Array(lines.reversed())
        return Section {
            if lines.count >= 2 {
                usageChart(lines)
                    .frame(height: 160)
                    .padding(.vertical, 6)
            }
            if lines.isEmpty {
                Text(L("No readings yet.", "Abhi koi reading nahi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(recent) { line in
                UsageRow(line: line)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deleting = line.reading
                        } label: {
                            Label(L("Remove", "Hatayein"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
            Button {
                adding = kind
            } label: {
                Label(L("Add a reading", "Reading jodein"), systemImage: "plus.circle")
            }
        } header: {
            Text(kind.label)
        } footer: {
            if let average = averageUnits(lines) {
                Text(L("Average ", "Ausat ") + Fmt.number(average) + L(" units between readings.", " unit har reading ke beech."))
            }
        }
    }

    private func averageUnits(_ lines: [UsageLine]) -> Double? {
        let used = lines.dropFirst().map { $0.units }
        guard !used.isEmpty else { return nil }
        return (used.reduce(0, +) / Double(used.count) * 10).rounded() / 10
    }

    private func usageChart(_ lines: [UsageLine]) -> some View {
        let points = lines.dropFirst().suffix(12).enumerated().map { i, line in
            ChartPoint(label: Fmt.date(line.reading.date), series: L("Units", "Unit"), value: Int(line.units.rounded()), order: i)
        }
        return Chart(points) { p in
            BarMark(x: .value("Date", p.label), y: .value("Units", p.value))
        }
    }
}

extension MeterKind {
    var icon: String { self == .electricity ? "bolt.fill" : "drop.fill" }
}

struct UsageRow: View {
    let line: UsageLine

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.number(line.reading.reading))
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if line.previous != nil {
                    Text(Fmt.number(line.units) + L(" units", " unit"))
                        .font(.subheadline)
                }
                if line.reading.billedAmount > 0 {
                    Text(L("billed ", "bill ") + Fmt.inr(line.reading.billedAmount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String {
        var parts = [Fmt.date(line.reading.date)]
        if !line.reading.note.isEmpty { parts.append(line.reading.note) }
        return parts.joined(separator: " · ")
    }
}

struct MeterReadingFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var kind: MeterKind
    @State private var date = DateMath.day(Date())
    @State private var readingText = ""
    @State private var note = ""
    @State private var bill = true
    @State private var rateText = ""
    @State private var dueDate = DateMath.day(Date())
    @State private var prepared = false

    init(tenantID: UUID, kind: MeterKind) {
        self.tenantID = tenantID
        _kind = State(initialValue: kind)
    }

    private var reading: Double? { parseDecimal(readingText) }
    private var rate: Double { parseDecimal(rateText) ?? 0 }

    private var previous: MeterReading? {
        store.previousReading(kind, tenantID: tenantID, before: date)
    }

    private var units: Double {
        guard let r = reading, let p = previous else { return 0 }
        return max(0, r - p.reading)
    }

    private var amount: Int { Utilities.bill(units: units, rate: rate) }

    var body: some View {
        let name = store.tenant(tenantID)?.name ?? ""
        NavigationStack {
            Form {
                Section {
                    Picker(L("Meter", "Meter"), selection: $kind) {
                        ForEach(MeterKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker(L("Reading date", "Reading ki tareekh"), selection: $date, displayedComponents: .date)
                    HStack {
                        Text(L("Reading", "Reading"))
                        Spacer()
                        TextField("0", text: $readingText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                    }
                    TextField(L("Note", "Note"), text: $note)
                } footer: {
                    if let p = previous {
                        Text(concat(L("Last reading: ", "Pichhli reading: "), Fmt.number(p.reading), L(" on ", ", "), Fmt.date(p.date)))
                    } else {
                        Text(L("This is the first reading, so there is nothing to bill yet.", "Yeh pehli reading hai, isliye abhi bill nahi banega."))
                    }
                }
                if let p = previous {
                    billSection(p, name)
                }
            }
            .navigationTitle(L("Meter reading", "Meter reading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                        .disabled(reading == nil || (reading ?? 0) < 0)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
            .onChange(of: kind) { _ in
                setRate()
            }
        }
    }

    private func billSection(_ p: MeterReading, _ name: String) -> some View {
        Section {
            Toggle(L("Add a bill to ", "Bill jodein: ") + name + L("'s dues", " ke baaki mein"), isOn: $bill)
            if bill {
                HStack {
                    Text(L("Rate per unit", "Har unit ka rate"))
                    Spacer()
                    Text("₹").foregroundStyle(.secondary)
                    TextField("0", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                DatePicker(L("Bill due on", "Bill kab dena hai"), selection: $dueDate, displayedComponents: .date)
                LabeledContent(L("Units used", "Kitne unit"), value: Fmt.number(units))
                LabeledContent(L("Bill", "Bill"), value: Fmt.inr(amount))
                    .font(.headline)
            }
        } footer: {
            if let r = reading, r < p.reading {
                Text(L("This is lower than the last reading. If the meter was changed, save it without a bill.",
                       "Yeh pichhli reading se kam hai. Agar meter badla gaya hai to bina bill ke save karein."))
                    .foregroundStyle(.orange)
            } else if bill {
                Text(concat("(", (readingText.isEmpty ? "?" : readingText), " − ", Fmt.number(p.reading), ") × ₹", Fmt.number(rate), " = ", Fmt.inr(amount),
                            L(". The bill is added to the tenant's ledger as an extra charge.", ". Bill tenant ke ledger mein extra charge ki tarah judega.")))
            }
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        setRate()
        if let t = store.tenant(tenantID), let next = store.freshLedger(for: t).nextRentLine {
            dueDate = next.charge.dueDate
        }
    }

    private func setRate() {
        guard let t = store.tenant(tenantID) else { return }
        let r = Utilities.rate(kind, tenant: t, settings: store.settings)
        rateText = r > 0 ? Fmt.number(r) : ""
    }

    private func save() {
        guard let value = reading, value >= 0 else { return }
        var r = MeterReading()
        r.kind = kind
        r.date = date
        r.reading = value
        r.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        r.rate = rate
        store.addMeterReading(tenantID: tenantID, reading: r, bill: bill && amount > 0, dueDate: dueDate)
        dismiss()
    }
}

struct UtilityRatesForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let tenantID: UUID

    @State private var ownElectricity = false
    @State private var ownWater = false
    @State private var electricityText = ""
    @State private var waterText = ""
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L("Own electricity rate", "Alag bijli rate"), isOn: $ownElectricity)
                    if ownElectricity {
                        rateField(L("Electricity, per unit", "Bijli, har unit"), $electricityText)
                    }
                    Toggle(L("Own water rate", "Alag paani rate"), isOn: $ownWater)
                    if ownWater {
                        rateField(L("Water, per unit", "Paani, har unit"), $waterText)
                    }
                } footer: {
                    Text(L("Without its own rate, the tenant uses the default rate from Settings → Defaults.",
                           "Alag rate na ho to Settings → Defaults ka rate lagega."))
                }
            }
            .navigationTitle(L("Rates", "Rate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Save karein")) { save() }
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: prepare)
        }
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

    private func prepare() {
        guard !prepared, let t = store.tenant(tenantID) else { return }
        prepared = true
        ownElectricity = t.electricityRate != nil
        ownWater = t.waterRate != nil
        electricityText = t.electricityRate.map { Fmt.number($0) } ?? ""
        waterText = t.waterRate.map { Fmt.number($0) } ?? ""
    }

    private func save() {
        let electricity = ownElectricity ? max(0, parseDecimal(electricityText) ?? 0) : nil
        let water = ownWater ? max(0, parseDecimal(waterText) ?? 0) : nil
        store.setUtilityRates(tenantID: tenantID, electricity: electricity, water: water)
        dismiss()
    }
}
