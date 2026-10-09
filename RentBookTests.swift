//  RentBookTests.swift
//  Checks for the rent calculations. This file is not part of the app:
//  the GitHub build compiles it with the Core*.swift files, runs it first,
//  and stops the build if any check fails.

import Foundation

var checksRun = 0
var checksFailed = 0

func expect(_ ok: Bool, _ message: String, line: Int = #line) {
    checksRun += 1
    if !ok {
        checksFailed += 1
        print("FAIL line \(line): \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    checksRun += 1
    if actual != expected {
        checksFailed += 1
        print("FAIL line \(line): \(message): got \(actual), expected \(expected)")
    }
}

func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    DateMath.make(y, m, day)
}

func makeTenant(rent: Int, start: Date, due: Int = 5, prorate: Bool = false,
                frequency: BillingFrequency = .monthly) -> Tenant {
    var t = Tenant()
    t.name = "Test"
    t.startDate = start
    t.billingStartDate = start
    t.dueDay = due
    t.prorateFirst = prorate
    t.prorateLast = prorate
    t.frequency = frequency
    t.rentHistory = [RentChange(effectiveDate: start, amount: rent)]
    return t
}

func payment(_ amount: Int, _ date: Date, manual: [Allocation]? = nil, kind: PaymentKind = .payment) -> Payment {
    var p = Payment()
    p.amount = amount
    p.date = date
    p.createdAt = date
    p.kind = kind
    p.manualAllocations = manual
    return p
}

func line(_ ledger: TenantLedger, _ key: String) -> ChargeLine? {
    ledger.lines.first(where: { $0.id == key })
}

// MARK: - Monthly billing

func testMonthlyCharges() {
    let t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    let l = Ledger.ledger(for: t, asOf: d(2026, 3, 10), graceDays: 5)
    expectEqual(l.dueLines.count, 3, "three months due")
    expectEqual(l.totalBilled, 30000, "billed")
    expectEqual(l.outstanding, 30000, "outstanding")
    expectEqual(l.status, .overdue, "status")
    expectEqual(l.daysOverdue, 64, "days since the oldest due date")
    expectEqual(l.dueLines.map { $0.charge.dueDate }, [d(2026, 1, 5), d(2026, 2, 5), d(2026, 3, 5)], "due dates")
    expectEqual(Set(l.lines.map { $0.id }).count, l.lines.count, "no month billed twice")
    expectEqual(l.oldestUnpaid?.charge.key, "rent-2026-01", "oldest unpaid month")
    expectEqual(l.currentDue, 10000, "current month dues")
    expectEqual(l.arrears, 20000, "previous arrears")
}

func testStartAfterDueDay() {
    let t = makeTenant(rent: 9000, start: d(2026, 1, 20))
    let l = Ledger.ledger(for: t, asOf: d(2026, 2, 6))
    expectEqual(l.dueLines.map { $0.charge.dueDate }, [d(2026, 1, 20), d(2026, 2, 5)], "first rent due on the start day")
    expectEqual(l.totalBilled, 18000, "full months when not prorating")
}

func testProration() {
    var t = makeTenant(rent: 31000, start: d(2026, 1, 16), prorate: true)
    var l = Ledger.ledger(for: t, asOf: d(2026, 1, 20))
    expectEqual(l.dueLines.first?.charge.amount, 16000, "16 of 31 days in January")
    t.endDate = d(2026, 3, 14)
    l = Ledger.ledger(for: t, asOf: d(2026, 6, 1))
    expectEqual(l.dueLines.map { $0.charge.amount }, [16000, 31000, 14000], "first and last months prorated")
    expectEqual(l.upcomingLines.count, 0, "nothing billed after moving out")
}

func testLeapYear() {
    var t = makeTenant(rent: 29000, start: d(2028, 2, 1), prorate: true)
    t.endDate = d(2028, 2, 15)
    let l = Ledger.ledger(for: t, asOf: d(2028, 3, 1))
    expectEqual(DateMath.daysInMonth(d(2028, 2, 1)), 29, "February 2028 has 29 days")
    expectEqual(l.totalBilled, 15000, "15 of 29 days")
}

func testMoveOutWithoutProration() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.endDate = d(2026, 2, 3)
    var l = Ledger.ledger(for: t, asOf: d(2026, 4, 1))
    expectEqual(l.totalBilled, 10000, "left before February's due date")
    t.endDate = d(2026, 2, 10)
    l = Ledger.ledger(for: t, asOf: d(2026, 4, 1))
    expectEqual(l.totalBilled, 20000, "left after February's due date")
}

