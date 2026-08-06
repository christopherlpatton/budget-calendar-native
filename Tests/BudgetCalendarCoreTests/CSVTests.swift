import XCTest
@testable import BudgetCalendarCore

final class CSVTests: XCTestCase {
    func testExportEscapesNotesAndRoundTrips() throws {
        let item = Item(name: "Groceries", amountCents: 1234, type: .purchase, date: "2026-08-06", note: "Milk, \"oat\"")
        let csv = CSVService.export(items: [item])
        let rows = try CSVService.parse(csv)
        XCTAssertEqual(rows.first?["name"], "Groceries")
        XCTAssertEqual(rows.first?["note"], "Milk, \"oat\"")
    }
}
