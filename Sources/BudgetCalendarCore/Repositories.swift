import Foundation
import GRDB

public protocol ItemRepository {
    func items(in startDate: String, through endDate: String) throws -> [Item]
    func save(_ item: Item) throws -> Item
    func delete(id: Int64) throws
}

public final class GRDBItemRepository: ItemRepository {
    private let database: DatabaseQueue
    public init(database: DatabaseQueue) { self.database = database }
    public func items(in startDate: String, through endDate: String) throws -> [Item] {
        try database.read { db in try Item.fetchAll(db, sql: "SELECT * FROM items WHERE date >= ? AND date <= ? ORDER BY date, id", arguments: [startDate, endDate]) }
    }
    public func save(_ item: Item) throws -> Item {
        var value = item
        try database.write { db in try value.save(db) }
        return value
    }
    public func delete(id: Int64) throws { try database.write { db in try db.execute(sql: "UPDATE items SET deleted=1, updated_at=? WHERE id=?", arguments: [ISO8601DateFormatter().string(from: Date()), id]) } }
}