func testQuarterly() {
    let t = makeTenant(rent: 10000, start: d(2026, 1, 1), frequency: .quarterly)
    let l = Ledger.ledger(for: t, asOf: d(2026, 5, 10))
    expectEqual(l.dueLines.map { $0.charge.key }, ["rent-2026-01", "rent-2026-04"], "quarter keys")
    expectEqual(l.totalBilled, 60000, "two quarters of three months")
}

func testRentChange() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.rentHistory.append(RentChange(effectiveDate: d(2026, 3, 1), amount: 11000))
    var l = Ledger.ledger(for: t, asOf: d(2026, 4, 10))
    expectEqual(l.dueLines.map { $0.charge.amount }, [10000, 10000, 11000, 11000], "new rent from March")
    t.rentHistory[1].effectiveDate = d(2026, 3, 10)
    l = Ledger.ledger(for: t, asOf: d(2026, 4, 10))
    expectEqual(l.dueLines.map { $0.charge.amount }, [10000, 10000, 10000, 11000], "change after March's due date starts in April")
}

func testYearBoundaryAndDueDayLimit() {
    let t = makeTenant(rent: 8000, start: d(2025, 12, 1), due: 31)
    let l = Ledger.ledger(for: t, asOf: d(2026, 2, 28))
    expectEqual(l.dueLines.map { $0.charge.dueDate }, [d(2025, 12, 28), d(2026, 1, 28), d(2026, 2, 28)], "due day kept within 28")
    expectEqual(l.dueLines.map { $0.charge.key }, ["rent-2025-12", "rent-2026-01", "rent-2026-02"], "keys across the new year")
}

// MARK: - Payments

func testPartialAndOldestFirst() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.payments = [payment(10000, d(2026, 1, 6)), payment(4000, d(2026, 2, 6))]
    var l = Ledger.ledger(for: t, asOf: d(2026, 3, 10), graceDays: 5)
    expectEqual(l.outstanding, 16000, "February balance plus March")
    expectEqual(l.oldestUnpaid?.charge.key, "rent-2026-02", "February is the oldest unpaid")
    expectEqual(l.oldestUnpaid?.outstanding, 6000, "February still owes 6,000")
    expectEqual(l.currentDue, 10000, "this month's rent")
    expectEqual(l.arrears, 6000, "older arrears")
    expectEqual(l.payments.map { $0.balanceAfter }, [0, 6000], "balance after each payment")

    t.payments.append(payment(16000, d(2026, 3, 11)))
    l = Ledger.ledger(for: t, asOf: d(2026, 3, 12), graceDays: 5)
    expectEqual(l.outstanding, 0, "all cleared")
    expectEqual(l.status, .paid, "paid")
    let last = l.payments.last
    expectEqual(last?.applications.map { $0.chargeKey } ?? [], ["rent-2026-02", "rent-2026-03"], "one payment covers two months")
    expectEqual(last?.applications.map { $0.amount } ?? [], [6000, 10000], "split oldest first")
    expectEqual(last?.balanceAfter, 0, "nothing left after the last payment")
}

func testStatuses() {
    var t = makeTenant(rent: 10000, start: d(2026, 3, 1))
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 3, 2), graceDays: 5).status, .noDues, "nothing due before the 5th")
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 3, 7), graceDays: 5).status, .unpaid, "due, within the grace period")
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 3, 11), graceDays: 5).status, .overdue, "past the grace period")
    t.payments = [payment(4000, d(2026, 3, 6))]
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 3, 8), graceDays: 5).status, .partial, "part paid")
    t.payments.append(payment(6000, d(2026, 3, 9)))
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 3, 20), graceDays: 5).status, .paid, "two payments in one month")
}

