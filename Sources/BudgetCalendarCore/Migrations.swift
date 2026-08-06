import Foundation
import GRDB

/// The Electron app uses SQLite PRAGMA user_version as its migration marker.
/// Keep that contract instead of GRDB's separate grdb_migrations table.
public enum DatabaseMigrations {
    public static let latestVersion = 6

    public static func migrate(_ database: DatabaseQueue) throws {
        try database.write { db in
            let current = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            guard current <= latestVersion else { throw DatabaseError.unsupportedFutureSchema(current, latestVersion) }
            for version in (current + 1)...latestVersion {
                try apply(version: version, db: db)
                try db.execute(sql: "PRAGMA user_version = \(version)")
            }
        }
    }

    private static func apply(version: Int, db: Database) throws {
        switch version {
        case 1:
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('purchase','bill','deposit','both')), is_builtin INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS recurring_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL CHECK(kind IN ('monthly_date','weekly','biweekly','monthly_nth')), anchor_date TEXT NOT NULL, weekday INTEGER, day_of_month INTEGER, nth INTEGER, end_date TEXT);
            CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), type TEXT NOT NULL CHECK(type IN ('deposit','bill','purchase')), date TEXT NOT NULL, category_id INTEGER REFERENCES categories(id), note TEXT, priority INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','paid')), paid_date TEXT, rule_id INTEGER REFERENCES recurring_rules(id), is_override INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0, assignment_override INTEGER NOT NULL DEFAULT 0, assigned_deposit_item_id INTEGER REFERENCES items(id), assignment_note TEXT, moved_from_deposit_item_id INTEGER REFERENCES items(id), created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS balance_adjustments (id INTEGER PRIMARY KEY AUTOINCREMENT, amount_cents INTEGER NOT NULL, date TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER, action TEXT NOT NULL, detail TEXT, created_at TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_items_date ON items(date);
            CREATE INDEX IF NOT EXISTS idx_items_type ON items(type);
            CREATE INDEX IF NOT EXISTS idx_items_rule ON items(rule_id);
            CREATE INDEX IF NOT EXISTS idx_items_assignment ON items(assignment_override, assigned_deposit_item_id);
            CREATE INDEX IF NOT EXISTS idx_audit_item ON audit_log(item_id);
            """)
        case 2:
            let rows: [(String, String, String, Int)] = [("Housing", "#e05d7a", "both", 1), ("Utilities", "#f2a6c0", "both", 2), ("Food & Groceries", "#a48bf0", "both", 3), ("Transportation", "#7c6bd6", "both", 4), ("Entertainment", "#f6c6d8", "both", 5), ("Shopping", "#d4b0f0", "both", 6), ("Health", "#f0eafa", "both", 7), ("Other", "#8b83a3", "both", 8), ("Salary", "#2f9e7f", "deposit", 9), ("Other Income", "#3aa97c", "deposit", 10)]
            for row in rows { try db.execute(sql: "INSERT OR IGNORE INTO categories (name,color,kind,is_builtin,sort_order) VALUES (?,?,?,1,?)", arguments: [row.0, row.1, row.2, row.3]) }
        case 3:
            try db.execute(sql: "ALTER TABLE categories ADD COLUMN income_type TEXT CHECK(income_type IN ('salary','other') OR income_type IS NULL)")
            try db.execute(sql: "UPDATE categories SET income_type='salary' WHERE name='Salary'")
            try db.execute(sql: "UPDATE categories SET income_type='other' WHERE name='Other Income'")
            try db.execute(sql: "UPDATE items SET category_id=(SELECT id FROM categories WHERE name='Other Income' LIMIT 1) WHERE type='deposit' AND category_id IS NULL")
            try db.execute(sql: "INSERT OR IGNORE INTO settings (key,value) VALUES ('include_other_income_in_pay_periods','true')")
        case 4:
            try db.execute(sql: "UPDATE items SET category_id=(SELECT id FROM categories WHERE name='Salary' LIMIT 1) WHERE type='deposit' AND category_id=(SELECT id FROM categories WHERE name='Other Income' LIMIT 1) AND (LOWER(name) LIKE '%paycheck%' OR LOWER(name) LIKE '%salary%')")
        case 5:
            try db.execute(sql: "ALTER TABLE items ADD COLUMN moved_from_date TEXT")
        case 6:
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(sql: "UPDATE items AS duplicate SET deleted=1, updated_at=? WHERE duplicate.deleted=0 AND duplicate.is_override=0 AND duplicate.rule_id IS NOT NULL AND EXISTS (SELECT 1 FROM items AS moved WHERE moved.rule_id=duplicate.rule_id AND moved.id != duplicate.id AND moved.deleted=0 AND moved.moved_from_date=duplicate.date)", arguments: [now])
            try db.execute(sql: "UPDATE items AS duplicate SET deleted=1, updated_at=? WHERE duplicate.deleted=0 AND duplicate.is_override=0 AND duplicate.rule_id IS NOT NULL AND EXISTS (SELECT 1 FROM items AS tombstone WHERE tombstone.rule_id=duplicate.rule_id AND tombstone.id != duplicate.id AND tombstone.deleted=1 AND tombstone.is_override=1 AND COALESCE(tombstone.moved_from_date,tombstone.date)=duplicate.date)", arguments: [now])
        default: break
        }
    }
}
