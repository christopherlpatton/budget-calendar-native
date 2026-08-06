import Foundation
import GRDB
#if os(macOS)
import Darwin
#endif

public enum DatabaseError: Error, LocalizedError {
    case unsupportedFutureSchema(Int, Int)
    case lockUnavailable(URL)
    case invalidSchema(String)
    public var errorDescription: String? {
        switch self {
        case let .unsupportedFutureSchema(found, supported): "Database schema v\(found) is newer than supported v\(supported)."
        case let .lockUnavailable(url): "Budget Calendar is already open or its database lock is unavailable: \(url.path)"
        case let .invalidSchema(message): "The Budget Calendar database is not compatible: \(message)"
        }
    }
}

public enum BudgetCalendarPaths {
    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Budget Calendar", isDirectory: true)
    }
    public static var database: URL { applicationSupport.appendingPathComponent("budget.sqlite") }
    public static var lock: URL { applicationSupport.appendingPathComponent("budget.sqlite.lock") }
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
            try DatabaseMigrations.migrate(database)
            let version = try database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
            guard version <= Self.supportedSchemaVersion else { throw DatabaseError.unsupportedFutureSchema(version, Self.supportedSchemaVersion) }
            try validateSchema()
        } catch {
            releaseLock()
            throw error
        }
    }

    deinit { releaseLock() }

    private func acquireLock() throws {
        #if os(macOS)
        let lockURL = path.deletingPathExtension().appendingPathExtension("lock")
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
}