func testAdvanceCredit() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.payments = [payment(25000, d(2026, 1, 2))]
    var l = Ledger.ledger(for: t, asOf: d(2026, 1, 10))
    expectEqual(l.outstanding, 0, "January covered")
    expectEqual(l.credit, 15000, "credit left over")
    expectEqual(l.net, -15000, "tenant in credit")
    expectEqual(line(l, "rent-2026-02")?.paid, 10000, "February paid ahead automatically")
    expectEqual(line(l, "rent-2026-03")?.paid, 5000, "part of March paid ahead")
    l = Ledger.ledger(for: t, asOf: d(2026, 2, 10))
    expectEqual(l.credit, 5000, "credit used for February automatically")
    expectEqual(l.status, .paid, "February counts as paid")
    l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(l.outstanding, 5000, "March half covered")
    expectEqual(l.credit, 0, "credit used up")

    var big = makeTenant(rent: 1000, start: d(2026, 1, 1))
    big.payments = [payment(20000, d(2026, 1, 2))]
    let far = Ledger.ledger(for: big, asOf: d(2026, 1, 10))
    expectEqual(far.net, -19000, "a year and more paid ahead")
    expect(far.advanceCredit > 0, "money beyond the next twelve months stays as unused credit")
}

func testEarlyPayment() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.payments = [payment(10000, d(2026, 1, 5)), payment(10000, d(2026, 2, 3))]
    let l = Ledger.ledger(for: t, asOf: d(2026, 2, 3))
    let last = l.payments.last
    expectEqual(last?.applications.map { $0.chargeKey } ?? [], ["rent-2026-02"], "paying two days early pays February")
    expectEqual(last?.balanceAfter, 0, "nothing left to pay for February")
    expectEqual(l.credit, 10000, "counted as paid ahead until the due date")
    let snap = Portfolio.snapshot(AppData(tenants: [t]), asOf: d(2026, 2, 3))
    expect(snap.upcomingDues.isEmpty, "a month paid early is not listed as coming due")
}

func testRefundOfMonthsPaidAhead() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    let both = [Allocation(chargeKey: "rent-2026-01", amount: 10000), Allocation(chargeKey: "rent-2026-02", amount: 10000)]
    t.payments = [payment(20000, d(2026, 1, 2), manual: both), payment(10000, d(2026, 1, 20), kind: .refund)]
    let l = Ledger.ledger(for: t, asOf: d(2026, 1, 25))
    expectEqual(l.outstanding, 0, "January still paid")
    expectEqual(l.net, 0, "nothing owed after the advance is returned")
    expect(line(l, "refund-excess") == nil, "no charge is made up for the refund")
    expectEqual(line(l, "rent-2026-02")?.paid, 0, "February is no longer paid ahead")
}

func testRecurringChargeChanges() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.recurringCharges = [RecurringCharge(title: "Maintenance", amount: 1500, endDate: d(2026, 3, 14)),
                          RecurringCharge(title: "Maintenance", amount: 2000, startDate: d(2026, 3, 15))]
    let l = Ledger.ledger(for: t, asOf: d(2026, 4, 10))
    let extras = l.dueLines.filter { $0.charge.kind == .recurring }.map { $0.charge.amount }
    expectEqual(extras, [1500, 1500, 1500, 2000], "new amount from April; March billed once")

    var late = makeTenant(rent: 10000, start: d(2026, 1, 1))
    late.recurringCharges = [RecurringCharge(title: "Parking", amount: 500, startDate: d(2026, 3, 25))]
    let l2 = Ledger.ledger(for: late, asOf: d(2026, 3, 26))
    expectEqual(l2.dueLines.filter { $0.charge.kind == .recurring }.count, 0, "a charge added after the due date starts next month")
}

func testBillingStartedLater() {
    var t = makeTenant(rent: 15000, start: d(2019, 3, 10), prorate: true)
    t.billingStartDate = d(2026, 10, 9)
    let l = Ledger.ledger(for: t, asOf: d(2026, 10, 9))
    expectEqual(l.dueLines.map { $0.charge.amount }, [15000], "a full October, not part of it")
    expectEqual(l.dueLines.first?.charge.dueDate, d(2026, 10, 5), "due on the usual day")
}

