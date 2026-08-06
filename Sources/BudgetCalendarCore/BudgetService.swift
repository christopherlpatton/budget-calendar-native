import Foundation
import GRDB

public enum OccurrenceScope: String, Sendable { case onlyThis = "only_this", thisAndFuture = "this_and_future", all }

public struct ItemChanges: Sendable {
    public var name: String?; public var amountCents: Int?; public var type: ItemType?; public var date: String?
    public var categoryId: Int64?; public var note: String?; public var priority: Int?
    public init(name: String? = nil, amountCents: Int? = nil, type: ItemType? = nil, date: String? = nil, categoryId: Int64? = nil, note: String? = nil, priority: Int? = nil) {
        self.name = name; self.amountCents = amountCents; self.type = type; self.date = date; self.categoryId = categoryId; self.note = note; self.priority = priority
    }
}

public final class BudgetService {
    public let database: DatabaseQueue
    public init(database: DatabaseQueue) { self.database = database }

    public func items(from start: String, through end: String) throws -> [Item] {
        try database.read { db in try Item.fetchAll(db, sql: "SELECT * FROM items WHERE date BETWEEN ? AND ? ORDER BY date, id", arguments: [start, end]) }
    }
    public func visibleItems(from start: String, through end: String) throws -> [Item] {
        try database.read { db in try Item.fetchAll(db, sql: "SELECT * FROM items WHERE deleted=0 AND date BETWEEN ? AND ? ORDER BY date, id", arguments: [start, end]) }
    }
    public func item(id: Int64) throws -> Item? { try database.read { db in try Item.fetchOne(db, key: id) } }
    public func categories() throws -> [Category] { try database.read { db in try Category.fetchAll(db, sql: "SELECT * FROM categories ORDER BY sort_order, id") } }
    public func rules() throws -> [RecurringRule] { try database.read { db in try RecurringRule.fetchAll(db, sql: "SELECT * FROM recurring_rules ORDER BY anchor_date, id") } }
    public func setting(_ key: String) throws -> String? { try database.read { db in try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key=?", arguments: [key]) } }
    public func setSetting(_ key: String, value: String) throws { try database.write { db in try db.execute(sql: "INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [key, value]) } }
    @discardableResult public func saveItem(_ item: Item) throws -> Item {
        var item = item
        item.updatedAt = now()
        try database.write { db in
            if item.id == nil { item.createdAt = item.updatedAt; try item.insert(db) }
            else { try item.update(db) }
        }
        return item
    }
    public func setPaid(id: Int64, paid: Bool, paidDate: String? = nil) throws {
        try database.write { db in try db.execute(sql: "UPDATE items SET status=?, paid_date=?, updated_at=? WHERE id=?", arguments: [paid ? ItemStatus.paid.rawValue : ItemStatus.planned.rawValue, paid ? (paidDate ?? today()) : nil, now(), id]) }
    }
    public func importTransactionsCSV(_ content: String) throws -> (imported: Int, skipped: Int) {
        let rows = try CSVService.parse(content)
        return try database.write { db in
            let categories = try Category.fetchAll(db)
            let categoryByName = Dictionary(uniqueKeysWithValues: categories.compactMap { category in category.id.map { (category.name.lowercased(), $0) } })
            var imported = 0, skipped = 0
            for row in rows {
                guard let type = ItemType(rawValue: row["type"]?.lowercased() ?? ""), let name = row["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, let cents = cents(row["amount"] ?? ""), cents > 0, validDate(row["date"] ?? "") else { skipped += 1; continue }
                let status = ItemStatus(rawValue: row["status"]?.lowercased() ?? "") ?? .planned
                let item = Item(name: name, amountCents: cents, type: type, date: row["date"]!, categoryId: row["category"].flatMap { categoryByName[$0.lowercased()] }, note: row["note"]?.emptyAsNil, priority: Int(row["priority"] ?? "") ?? 0, status: status, paidDate: row["paid date"]?.emptyAsNil)
                try item.insert(db); imported += 1
            }
            return (imported, skipped)
        }
    }
    public func resetAllData() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM audit_log; DELETE FROM items; DELETE FROM recurring_rules; DELETE FROM balance_adjustments; DELETE FROM categories; DELETE FROM settings; DELETE FROM sqlite_sequence WHERE name IN ('items','recurring_rules','balance_adjustments','audit_log','categories')")
            let seed: [(String, String, String, Int, String?)] = [("Housing", "#e05d7a", "both", 1, nil), ("Utilities", "#f2a6c0", "both", 2, nil), ("Food & Groceries", "#a48bf0", "both", 3, nil), ("Transportation", "#7c6bd6", "both", 4, nil), ("Entertainment", "#f6c6d8", "both", 5, nil), ("Shopping", "#d4b0f0", "both", 6, nil), ("Health", "#f0eafa", "both", 7, nil), ("Other", "#8b83a3", "both", 8, nil), ("Salary", "#2f9e7f", "deposit", 9, "salary"), ("Other Income", "#3aa97c", "deposit", 10, "other")]
            for row in seed { try db.execute(sql: "INSERT INTO categories(name,color,kind,is_builtin,sort_order,income_type) VALUES(?,?,?,1,?,?)", arguments: [row.0, row.1, row.2, row.3, row.4]) }
            try db.execute(sql: "INSERT INTO settings(key,value) VALUES('include_other_income_in_pay_periods','true')")
        }
    }

    @discardableResult public func materialize(ruleId: Int64, from start: String, through end: String) throws -> Int {
        try database.write { db in
            guard let rule = try RecurringRule.fetchOne(db, key: ruleId), let template = try Item.fetchOne(db, sql: "SELECT * FROM items WHERE rule_id=? AND deleted=0 ORDER BY date,id LIMIT 1", arguments: [ruleId]) else { return 0 }
            let existing = try Item.fetchAll(db, sql: "SELECT * FROM items WHERE rule_id=?", arguments: [ruleId])
            var occupied = Set<String>()
            for item in existing { if !item.deleted || item.isOverride { occupied.insert(item.movedFromDate ?? item.date) } }
            var count = 0
            for occurrence in RecurrenceEngine.occurrences(for: rule, from: start, through: end) where !occupied.contains(occurrence.date) {
                var generated = template; generated.id = nil; generated.date = occurrence.date; generated.ruleId = ruleId; generated.isOverride = false; generated.deleted = false
                generated.createdAt = now(); generated.updatedAt = generated.createdAt
                try generated.insert(db); occupied.insert(occurrence.date); count += 1
            }
            return count
        }
    }

    public func deleteOccurrence(id: Int64, scope: OccurrenceScope) throws -> String {
        try database.write { db in
            guard let item = try Item.fetchOne(db, key: id) else { return "Item not found." }
            if scope == .onlyThis || item.ruleId == nil {
                try db.execute(sql: "UPDATE items SET deleted=1, is_override=?, updated_at=? WHERE id=?", arguments: [scope == .onlyThis ? 1 : 0, now(), id])
                return scope == .onlyThis ? "Deleted this occurrence of \(item.name) (\(item.date))." : "Deleted \(item.name) (\(item.date))."
            }
            guard let ruleId = item.ruleId else { return "Item not found." }
            if scope == .thisAndFuture {
                try db.execute(sql: "UPDATE recurring_rules SET end_date=? WHERE id=?", arguments: [dayBefore(item.date), ruleId])
                try db.execute(sql: "UPDATE items SET deleted=1, updated_at=? WHERE rule_id=? AND date>=? AND deleted=0 AND is_override=0", arguments: [now(), ruleId, item.date])
                return "Deleted \(item.name) from \(item.date) onward."
            }
            try db.execute(sql: "UPDATE items SET deleted=1, updated_at=? WHERE rule_id=?", arguments: [now(), ruleId])
            try db.execute(sql: "DELETE FROM recurring_rules WHERE id=?", arguments: [ruleId])
            return "Deleted the entire \(item.name) series."
        }
    }

    public func editOccurrence(id: Int64, scope: OccurrenceScope, changes: ItemChanges, endDate: String? = nil) throws -> String {
        try database.write { db in
            guard let original = try Item.fetchOne(db, key: id) else { return "Item not found." }
            if scope == .onlyThis || original.ruleId == nil {
                try apply(changes, to: id, db: db, override: scope == .onlyThis)
                return "Updated \(original.name) (\(original.date))."
            }
            guard let ruleId = original.ruleId else { return "Item not found." }
            if scope == .thisAndFuture {
                try db.execute(sql: "UPDATE recurring_rules SET anchor_date=?, end_date=? WHERE id=?", arguments: [original.date, endDate, ruleId])
                try db.execute(sql: "UPDATE items SET deleted=1, updated_at=? WHERE rule_id=? AND date>=? AND deleted=0", arguments: [now(), ruleId, original.date])
                let rule = try RecurringRule.fetchOne(db, key: ruleId)!
                var template = original; template.name = changes.name ?? original.name; template.amountCents = changes.amountCents ?? original.amountCents; template.type = changes.type ?? original.type; template.categoryId = changes.categoryId ?? original.categoryId; template.note = changes.note ?? original.note; template.priority = changes.priority ?? original.priority; template.id = nil; template.isOverride = false; template.deleted = false
                for occurrence in RecurrenceEngine.occurrences(for: rule, from: original.date, through: endDate ?? "2099-12-31") { var copy = template; copy.date = occurrence.date; copy.createdAt = now(); copy.updatedAt = copy.createdAt; try copy.insert(db) }
                return "Updated \(template.name) from \(original.date) onward."
            }
            try db.execute(sql: "UPDATE items SET name=COALESCE(?,name), amount_cents=COALESCE(?,amount_cents), type=COALESCE(?,type), category_id=COALESCE(?,category_id), note=COALESCE(?,note), priority=COALESCE(?,priority), is_override=0, updated_at=? WHERE rule_id=? AND deleted=0", arguments: [changes.name, changes.amountCents, changes.type?.rawValue, changes.categoryId, changes.note, changes.priority, now(), ruleId])
            return "Updated all occurrences of \(changes.name ?? original.name)."
        }
    }

    private func apply(_ changes: ItemChanges, to id: Int64, db: Database, override: Bool) throws {
        let current = try Item.fetchOne(db, key: id)!
        var updated = current; updated.name = changes.name ?? current.name; updated.amountCents = changes.amountCents ?? current.amountCents; updated.type = changes.type ?? current.type; updated.date = changes.date ?? current.date; updated.categoryId = changes.categoryId ?? current.categoryId; updated.note = changes.note ?? current.note; updated.priority = changes.priority ?? current.priority; updated.isOverride = override; updated.updatedAt = now(); try updated.update(db)
    }
    private func now() -> String { ISO8601DateFormatter().string(from: Date()) }
    private func today() -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    private func cents(_ value: String) -> Int? { let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal; guard let decimal = formatter.number(from: value)?.decimalValue else { return nil }; return NSDecimalNumber(decimal: decimal * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).intValue }
    private func validDate(_ value: String) -> Bool { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false }
    private func dayBefore(_ value: String) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let date = f.date(from: value)!; return f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: date)!) }
}

private extension String { var emptyAsNil: String? { isEmpty ? nil : self } }
