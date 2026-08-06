import XCTest
import GRDB
@testable import BudgetCalendarCore

final class BudgetServiceTests: XCTestCase {
    private func service() throws -> BudgetService {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return BudgetService(database: try DatabaseCoordinator(path: directory.appendingPathComponent("budget.sqlite")).database)
    }

    func testMaterializeAndDeleteOnlyUsesTombstone() throws {
        let service = try service()
        var rule = RecurringRule(id: nil, kind: .monthlyDate, anchorDate: "2026-01-15", weekday: nil, dayOfMonth: 15, nth: nil, endDate: nil)
        try service.database.write { db in try rule.insert(db) }
        var template = Item(name: "Rent", amountCents: 100_00, type: .bill, date: "2026-01-15", ruleId: rule.id)
        try service.database.write { db in try template.insert(db) }
        XCTAssertEqual(try service.materialize(ruleId: rule.id!, from: "2026-01-01", through: "2026-04-30"), 3)
        let future = try service.items(from: "2026-01-01", through: "2026-04-30").first { $0.date == "2026-02-15" }!
        _ = try service.deleteOccurrence(id: future.id!, scope: .onlyThis)
        XCTAssertEqual(try service.materialize(ruleId: rule.id!, from: "2026-01-01", through: "2026-04-30"), 0)
        XCTAssertEqual(try service.items(from: "2026-01-01", through: "2026-04-30").filter { $0.date == "2026-02-15" }.count, 1)
    }

    func testSaveAndMarkPaidRoundTripsThroughSharedItemSchema() throws {
        let service = try service()
        let saved = try service.saveItem(Item(name: "Groceries", amountCents: 4599, type: .purchase, date: "2026-08-06"))
        XCTAssertNotNil(saved.id)
        try service.setPaid(id: saved.id!, paid: true, paidDate: "2026-08-07")
        let updated = try service.item(id: saved.id!)
        XCTAssertEqual(updated?.status, .paid)
        XCTAssertEqual(updated?.paidDate, "2026-08-07")
    }

    func testCSVImportIsAdditiveAndResetRestoresDefaults() throws {
        let service = try service()
        let result = try service.importTransactionsCSV("Type,Name,Amount,Date,Category,Note,Priority,Status,Paid Date\nPurchase,Coffee,4.50,2026-08-06,Food & Groceries,,0,paid,2026-08-06\nBad,Nope,nope,invalid,,,,,\n")
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(try service.visibleItems(from: "2026-08-01", through: "2026-08-31").count, 1)
        try service.resetAllData()
        XCTAssertEqual(try service.visibleItems(from: "2026-08-01", through: "2026-08-31").count, 0)
        XCTAssertEqual(try service.categories().count, 10)
        XCTAssertEqual(try service.setting("include_other_income_in_pay_periods"), "true")
    }

    func testPayPeriodSummaryUsesOnlySalaryDepositsAndAssignmentRules() throws {
        let service = try service()
        let salary = try service.categories().first { $0.incomeType == "salary" }!
        _ = try service.saveItem(Item(name: "Paycheck", amountCents: 2_000_00, type: .deposit, date: "2026-08-01", categoryId: salary.id))
        _ = try service.saveItem(Item(name: "Other income", amountCents: 100_00, type: .deposit, date: "2026-08-05"))
        _ = try service.saveItem(Item(name: "Rent", amountCents: 1_250_00, type: .bill, date: "2026-08-03"))
        let summary = try XCTUnwrap(service.payPeriodSummaries(today: "2026-08-06").first)
        XCTAssertEqual(summary.period.depositAmountCents, 2_000_00)
        XCTAssertEqual(summary.assignedExpenseCents, 1_250_00)
        XCTAssertEqual(summary.remainingCents, 750_00)
        XCTAssertEqual(summary.leftAfterPlansCents, 850_00)
        try service.database.write { db in try db.execute(sql: "UPDATE categories SET income_type=NULL WHERE id=?", arguments: [salary.id]) }
        XCTAssertEqual(try service.payPeriodSummaries(today: "2026-08-06").first?.period.depositAmountCents, 2_000_00)
    }

    func testPayPeriodAvailableBalanceCarriesForwardAndCanExcludeOtherIncome() throws {
        let service = try service()
        let salary = try service.categories().first { $0.incomeType == "salary" }!
        _ = try service.saveItem(Item(name: "Pay 1", amountCents: 1_000_00, type: .deposit, date: "2026-08-01", categoryId: salary.id))
        _ = try service.saveItem(Item(name: "Pay 2", amountCents: 1_000_00, type: .deposit, date: "2026-08-15", categoryId: salary.id))
        _ = try service.saveItem(Item(name: "Gift", amountCents: 100_00, type: .deposit, date: "2026-08-02"))
        _ = try service.saveItem(Item(name: "First bill", amountCents: 200_00, type: .bill, date: "2026-08-03"))
        _ = try service.saveItem(Item(name: "Second bill", amountCents: 300_00, type: .bill, date: "2026-08-16"))
        let withOther = try service.payPeriodSummaries(today: "2026-08-02")
        XCTAssertEqual(withOther.map(\.leftAfterPlansCents), [900_00, 1_600_00])
        try service.setSetting("include_other_income_in_pay_periods", value: "false")
        XCTAssertEqual(try service.payPeriodSummaries(today: "2026-08-02").map(\.leftAfterPlansCents), [800_00, 1_500_00])
    }

    func testProjectedBalanceExcludesTransactionsOnExclusivePeriodEnd() throws {
        let service = try service()
        _ = try service.saveItem(Item(name: "Received", amountCents: 1_000_00, type: .deposit, date: "2026-08-01", status: .paid))
        _ = try service.saveItem(Item(name: "Next paycheck", amountCents: 1_000_00, type: .deposit, date: "2026-08-15"))
        XCTAssertEqual(try service.balances(today: "2026-08-02", through: "2026-08-14").projected, 1_000_00)
        XCTAssertEqual(try service.balances(today: "2026-08-02", through: "2026-08-15").projected, 2_000_00)
    }
}