func testExpectedCountsOnlyDueRent() {
    var t = makeTenant(rent: 10000, start: d(2026, 4, 1))
    t.payments = (4...10).map { payment(10000, d(2026, $0, 5)) }
    let data = AppData(tenants: [t])
    let year = ReportFilter(from: d(2026, 4, 1), to: d(2027, 3, 31))
    let table = Reports.build(.expectedVsActual, data: data, filter: year, asOf: d(2026, 10, 9))
    expectEqual(table.totals?[2], Fmt.inr(70000), "expected counts rent due so far")
    expectEqual(table.totals?[4], Fmt.inr(0), "no shortfall for a tenant who is paid up")
}

func testTypedAmounts() {
    expectEqual(parseAmount("12,500"), 12500, "commas")
    expectEqual(parseAmount("₹12,500.00"), 12500, "pasted with paise")
    expectEqual(parseAmount(" 1,23,456 "), 123456, "Indian grouping")
    expectEqual(parseAmount("abc"), nil, "no digits")
    expectEqual(parseAmount("1234567890123"), nil, "too large")
    expectEqual(parseDecimal("5.5"), 5.5, "decimal")
    expectEqual(parseDecimal("1,000"), 1000, "thousands separator")
    expect(parseDecimal("inf") == nil, "infinity rejected")
    expect(parseDecimal("nan") == nil, "not-a-number rejected")
    expectEqual(Escalation.proposedAmount(from: 10000, mode: .percent, value: .infinity), 10000, "a broken value changes nothing")
    expectEqual(Escalation.proposedAmount(from: 10000, mode: .fixed, value: 500), 10500, "fixed increase")
    expectEqual(wholeRupees(.nan), 0, "safe conversion")
}

func testManualAllocation() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.payments = [payment(10000, d(2026, 3, 6), manual: [Allocation(chargeKey: "rent-2026-03", amount: 10000)])]
    var l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(l.outstanding, 20000, "January and February still open")
    expectEqual(line(l, "rent-2026-03")?.outstanding, 0, "March paid by choice")

    t.payments = [payment(12000, d(2026, 3, 6), manual: [Allocation(chargeKey: "rent-2026-03", amount: 12000)])]
    l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(line(l, "rent-2026-01")?.paid, 2000, "the extra goes to the oldest month")

    t.payments = [payment(10000, d(2026, 3, 6), manual: [Allocation(chargeKey: "rent-2026-05", amount: 10000)])]
    l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(l.prepaid, 10000, "May paid ahead")
    expectEqual(l.outstanding, 30000, "due months still open")
    expectEqual(l.net, 20000, "net balance")
}

func testReversalAndRefund() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    var wrong = payment(10000, d(2026, 1, 6))
    wrong.isReversed = true
    t.payments = [wrong]
    expectEqual(Ledger.ledger(for: t, asOf: d(2026, 1, 10)).outstanding, 10000, "reversed payment ignored")

    t.payments = [payment(15000, d(2026, 1, 2)), payment(5000, d(2026, 1, 20), kind: .refund)]
    var l = Ledger.ledger(for: t, asOf: d(2026, 1, 25))
    expectEqual(l.advanceCredit, 0, "refund took the extra back")
    expectEqual(l.outstanding, 0, "January still paid")
    expectEqual(l.totalPaid, 10000, "net paid")

    t.payments = [payment(15000, d(2026, 1, 2)), payment(8000, d(2026, 1, 20), kind: .refund)]
    l = Ledger.ledger(for: t, asOf: d(2026, 1, 25))
    expectEqual(l.outstanding, 3000, "refunded more than the extra")

    t.payments = [payment(5000, d(2026, 1, 2)), payment(8000, d(2026, 1, 20), kind: .refund)]
    l = Ledger.ledger(for: t, asOf: d(2026, 1, 25))
    expectEqual(l.outstanding, 13000, "refund beyond credit is owed back")
}

// MARK: - Adjustments, older dues, extras

