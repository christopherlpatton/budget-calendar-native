import Foundation
import GRDB
#if os(macOS)
import Darwin
#endif

public enum DatabaseError: Error, LocalizedError {
    case unsupportedFutureSchema(Int, Int)
    case lockUnavailable(URL)
    case invalidSchema(String)
    case corruptDatabase(URL, String)
    case unreadableDatabase(URL, String)
    public var errorDescription: String? {
        switch self {
        case let .unsupportedFutureSchema(found, supported): "Database schema v\(found) is newer than supported v\(supported)."
        case let .lockUnavailable(url): "Budget Calendar is already open or its database lock is unavailable: \(url.path)"
        case let .invalidSchema(message): "The Budget Calendar database is not compatible: \(message)"
        case let .corruptDatabase(url, detail): "The Budget Calendar database appears corrupt at \(url.path): \(detail). Restore a SQLite backup or make a copy before attempting recovery."
        case let .unreadableDatabase(url, detail): "The Budget Calendar database could not be read at \(url.path): \(detail). Close the other app and restore a known-good SQLite backup if needed."
        }
    }
}

public enum BudgetCalendarPaths {
    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Budget Calendar", isDirectory: true)
    }
    public static var database: URL { applicationSupport.appendingPathComponent("budget.sqlite") }
    public static var lock: URL { lock(for: database) }
    public static func lock(for database: URL) -> URL { database.deletingPathExtension().appendingPathExtension("lock") }
}

public final class DatabaseCoordinator {
    public static let supportedSchemaVersion = 6
    public let path: URL
    public private(set) var database: DatabaseQueue!
    private var lockDescriptor: Int32 = -1

    public init(path: URL = BudgetCalendarPaths.database) throws {
        self.path = path
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try acquireLock()
        do {
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
            }
            database = try DatabaseQueue(path: path.path, configuration: configuration)
            try verifyIntegrity()
            try DatabaseMigrations.migrate(database)
            let version = try database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
            guard version <= Self.supportedSchemaVersion else { throw DatabaseError.unsupportedFutureSchema(version, Self.supportedSchemaVersion) }
            try validateSchema()
        } catch let error as DatabaseError {
            releaseLock()
            throw error
        } catch {
            releaseLock()
            if FileManager.default.fileExists(atPath: path.path) { throw DatabaseError.unreadableDatabase(path, error.localizedDescription) }
            throw error
        }
    }

    deinit { releaseLock() }

    private func acquireLock() throws {
        #if os(macOS)
        let lockURL = BudgetCalendarPaths.lock(for: path)
        lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            if lockDescriptor >= 0 { close(lockDescriptor); lockDescriptor = -1 }
            throw DatabaseError.lockUnavailable(lockURL)
        }
        #endif
    }
    private func releaseLock() {
        #if os(macOS)
        guard lockDescriptor >= 0 else { return }
        flock(lockDescriptor, LOCK_UN); close(lockDescriptor); lockDescriptor = -1
        #endif
    }
    private func validateSchema() throws {
        let required = ["settings", "categories", "recurring_rules", "items", "balance_adjustments", "audit_log"]
        try database.read { db in
            let tables = try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            let missing = required.filter { !tables.contains($0) }
            if !missing.isEmpty { throw DatabaseError.invalidSchema("missing tables: \(missing.joined(separator: ", "))") }
        }
    }
    private func verifyIntegrity() throws {
        let result = try database.read { db in try String.fetchOne(db, sql: "PRAGMA quick_check") ?? "unknown" }
        guard result.lowercased() == "ok" else { throw DatabaseError.corruptDatabase(path, result) }
    }
}
