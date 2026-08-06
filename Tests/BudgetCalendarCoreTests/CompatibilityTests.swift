import XCTest
import GRDB
@testable import BudgetCalendarCore

final class CompatibilityTests: XCTestCase {
    func testFreshDatabaseUsesSharedSchemaAndVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let coordinator = try DatabaseCoordinator(path: directory.appendingPathComponent("budget.sqlite"))
        let version = try coordinator.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
        XCTAssertEqual(version, 6)
        let categories = try coordinator.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM categories") }
        XCTAssertEqual(categories, 10)
    }

    func testExistingVersionSixDatabaseIsNotRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("budget.sqlite")
        let db = try DatabaseQueue(path: path.path)
        try db.write { database in
            try database.execute(sql: "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try database.execute(sql: "CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color TEXT NOT NULL, kind TEXT NOT NULL, is_builtin INTEGER NOT NULL, sort_order INTEGER NOT NULL, income_type TEXT)")
            try database.execute(sql: "CREATE TABLE recurring_rules (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, anchor_date TEXT NOT NULL, weekday INTEGER, day_of_month INTEGER, nth INTEGER, end_date TEXT)")
            try database.execute(sql: "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, amount_cents INTEGER NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL, category_id INTEGER, note TEXT, priority INTEGER NOT NULL, status TEXT NOT NULL, paid_date TEXT, rule_id INTEGER, is_override INTEGER NOT NULL, deleted INTEGER NOT NULL, assignment_override INTEGER NOT NULL, assigned_deposit_item_id INTEGER, assignment_note TEXT, moved_from_deposit_item_id INTEGER, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, moved_from_date TEXT)")
            try database.execute(sql: "CREATE TABLE balance_adjustments (id INTEGER PRIMARY KEY, amount_cents INTEGER NOT NULL, date TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL)")
            try database.execute(sql: "CREATE TABLE audit_log (id INTEGER PRIMARY KEY, item_id INTEGER, action TEXT NOT NULL, detail TEXT, created_at TEXT NOT NULL)")
            try database.execute(sql: "PRAGMA user_version = 6")
        }
        let coordinator = try DatabaseCoordinator(path: path)
        XCTAssertEqual(try coordinator.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }, 6)
    }
}
