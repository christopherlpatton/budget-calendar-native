import XCTest
@testable import BudgetCalendarCore

final class RecurrenceTests: XCTestCase {
    func testMonthlyDateClampsDayThirtyOne() throws {
        let rule = RecurringRule(id: nil, kind: .monthlyDate, anchorDate: "2024-01-31", weekday: nil, dayOfMonth: 31, nth: nil, endDate: nil)
        XCTAssertEqual(RecurrenceEngine.occurrences(for: rule, from: "2024-02-01", through: "2024-04-30").map(\.date), ["2024-02-29", "2024-03-31", "2024-04-30"])
    }

    func testBiweeklyUsesFourteenDayDefault() throws {
        let rule = RecurringRule(id: nil, kind: .biweekly, anchorDate: "2026-01-02", weekday: nil, dayOfMonth: nil, nth: nil, endDate: nil)
        XCTAssertEqual(RecurrenceEngine.occurrences(for: rule, from: "2026-01-01", through: "2026-01-31").map(\.date), ["2026-01-02", "2026-01-16", "2026-01-30"])
    }
}