func testAdjustments() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.adjustments = [
        Adjustment(kind: .discount, date: d(2026, 1, 3), periodKey: "rent-2026-01", amount: 1000, reason: "Festival"),
        Adjustment(kind: .waiver, date: d(2026, 2, 3), periodKey: "rent-2026-02", reason: "Repairs"),
        Adjustment(kind: .correction, date: d(2026, 3, 3), periodKey: "rent-2026-03", amount: 500),
        Adjustment(kind: .extraCharge, date: d(2026, 2, 15), amount: 700, title: "Electricity"),
        Adjustment(kind: .discount, date: d(2026, 1, 3), periodKey: "rent-2026-01", amount: 3000, isReversed: true),
        Adjustment(kind: .discount, date: d(2026, 1, 3), periodKey: "rent-2030-01", amount: 100)
    ]
    let l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(line(l, "rent-2026-01")?.charge.amount, 9000, "discount")
    expectEqual(line(l, "rent-2026-02")?.charge.amount, 0, "waived")
    expectEqual(line(l, "rent-2026-03")?.charge.amount, 10500, "correction")
    expectEqual(l.totalBilled, 9000 + 0 + 10500 + 700, "billed including the extra charge")
    expectEqual(l.orphanAdjustments, 1, "adjustment for a month that is not billed")
}

func testOpeningBalanceAndRecurring() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.openingBalance = 5000
    t.recurringCharges = [RecurringCharge(title: "Parking", amount: 1000, startDate: d(2026, 2, 1))]
    t.payments = [payment(5000, d(2026, 1, 2))]
    let l = Ledger.ledger(for: t, asOf: d(2026, 3, 10))
    expectEqual(line(l, "opening")?.outstanding, 0, "older dues settled first")
    expectEqual(l.dueLines.filter { $0.charge.kind == .recurring }.count, 2, "parking for February and March")
    expectEqual(l.totalBilled, 5000 + 30000 + 2000, "billed")
    expectEqual(l.outstanding, 32000, "outstanding")
}

func testDeposit() {
    var t = Tenant()
    t.deposits = [
        DepositEntry(kind: .received, amount: 30000),
        DepositEntry(kind: .additional, amount: 5000),
        DepositEntry(kind: .deduction, amount: 2000, reason: "Broken tap"),
        DepositEntry(kind: .refund, amount: 10000),
        DepositEntry(kind: .deduction, amount: 999, isReversed: true)
    ]
    let s = Ledger.deposit(of: t)
    expectEqual(s.held, 23000, "deposit held")
    expectEqual(s.totalIn, 35000, "received in total")
}

// MARK: - Increases, promises, agreements

func testEscalation() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.escalation = EscalationRule(mode: .percent, value: 5, everyMonths: 12, nextDate: d(2027, 1, 1))
    let p = Escalation.next(for: t, asOf: d(2026, 12, 1))
    expectEqual(p?.to, 10500, "5% increase proposed")
    expectEqual(p?.isDue, false, "not due yet")
    expectEqual(Ledger.rent(of: t, on: d(2027, 2, 1)), 10000, "nothing changes until approved")
    Escalation.apply(to: &t, newRent: 10600, effective: d(2027, 1, 1), reason: "Negotiated", scheduledFor: p?.date)
    expectEqual(Ledger.rent(of: t, on: d(2026, 12, 31)), 10000, "old rent kept before the effective date")
    expectEqual(Ledger.rent(of: t, on: d(2027, 1, 1)), 10600, "negotiated rent from the effective date")
    expectEqual(t.escalation?.nextDate, d(2028, 1, 1), "next increase a year later")
    Escalation.skip(&t, note: "Skipped this year")
    expectEqual(t.escalation?.nextDate, d(2029, 1, 1), "skipped one")
    t.escalation?.mode = .fixed
    t.escalation?.value = 1000
    expectEqual(Escalation.next(for: t, asOf: d(2028, 6, 1))?.to, 11600, "fixed-amount increase")
    expectEqual(t.escalationEvents.count, 2, "history kept")
}

