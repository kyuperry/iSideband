import Foundation
import SQLite3

/// Transactional storage for durable messaging state. Values remain Codable
/// JSON while SQLite WAL and full synchronous writes protect queue mutations
/// from app termination and interrupted device writes.
final class MessageDatabase: @unchecked Sendable {
    static let shared = MessageDatabase()

    private let lock = NSLock()
    private var database: OpaquePointer?
    private let transientDestructor = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent(
                "iSideband",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let path = directory
                .appendingPathComponent("Messages.sqlite3")
                .path
            guard sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE |
                    SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK else {
                closeDatabase()
                return
            }
            // UI-facing stores currently perform short synchronous reads and
            // writes. Never let lock contention stall the main actor for
            // several seconds; WAL makes a short retry window sufficient.
            sqlite3_busy_timeout(database, 250)
            guard execute("PRAGMA journal_mode=WAL;"),
                  execute("PRAGMA synchronous=NORMAL;"),
                  execute("PRAGMA foreign_keys=ON;"),
                  execute(
                    """
                    CREATE TABLE IF NOT EXISTS message_state (
                        key TEXT PRIMARY KEY NOT NULL,
                        value BLOB NOT NULL,
                        updated_at REAL NOT NULL
                    );
                    """
                  ) else {
                closeDatabase()
                return
            }
        } catch {
            closeDatabase()
        }
    }

    deinit { closeDatabase() }

    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM message_state WHERE key = ?1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        sqlite3_bind_text(statement, 1, key, -1, transientDestructor)
            == SQLITE_OK,
        sqlite3_step(statement) == SQLITE_ROW,
        let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        return Data(
            bytes: bytes,
            count: Int(sqlite3_column_bytes(statement, 0))
        )
    }

    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            database,
            """
            INSERT INTO message_state (key, value, updated_at)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        sqlite3_bind_text(statement, 1, key, -1, transientDestructor)
            == SQLITE_OK else {
            return false
        }
        let bindResult = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                2,
                bytes.baseAddress,
                Int32(bytes.count),
                transientDestructor
            )
        }
        guard bindResult == SQLITE_OK,
              sqlite3_bind_double(
                statement,
                3,
                Date().timeIntervalSince1970
              ) == SQLITE_OK else {
            return false
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    @discardableResult
    func removeValue(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            database,
            "DELETE FROM message_state WHERE key = ?1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        sqlite3_bind_text(statement, 1, key, -1, transientDestructor)
            == SQLITE_OK else {
            return false
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func execute(_ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close_v2(database)
            self.database = nil
        }
    }
}
