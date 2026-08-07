import XCTest
import GRDB
@testable import BudgetCalendarCore

final class CompatibilityTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "sql", subdirectory: "Fixtures"))
        return try String(contentsOf: url)
    }
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

    func testRestorePreservesExistingDatabaseBeforeReplacingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let active = directory.appendingPathComponent("budget.sqlite")
        let backup = directory.appendingPathComponent("known-good.sqlite")
        let oldQueue = try DatabaseQueue(path: active.path)
        try oldQueue.write { try $0.execute(sql: "CREATE TABLE marker(value TEXT); INSERT INTO marker VALUES('old')") }
        let backupQueue = try DatabaseQueue(path: backup.path)
        try backupQueue.write { try $0.execute(sql: "PRAGMA journal_mode=WAL; CREATE TABLE marker(value TEXT); INSERT INTO marker VALUES('new')") }
        let hadBackupWAL = FileManager.default.fileExists(atPath: backup.path + "-wal")
        let preserved = try XCTUnwrap(try BackupService.restore(backup: backup, to: active))
        XCTAssertEqual(try DatabaseQueue(path: active.path).read { try String.fetchOne($0, sql: "SELECT value FROM marker") }, "new")
        XCTAssertEqual(try DatabaseQueue(path: preserved.path).read { try String.fetchOne($0, sql: "SELECT value FROM marker") }, "old")
        if hadBackupWAL { XCTAssertTrue(FileManager.default.fileExists(atPath: active.path + "-wal")) }
    }

    func testRestoreRemovesOrphanedDestinationSidecars() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let active = directory.appendingPathComponent("budget.sqlite")
        let backup = directory.appendingPathComponent("known-good.sqlite")
        let queue = try DatabaseQueue(path: backup.path)
        try queue.write { try $0.execute(sql: "CREATE TABLE marker(value TEXT); INSERT INTO marker VALUES('restored')") }
        try Data("orphaned WAL".utf8).write(to: URL(fileURLWithPath: active.path + "-wal"))
        XCTAssertNil(try BackupService.restore(backup: backup, to: active))
        XCTAssertEqual(try DatabaseQueue(path: active.path).read { try String.fetchOne($0, sql: "SELECT value FROM marker") }, "restored")
    }

    func testElectronVersionSixFixturePreservesRowsThroughNativeWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("budget.sqlite")
        let electronDatabase = try DatabaseQueue(path: path.path)
        try electronDatabase.write { try $0.execute(sql: fixture("electron-v6-compat")) }
        let coordinator = try DatabaseCoordinator(path: path)
        let service = BudgetService(database: coordinator.database)
        let moved = try XCTUnwrap(service.item(id: 802))
        XCTAssertEqual(moved.date, "2026-08-16")
        XCTAssertEqual(moved.movedFromDate, "2026-08-05")
        XCTAssertEqual(moved.assignedDepositItemId, 801)
        XCTAssertEqual(moved.movedFromDepositItemId, 800)
        XCTAssertEqual(try service.materialize(ruleId: 700, from: "2026-08-01", through: "2026-09-30"), 0)
        XCTAssertEqual(try service.visibleItems(from: "2026-08-01", through: "2026-09-30").map(\.id), [800, 804, 801, 802])
        XCTAssertEqual(try service.adjustments().first?.note, "Electron adjustment")
        _ = try service.saveItem(Item(name: "Native write", amountCents: 999, type: .purchase, date: "2026-08-20"))
        let preserved = try coordinator.database.read { db in
            try Row.fetchOne(db, sql: "SELECT name, amount_cents, moved_from_date, assignment_note FROM items WHERE id=802")
        }
        XCTAssertEqual(preserved?["name"] as String?, "Moved rent")
        XCTAssertEqual(preserved?["amount_cents"] as Int?, 120000)
        XCTAssertEqual(preserved?["moved_from_date"] as String?, "2026-08-05")
        XCTAssertEqual(preserved?["assignment_note"] as String?, "Pay later")
        XCTAssertEqual(try coordinator.database.read { try String.fetchOne($0, sql: "SELECT moved_from_date FROM items WHERE id=803") }, "2026-09-05")
        XCTAssertEqual(try coordinator.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM categories WHERE income_type='salary'") }, 1)
        XCTAssertEqual(try coordinator.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }, 6)
    }
}