func testPromises() {
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    let promise = PaymentPromise(madeOn: d(2026, 3, 1), promisedDate: d(2026, 3, 10), amount: 5000)
    t.promises = [promise]
    expectEqual(Promises.status(promise, of: t, asOf: d(2026, 3, 9)), .pending, "pending")
    expectEqual(Promises.status(promise, of: t, asOf: d(2026, 3, 11)), .missed, "missed")
    t.payments = [payment(6000, d(2026, 3, 5))]
    expectEqual(Promises.status(promise, of: t, asOf: d(2026, 3, 11)), .kept, "kept")
}

func testAgreements() {
    var a = Agreement()
    a.startDate = d(2026, 1, 1)
    a.endDate = d(2026, 11, 30)
    a.reminderDays = 30
    expectEqual(Agreements.status(a, asOf: d(2026, 6, 1)), .active, "active")
    expectEqual(Agreements.status(a, asOf: d(2026, 11, 10)), .expiring, "expiring")
    expectEqual(Agreements.status(a, asOf: d(2026, 12, 1)), .expired, "expired")
    a.endDate = nil
    expectEqual(Agreements.status(a, asOf: d(2026, 6, 1)), .open, "no end date")
}

// MARK: - Moving from RentBook 1.0, backups

/// RentBook 1.0's balance: older dues plus full rent for every due date so far, minus payments.
func versionOneBalance(_ t: Tenant, asOf: Date) -> Int {
    guard let start = t.startDate else { return 0 }
    let startDay = DateMath.day(start)
    let end = DateMath.day(asOf)
    var billed = 0
    var month = DateMath.monthStart(startDay)
    var safety = 0
    while safety < 600 {
        safety += 1
        var due = DateMath.dueDate(inMonthOf: month, day: t.dueDay)
        if due < startDay { due = startDay }
        if due > end { break }
        billed += Ledger.rent(of: t, on: due)
        month = DateMath.addMonths(1, to: month)
    }
    let paid = t.payments.reduce(0) { $0 + $1.amount }
    return t.openingBalance + billed - paid
}

func testMigrationFromVersion1() {
    let json = """
    [{"id":"11111111-1111-1111-1111-111111111111","name":"Ravi","phone":"98765 43210","unit":"Flat 1",
      "startDate":"2026-01-20T00:00:00Z","dueDay":5,"deposit":20000,"openingBalance":3000,
      "rentHistory":[{"id":"22222222-2222-2222-2222-222222222222","effectiveDate":"2026-01-20T00:00:00Z","amount":10000},
                     {"id":"33333333-3333-3333-3333-333333333333","effectiveDate":"2026-04-01T00:00:00Z","amount":10500}],
      "payments":[{"id":"44444444-4444-4444-4444-444444444444","date":"2026-01-21T00:00:00Z","amount":13000,"method":"UPI","note":""},
                  {"id":"55555555-5555-5555-5555-555555555555","date":"2026-03-06T00:00:00Z","amount":15000,"method":"Cash","note":"two months"}],
      "incrementPercent":5,"incrementEveryMonths":11,"nextIncrementDate":"2026-12-20T00:00:00Z","notes":"Good tenant"}]
    """
    guard let result = try? BackupCodec.decode(Data(json.utf8)) else {
        expect(false, "a RentBook 1.0 file should load")
        return
    }
    expect(result.fromVersion1, "recognised as RentBook 1.0")
    let data = result.data
    expectEqual(data.tenants.count, 1, "one tenant")
    expectEqual(data.properties.first?.units.map { $0.name } ?? [], ["Flat 1"], "the unit becomes part of a property")
    guard let t = data.tenants.first else { return }
    expectEqual(t.unitID, data.properties.first?.units.first?.id, "tenant assigned to the unit")
    expectEqual(Ledger.deposit(of: t).held, 20000, "deposit kept")
    expectEqual(t.escalation?.everyMonths, 11, "increase schedule kept")
    expectEqual(t.payments.map { $0.method }, [.upi, .cash], "payment methods")
    expectEqual(t.payments.map { $0.receiptNumber }, [1, 2], "receipt numbers")
    let asOf = d(2026, 6, 10)
    expectEqual(Ledger.ledger(for: t, asOf: asOf).net, versionOneBalance(t, asOf: asOf), "same balance as RentBook 1.0")
    expectEqual(Ledger.ledger(for: t, asOf: asOf).net, 36500, "expected balance")
}

