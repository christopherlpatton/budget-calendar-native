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
}
