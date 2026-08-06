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
    public func item(id: Int64) throws -> Item? { try database.read { db in try Item.fetchOne(db, key: id) } }
    public func categories() throws -> [Category] { try database.read { db in try Category.fetchAll(db, sql: "SELECT * FROM categories ORDER BY sort_order, id") } }
    public func rules() throws -> [RecurringRule] { try database.read { db in try RecurringRule.fetchAll(db, sql: "SELECT * FROM recurring_rules ORDER BY anchor_date, id") } }
    public func setting(_ key: String) throws -> String? { try database.read { db in try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key=?", arguments: [key]) } }
    public func setSetting(_ key: String, value: String) throws { try database.write { db in try db.execute(sql: "INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [key, value]) } }

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
    private func dayBefore(_ value: String) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let date = f.date(from: value)!; return f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: date)!) }
}
