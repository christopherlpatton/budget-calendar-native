import XCTest
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
}
