import Foundation
import GRDB

public enum ItemType: String, Codable, Sendable { case deposit, bill, purchase }
public enum ItemStatus: String, Codable, Sendable { case planned, paid }
public enum RecurrenceKind: String, Codable, Sendable { case monthlyDate = "monthly_date", weekly, biweekly, monthlyNth = "monthly_nth" }

public struct Item: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    public var amountCents: Int
    public var type: ItemType
    public var date: String
    public var categoryId: Int64?
    public var note: String?
    public var priority: Int
    public var status: ItemStatus
    public var paidDate: String?
    public var ruleId: Int64?
    public var isOverride: Bool
    public var deleted: Bool
    public var assignmentOverride: Bool
    public var assignedDepositItemId: Int64?
    public var assignmentNote: String?
    public var movedFromDepositItemId: Int64?
    public var movedFromDate: String?
    public var createdAt: String
    public var updatedAt: String

    public init(id: Int64? = nil, name: String, amountCents: Int, type: ItemType, date: String,
                categoryId: Int64? = nil, note: String? = nil, priority: Int = 0,
                status: ItemStatus = .planned, paidDate: String? = nil, ruleId: Int64? = nil,
                isOverride: Bool = false, deleted: Bool = false, assignmentOverride: Bool = false,
                assignedDepositItemId: Int64? = nil, assignmentNote: String? = nil,
                movedFromDepositItemId: Int64? = nil, movedFromDate: String? = nil,
                createdAt: String = ISO8601DateFormatter().string(from: Date()),
                updatedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.name = name; self.amountCents = amountCents; self.type = type; self.date = date
        self.categoryId = categoryId; self.note = note; self.priority = priority; self.status = status
        self.paidDate = paidDate; self.ruleId = ruleId; self.isOverride = isOverride; self.deleted = deleted
        self.assignmentOverride = assignmentOverride; self.assignedDepositItemId = assignedDepositItemId
        self.assignmentNote = assignmentNote; self.movedFromDepositItemId = movedFromDepositItemId
        self.movedFromDate = movedFromDate; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public static let databaseTableName = "items"
    public enum Columns { public static let id = Column("id"); public static let date = Column("date"); public static let type = Column("type") }
    public enum CodingKeys: String, CodingKey {
        case id, name, amountCents = "amount_cents", type, date, categoryId = "category_id", note, priority, status
        case paidDate = "paid_date", ruleId = "rule_id", isOverride = "is_override", deleted
        case assignmentOverride = "assignment_override", assignedDepositItemId = "assigned_deposit_item_id"
        case assignmentNote = "assignment_note", movedFromDepositItemId = "moved_from_deposit_item_id"
        case movedFromDate = "moved_from_date", createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct Category: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?; public var name: String; public var color: String; public var kind: String
    public var isBuiltin: Bool; public var sortOrder: Int; public var incomeType: String?
    public static let databaseTableName = "categories"
    public enum CodingKeys: String, CodingKey { case id, name, color, kind, isBuiltin = "is_builtin", sortOrder = "sort_order", incomeType = "income_type" }
}

public struct RecurringRule: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?; public var kind: RecurrenceKind; public var anchorDate: String
    public var weekday: Int?; public var dayOfMonth: Int?; public var nth: Int?; public var endDate: String?
    public static let databaseTableName = "recurring_rules"
    public enum CodingKeys: String, CodingKey { case id, kind, anchorDate = "anchor_date", weekday, dayOfMonth = "day_of_month", nth, endDate = "end_date" }
}

public struct BalanceAdjustment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?; public var amountCents: Int; public var date: String; public var note: String?; public var createdAt: String
    public static let databaseTableName = "balance_adjustments"
    public enum CodingKeys: String, CodingKey { case id, amountCents = "amount_cents", date, note, createdAt = "created_at" }
}

public struct Setting: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var key: String; public var value: String
    public static let databaseTableName = "settings"
}