func testBackupRoundTrip() {
    let asOf = d(2026, 10, 9)
    let sample = SampleData.make(asOf: asOf)
    do {
        let raw = try BackupCodec.encoder.encode(sample)
        let back = try BackupCodec.decode(raw)
        expectEqual(back.data.tenants.count, sample.tenants.count, "tenants survive a round trip")
        expect(!back.fromVersion1, "current data is not RentBook 1.0")
        let before = Ledger.ledger(for: sample.tenants[0], asOf: asOf).net
        let after = Ledger.ledger(for: back.data.tenants[0], asOf: asOf).net
        expectEqual(after, before, "balances survive a round trip")

        let file = EmbeddedFile(fileName: "proof.jpg", base64: Data("hello".utf8).base64EncodedString())
        let package = try BackupCodec.package(sample, files: [file])
        let restored = try BackupCodec.decode(package)
        expectEqual(restored.files.count, 1, "files travel with a full backup")
        expectEqual(restored.data.properties.count, sample.properties.count, "properties in a full backup")
    } catch {
        expect(false, "backup failed: \(error)")
    }
    let unrelated = try? BackupCodec.decode(Data("{\"hello\":1}".utf8))
    expect(unrelated == nil, "an unrelated file is rejected")
}

func testTolerantDecoding() {
    let json = """
    {"schemaVersion":2,"tenants":[{"name":"Asha","futureField":true,
      "payments":[{"amount":500,"method":"crypto","date":"2026-01-02T00:00:00Z"}]}]}
    """
    guard let result = try? BackupCodec.decode(Data(json.utf8)) else {
        expect(false, "data with missing fields should still load")
        return
    }
    expectEqual(result.data.tenants.first?.name, "Asha", "name kept")
    expectEqual(result.data.tenants.first?.payments.first?.amount, 500, "payment kept")
    expectEqual(result.data.tenants.first?.payments.first?.method, PaymentMethod.upi, "unknown method falls back")
}

// MARK: - Reminders, dashboard, reports

func testReminderPlan() {
    var data = AppData()
    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.payments = (1...10).map { payment(10000, d(2026, $0, 5)) }
    data.tenants = [t]
    let now = DateMath.at(d(2026, 10, 25), hour: 9, minute: 0)
    let plan = ReminderPlanner.plan(data, now: now)
    expect(plan.contains(where: { $0.kind == "before" && DateMath.day($0.date) == d(2026, 11, 2) }), "3 days before November's rent")
    expect(plan.contains(where: { $0.kind == "due" && DateMath.day($0.date) == d(2026, 11, 5) }), "on the due date")
    expect(plan.allSatisfy({ $0.date > now }), "only future reminders")
    expect(plan.count <= 60, "within the iOS limit")
    expect(plan.contains(where: { $0.kind == "refresh" }), "reminder to open the app")

    let prepay = payment(10000, d(2026, 10, 25), manual: [Allocation(chargeKey: "rent-2026-11", amount: 10000)])
    data.tenants[0].payments.append(prepay)
    let after = ReminderPlanner.plan(data, now: now)
    expect(!after.contains(where: { $0.kind == "due" && DateMath.day($0.date) == d(2026, 11, 5) }), "no reminder once November is paid")
}

