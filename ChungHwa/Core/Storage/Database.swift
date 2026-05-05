import Foundation
import OSLog
import SQLite3

/// Single SQLite database under Application Support / ChungHwa, replacing
/// the per-store JSON-on-disk schemes (proxy-delays, geoip-cache,
/// traffic-history). Schema is bootstrapped on first open; existing JSON
/// files are migrated once and then deleted.
@MainActor
final class Database {
    static let shared = Database()

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "db")
    private var db: OpaquePointer?

    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1)!,
        to: sqlite3_destructor_type.self
    )

    /// Default path: `~/Library/Application Support/ChungHwa/data.sqlite`.
    static var defaultPath: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChungHwa", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("data.sqlite")
    }

    var isOpen: Bool { db != nil }

    private convenience init() {
        self.init(path: Self.defaultPath)
    }

    /// Test injection point — opens (or creates) the database at `path`.
    init(path: URL) {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path.path, &handle, flags, nil)
        if rc != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            log.error("open failed (\(rc, privacy: .public)): \(msg, privacy: .public)")
            if let handle { sqlite3_close_v2(handle) }
            self.db = nil
            return
        }
        self.db = handle
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")
        exec("PRAGMA foreign_keys = ON;")
        bootstrapSchema()
        migrateLegacyJSONIfNeeded(supportDir: path.deletingLastPathComponent())
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - Schema

    private func bootstrapSchema() {
        exec("""
            CREATE TABLE IF NOT EXISTS schema_version (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                version INTEGER NOT NULL
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS proxy_delays (
                name TEXT PRIMARY KEY,
                delay_ms INTEGER NOT NULL,
                tested_at REAL NOT NULL
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS geoip_cache (
                ip TEXT PRIMARY KEY,
                country TEXT NOT NULL,
                fetched_at REAL NOT NULL
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS traffic_history (
                minute_start INTEGER PRIMARY KEY,
                up_bytes INTEGER NOT NULL,
                down_bytes INTEGER NOT NULL
            );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_geoip_fetched_at ON geoip_cache(fetched_at);")
        exec("CREATE INDEX IF NOT EXISTS idx_traffic_history_minute ON traffic_history(minute_start);")

        if currentSchemaVersion() == 0 {
            exec("INSERT OR REPLACE INTO schema_version (id, version) VALUES (1, 1);")
        }
    }

    private func currentSchemaVersion() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT version FROM schema_version WHERE id = 1;", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Proxy delays

    func loadAllProxyDelays() -> [String: (delay: Int, testedAt: Date)] {
        guard let db else { return [:] }
        var out: [String: (delay: Int, testedAt: Date)] = [:]
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT name, delay_ms, tested_at FROM proxy_delays;", -1, &stmt, nil) == SQLITE_OK else {
            log.error("loadAllProxyDelays prepare failed: \(self.lastError(), privacy: .public)")
            return [:]
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cstr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: cstr)
            let delay = Int(sqlite3_column_int64(stmt, 1))
            let ts = sqlite3_column_double(stmt, 2)
            out[name] = (delay: delay, testedAt: Date(timeIntervalSince1970: ts))
        }
        return out
    }

    func upsertProxyDelay(name: String, delay: Int, testedAt: Date) {
        upsertProxyDelays([(name: name, delay: delay, testedAt: testedAt)])
    }

    func upsertProxyDelays(_ entries: [(name: String, delay: Int, testedAt: Date)]) {
        guard let db, !entries.isEmpty else { return }
        let sql = """
            INSERT INTO proxy_delays (name, delay_ms, tested_at)
            VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                delay_ms = excluded.delay_ms,
                tested_at = excluded.tested_at;
        """
        exec("BEGIN IMMEDIATE;")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("upsertProxyDelays prepare failed: \(self.lastError(), privacy: .public)")
            exec("ROLLBACK;")
            return
        }
        defer { sqlite3_finalize(stmt) }
        for entry in entries {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, entry.name, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, sqlite3_int64(entry.delay))
            sqlite3_bind_double(stmt, 3, entry.testedAt.timeIntervalSince1970)
            if sqlite3_step(stmt) != SQLITE_DONE {
                log.error("upsertProxyDelays step failed: \(self.lastError(), privacy: .public)")
            }
        }
        exec("COMMIT;")
    }

    // MARK: - GeoIP cache

    func loadAllGeoIP() -> [String: String] {
        guard let db else { return [:] }
        var out: [String: String] = [:]
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT ip, country FROM geoip_cache;", -1, &stmt, nil) == SQLITE_OK else {
            log.error("loadAllGeoIP prepare failed: \(self.lastError(), privacy: .public)")
            return [:]
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ipPtr = sqlite3_column_text(stmt, 0),
                  let cPtr = sqlite3_column_text(stmt, 1) else { continue }
            out[String(cString: ipPtr)] = String(cString: cPtr)
        }
        return out
    }

    func upsertGeoIP(ip: String, country: String, fetchedAt: Date) {
        upsertGeoIPs([(ip: ip, country: country, fetchedAt: fetchedAt)])
    }

    func upsertGeoIPs(_ entries: [(ip: String, country: String, fetchedAt: Date)]) {
        guard let db, !entries.isEmpty else { return }
        let sql = """
            INSERT INTO geoip_cache (ip, country, fetched_at)
            VALUES (?, ?, ?)
            ON CONFLICT(ip) DO UPDATE SET
                country = excluded.country,
                fetched_at = excluded.fetched_at;
        """
        exec("BEGIN IMMEDIATE;")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("upsertGeoIPs prepare failed: \(self.lastError(), privacy: .public)")
            exec("ROLLBACK;")
            return
        }
        defer { sqlite3_finalize(stmt) }
        for entry in entries {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, entry.ip, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.country, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, entry.fetchedAt.timeIntervalSince1970)
            if sqlite3_step(stmt) != SQLITE_DONE {
                log.error("upsertGeoIPs step failed: \(self.lastError(), privacy: .public)")
            }
        }
        exec("COMMIT;")
    }

    // MARK: - Traffic history

    func loadTrafficHistory(since cutoff: Date) -> [(minuteStart: Date, up: Int, down: Int)] {
        guard let db else { return [] }
        var out: [(minuteStart: Date, up: Int, down: Int)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
            SELECT minute_start, up_bytes, down_bytes
            FROM traffic_history
            WHERE minute_start >= ?
            ORDER BY minute_start ASC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("loadTrafficHistory prepare failed: \(self.lastError(), privacy: .public)")
            return []
        }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(cutoff.timeIntervalSince1970))
        while sqlite3_step(stmt) == SQLITE_ROW {
            let minute = sqlite3_column_int64(stmt, 0)
            let up = Int(sqlite3_column_int64(stmt, 1))
            let down = Int(sqlite3_column_int64(stmt, 2))
            out.append((
                minuteStart: Date(timeIntervalSince1970: TimeInterval(minute)),
                up: up,
                down: down
            ))
        }
        return out
    }

    func upsertTrafficBucket(minuteStart: Date, up: Int, down: Int) {
        guard let db else { return }
        let sql = """
            INSERT INTO traffic_history (minute_start, up_bytes, down_bytes)
            VALUES (?, ?, ?)
            ON CONFLICT(minute_start) DO UPDATE SET
                up_bytes = excluded.up_bytes,
                down_bytes = excluded.down_bytes;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("upsertTrafficBucket prepare failed: \(self.lastError(), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(minuteStart.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(up))
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(down))
        if sqlite3_step(stmt) != SQLITE_DONE {
            log.error("upsertTrafficBucket step failed: \(self.lastError(), privacy: .public)")
        }
    }

    func pruneTrafficHistory(keepHours: Int) {
        guard let db else { return }
        let cutoff = Date().addingTimeInterval(-Double(keepHours) * 3600)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM traffic_history WHERE minute_start < ?;", -1, &stmt, nil) == SQLITE_OK else {
            log.error("pruneTrafficHistory prepare failed: \(self.lastError(), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(cutoff.timeIntervalSince1970))
        if sqlite3_step(stmt) != SQLITE_DONE {
            log.error("pruneTrafficHistory step failed: \(self.lastError(), privacy: .public)")
        }
    }

    // MARK: - Test helpers

    func deleteAllProxyDelays() { exec("DELETE FROM proxy_delays;") }
    func deleteAllGeoIP()       { exec("DELETE FROM geoip_cache;") }
    func deleteAllTraffic()     { exec("DELETE FROM traffic_history;") }

    // MARK: - Migration

    private struct LegacyPersistedDelay: Decodable {
        let delay: Int
        let testedAt: Date
    }

    private struct LegacyTrafficBucket: Decodable {
        let minuteStart: Date
        let downBytes: Int
        let upBytes: Int
    }

    private func migrateLegacyJSONIfNeeded(supportDir: URL) {
        migrateProxyDelaysJSON(at: supportDir.appendingPathComponent("proxy-delays.json"))
        migrateGeoIPJSON(at: supportDir.appendingPathComponent("geoip-cache.json"))
        migrateTrafficHistoryJSON(at: supportDir.appendingPathComponent("traffic-history.json"))
    }

    private func migrateProxyDelaysJSON(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if rowCount(table: "proxy_delays") > 0 {
            log.info("skip proxy-delays.json migration: table already populated")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: LegacyPersistedDelay].self, from: data)
            let entries = decoded.map { (name: $0.key, delay: $0.value.delay, testedAt: $0.value.testedAt) }
            upsertProxyDelays(entries)
            try? FileManager.default.removeItem(at: url)
            log.info("migrated \(entries.count, privacy: .public) proxy delays from JSON")
        } catch {
            log.error("proxy-delays.json migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func migrateGeoIPJSON(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if rowCount(table: "geoip_cache") > 0 {
            log.info("skip geoip-cache.json migration: table already populated")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            let now = Date()
            let entries = decoded.map { (ip: $0.key, country: $0.value, fetchedAt: now) }
            upsertGeoIPs(entries)
            try? FileManager.default.removeItem(at: url)
            log.info("migrated \(entries.count, privacy: .public) geoip entries from JSON")
        } catch {
            log.error("geoip-cache.json migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func migrateTrafficHistoryJSON(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if rowCount(table: "traffic_history") > 0 {
            log.info("skip traffic-history.json migration: table already populated")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([LegacyTrafficBucket].self, from: data)
            for bucket in decoded {
                upsertTrafficBucket(
                    minuteStart: bucket.minuteStart,
                    up: bucket.upBytes,
                    down: bucket.downBytes
                )
            }
            try? FileManager.default.removeItem(at: url)
            log.info("migrated \(decoded.count, privacy: .public) traffic buckets from JSON")
        } catch {
            log.error("traffic-history.json migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func rowCount(table: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Plumbing

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.flatMap { String(cString: $0) } ?? "?"
            log.error("exec failed (\(rc, privacy: .public)) [\(sql, privacy: .public)]: \(msg, privacy: .public)")
            if let err { sqlite3_free(err) }
            return false
        }
        return true
    }

    private func lastError() -> String {
        guard let db else { return "no handle" }
        return String(cString: sqlite3_errmsg(db))
    }
}
