import Foundation
import GRDB

public enum BackupService {
    /// Checkpoints the WAL and copies the database plus any sidecar state to a user-selected URL.
    /// Callers should present NSSavePanel; this service deliberately has no UI dependency.
    public static func copy(database: DatabaseQueue, to destination: URL, source: URL = BudgetCalendarPaths.database) throws {
        try database.write { db in try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
    /// Restores a user-selected SQLite backup and preserves the current primary file beside it first.
    @discardableResult public static func restore(backup: URL, to destination: URL = BudgetCalendarPaths.database) throws -> URL? {
        guard backup.standardizedFileURL != destination.standardizedFileURL else { throw DatabaseError.invalidSchema("the selected backup is already the active database") }
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".budget-restore-\(UUID().uuidString).sqlite")
        defer { try? removeDatabaseFiles(at: temporary, manager: manager) }
        try copyDatabaseFiles(from: backup, to: temporary, manager: manager)
        try validateDatabase(at: temporary)
        var preserved: URL?
        let hadActiveDatabase = manager.fileExists(atPath: destination.path)
        if hadActiveDatabase {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let saved = destination.deletingLastPathComponent().appendingPathComponent("budget-before-restore-\(stamp).sqlite")
            do { try moveDatabaseFiles(from: destination, to: saved, manager: manager) }
            catch {
                // A companion may already have moved. Put every moved file back before aborting.
                try? moveDatabaseFiles(from: saved, to: destination, manager: manager)
                throw error
            }
            preserved = saved
        }
        if !hadActiveDatabase { try removeDatabaseFiles(at: destination, manager: manager) }
        do { try moveDatabaseFiles(from: temporary, to: destination, manager: manager) }
        catch {
            try? removeDatabaseFiles(at: destination, manager: manager)
            if let preserved { try? moveDatabaseFiles(from: preserved, to: destination, manager: manager) }
            throw error
        }
        return preserved
    }
    private static func companionURLs(for database: URL) -> [URL] { [database, URL(fileURLWithPath: database.path + "-wal"), URL(fileURLWithPath: database.path + "-shm")] }
    private static func copyDatabaseFiles(from source: URL, to destination: URL, manager: FileManager) throws { for (from, to) in zip(companionURLs(for: source), companionURLs(for: destination)) where manager.fileExists(atPath: from.path) { try manager.copyItem(at: from, to: to) } }
    private static func moveDatabaseFiles(from source: URL, to destination: URL, manager: FileManager) throws { for (from, to) in zip(companionURLs(for: source), companionURLs(for: destination)) where manager.fileExists(atPath: from.path) { try manager.moveItem(at: from, to: to) } }
    private static func removeDatabaseFiles(at database: URL, manager: FileManager) throws { for file in companionURLs(for: database) where manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) } }
    private static func validateDatabase(at path: URL) throws { let queue = try DatabaseQueue(path: path.path); let result = try queue.read { db in try String.fetchOne(db, sql: "PRAGMA quick_check") ?? "unknown" }; guard result.lowercased() == "ok" else { throw DatabaseError.corruptDatabase(path, result) } }
}