func testSnapshotAndReports() {
    let asOf = d(2026, 10, 9)
    let sample = SampleData.make(asOf: asOf)
    let snap = Portfolio.snapshot(sample, asOf: asOf)
    let live = sample.tenants.filter { $0.status != .vacated && !$0.isArchived }.count
    let counted = PayStatus.allCases.reduce(0) { $0 + snap.count($1) }
    expectEqual(counted, live, "every live tenant has one payment status")
    expect(snap.outstanding >= snap.overdue, "overdue is part of outstanding")
    expect(snap.depositsHeld > 0, "deposits held")

    for t in sample.tenants {
        let ids = Ledger.ledger(for: t, asOf: asOf).lines.map { $0.id }
        expectEqual(Set(ids).count, ids.count, "no duplicate charges for " + t.name)
    }

    let year = ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31))
    let monthly = Reports.build(.monthlyCollection, data: sample, filter: year, asOf: asOf)
    expectEqual(monthly.rows.count, 12, "one row per month")
    expect(monthly.csv.hasPrefix("Month,Expected,Collected,Difference"), "CSV header")

    if let first = sample.tenants.first {
        var f = ReportFilter(from: d(2020, 1, 1), to: asOf)
        f.tenantID = first.id
        let report = Reports.build(.tenantLedger, data: sample, filter: f, asOf: asOf)
        expectEqual(report.totals?.last, Fmt.inr(Ledger.ledger(for: first, asOf: asOf).net), "ledger report closing balance")
    }

    for kind in ReportKind.allCases {
        var f = year
        f.tenantID = kind.needsTenant ? sample.tenants.first?.id : nil
        let table = Reports.build(kind, data: sample, filter: f, asOf: asOf)
        let width = table.columns.count
        expect(table.rows.allSatisfy({ $0.count == width }), kind.title + ": every row has every column")
    }
}

func testMessagesAndWords() {
    expectEqual(Messages.rupeesInWords(0), "Zero", "zero")
    expectEqual(Messages.rupeesInWords(15000), "Fifteen Thousand", "thousands")
    expectEqual(Messages.rupeesInWords(123456), "One Lakh Twenty Three Thousand Four Hundred Fifty Six", "lakhs")
    expectEqual(Messages.rupeesInWords(25_00_00_000), "Twenty Five Crore", "crores")
    expectEqual(Messages.rupeesInWords(10_05_011), "Ten Lakh Five Thousand Eleven", "mixed")

    expectEqual(Messages.phoneDigits("098765 43210"), "919876543210", "Indian mobile with a leading zero")
    let url = Messages.whatsappURL(phone: "+91 98765 43210", text: "Rent ₹5,000 + maintenance")
    expect(url?.absoluteString.hasPrefix("https://wa.me/919876543210?text=") ?? false, "WhatsApp link")
    expect(url?.absoluteString.contains("%2B") ?? false, "plus sign kept in the message")
    expect(Messages.whatsappURL(phone: "12345", text: "x") == nil, "too short for WhatsApp")

    var t = makeTenant(rent: 10000, start: d(2026, 1, 1))
    t.name = "Ravi"
    let ledger = Ledger.ledger(for: t, asOf: d(2026, 2, 10))
    let context = MessageContext(tenant: t, place: "Flat 101", ledger: ledger, deadline: d(2026, 2, 15), landlord: "Owner")
    let text = Messages.compose(.politeReminder, context)
    expect(text.contains(Fmt.inr(20000)), "reminder shows the amount owed")
    expect(Fmt.inr(123456).hasSuffix("1,23,456"), "Indian digit grouping: " + Fmt.inr(123456))
    expect(text.contains("Flat 101"), "reminder names the place")
}

@main
struct RentBookTestRunner {
    static func main() {
        testMonthlyCharges()
        testStartAfterDueDay()
        testProration()
        testLeapYear()
        testMoveOutWithoutProration()
        testQuarterly()
        testRentChange()
        testYearBoundaryAndDueDayLimit()
        testPartialAndOldestFirst()
        testStatuses()
        testAdvanceCredit()
        testEarlyPayment()
        testRefundOfMonthsPaidAhead()
        testRecurringChargeChanges()
        testBillingStartedLater()
        testExpectedCountsOnlyDueRent()
        testTypedAmounts()
        testManualAllocation()
        testReversalAndRefund()
        testAdjustments()
        testOpeningBalanceAndRecurring()
        testDeposit()
        testEscalation()
        testPromises()
        testAgreements()
        testMigrationFromVersion1()
        testBackupRoundTrip()
        testTolerantDecoding()
        testReminderPlan()
        testSnapshotAndReports()
        testMessagesAndWords()
        print("RentBook rent checks: \(checksRun) run, \(checksFailed) failed")
        exit(checksFailed == 0 ? 0 : 1)
    }
}
