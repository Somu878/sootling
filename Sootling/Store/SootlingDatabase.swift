import Foundation
import SQLite3

public enum SootlingDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): "SQLite open failed: \(message)"
        case .prepareFailed(let message): "SQLite prepare failed: \(message)"
        case .stepFailed(let message): "SQLite step failed: \(message)"
        }
    }
}

public struct DayTotal: Equatable, Sendable, Identifiable {
    public var id: Date { day }
    public let day: Date
    public let gCO2e: Double

    public init(day: Date, gCO2e: Double) {
        self.day = day
        self.gCO2e = gCO2e
    }
}

public final class SootlingDatabase {
    private var db: OpaquePointer?
    private let url: URL
    /// macOS ships SQLite in multi-thread mode: a connection must not be used from two
    /// threads at once or it corrupts its heap. Every public method hops through this
    /// serial queue; FULLMUTEX below is a second line of defense.
    private let queue = DispatchQueue(label: "app.sootling.database")

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            throw SootlingDatabaseError.openFailed(lastErrorMessage)
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Sootling", isDirectory: true)
            .appendingPathComponent("sootling.sqlite")
    }

    /// Returns true when the event was actually inserted, false when its id was
    /// already recorded (re-parsed file, restart catch-up).
    @discardableResult
    public func insert(event: UsageEvent, estimate: EmissionEstimate) throws -> Bool {
        try queue.sync {
            let sql = """
            INSERT OR IGNORE INTO usage_events (
                id, timestamp, source, model, tokens_in, tokens_out, cached_input_tokens,
                energy_wh, gco2e, min_gco2e, max_gco2e, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bindText(event.id, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
            bindText(event.source.rawValue, to: 3, in: statement)
            bindText(event.model, to: 4, in: statement)
            sqlite3_bind_int64(statement, 5, Int64(event.tokensIn))
            sqlite3_bind_int64(statement, 6, Int64(event.tokensOut))
            sqlite3_bind_int64(statement, 7, Int64(event.cachedInputTokens))
            sqlite3_bind_double(statement, 8, estimate.energyWh.mean)
            sqlite3_bind_double(statement, 9, estimate.gCO2e.mean)
            sqlite3_bind_double(statement, 10, estimate.gCO2e.min)
            sqlite3_bind_double(statement, 11, estimate.gCO2e.max)
            sqlite3_bind_double(statement, 12, Date().timeIntervalSince1970)
            try stepDone(statement)
            return sqlite3_changes(db) > 0
        }
    }

    public func dailyImpact(since startOfDay: Date) throws -> DailyImpact {
        try queue.sync {
            let sql = """
            SELECT COUNT(*),
                   COALESCE(SUM(energy_wh), 0),
                   COALESCE(SUM(gco2e), 0),
                   COALESCE(SUM(min_gco2e), 0),
                   COALESCE(SUM(max_gco2e), 0)
            FROM usage_events
            WHERE timestamp >= ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, startOfDay.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return .zero
            }
            return DailyImpact(
                eventCount: Int(sqlite3_column_int64(statement, 0)),
                energyWh: sqlite3_column_double(statement, 1),
                gCO2e: sqlite3_column_double(statement, 2),
                minGCO2e: sqlite3_column_double(statement, 3),
                maxGCO2e: sqlite3_column_double(statement, 4)
            )
        }
    }

    public func recentEvents(limit: Int = 20) throws -> [StoredUsageEvent] {
        try queue.sync {
            let sql = """
            SELECT id, timestamp, source, model, tokens_in, tokens_out, cached_input_tokens,
                   energy_wh, gco2e, min_gco2e, max_gco2e
            FROM usage_events
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(limit))

            var events: [StoredUsageEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
            let sourceRaw = columnString(statement, 2) ?? UsageSource.manual.rawValue
            let source = UsageSource(rawValue: sourceRaw) ?? .manual
            events.append(
                StoredUsageEvent(
                    id: columnString(statement, 0) ?? UUID().uuidString,
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    source: source,
                    model: columnString(statement, 3) ?? "unknown",
                    tokensIn: Int(sqlite3_column_int64(statement, 4)),
                    tokensOut: Int(sqlite3_column_int64(statement, 5)),
                    cachedInputTokens: Int(sqlite3_column_int64(statement, 6)),
                    energyWh: sqlite3_column_double(statement, 7),
                    gCO2e: sqlite3_column_double(statement, 8),
                    minGCO2e: sqlite3_column_double(statement, 9),
                    maxGCO2e: sqlite3_column_double(statement, 10)
                )
            )
            }
            return events
        }
    }

    /// Per-day gCO2e totals for the trailing `days` days (missing days filled
    /// with zero), oldest first and ending with today.
    public func dailyTotals(days: Int, calendar: Calendar = .current) throws -> [DayTotal] {
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        let sums: [String: Double] = try queue.sync {
            let sql = """
            SELECT date(timestamp, 'unixepoch', 'localtime') AS day, SUM(gco2e)
            FROM usage_events
            WHERE timestamp >= ?
            GROUP BY day;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)

            var sums: [String: Double] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                if let day = columnString(statement, 0) {
                    sums[day] = sqlite3_column_double(statement, 1)
                }
            }
            return sums
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<days).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: start) else {
                return nil
            }
            return DayTotal(day: day, gCO2e: sums[formatter.string(from: day)] ?? 0)
        }
    }

    public func analytics(since startDate: Date, limit: Int = 5) throws -> UsageAnalytics {
        let byModel = try groupedAnalytics(
            since: startDate,
            groupExpression: "model",
            limit: limit
        )
        let bySource = try groupedAnalytics(
            since: startDate,
            groupExpression: "source",
            limit: 100
        )
        let providers = aggregateProviders(from: bySource)
            .prefix(limit)
            .map { $0 }
        return UsageAnalytics(providers: Array(providers), models: byModel)
    }

    private func groupedAnalytics(
        since startDate: Date,
        groupExpression: String,
        limit: Int
    ) throws -> [AnalyticsRow] {
        try queue.sync {
            let sql = """
            SELECT \(groupExpression),
                   COUNT(*),
                   COALESCE(SUM(tokens_in), 0),
                   COALESCE(SUM(tokens_out), 0),
                   COALESCE(SUM(gco2e), 0)
            FROM usage_events
            WHERE timestamp >= ?
            GROUP BY \(groupExpression)
            ORDER BY SUM(gco2e) DESC
            LIMIT ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, Int64(limit))

            var rows: [AnalyticsRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(
                    AnalyticsRow(
                        name: columnString(statement, 0) ?? "Unknown",
                        eventCount: Int(sqlite3_column_int64(statement, 1)),
                        tokensIn: Int(sqlite3_column_int64(statement, 2)),
                        tokensOut: Int(sqlite3_column_int64(statement, 3)),
                        gCO2e: sqlite3_column_double(statement, 4)
                    )
                )
            }
            return rows
        }
    }

    private func aggregateProviders(from sourceRows: [AnalyticsRow]) -> [AnalyticsRow] {
        var totals: [String: AnalyticsRow] = [:]
        for row in sourceRows {
            let provider = providerName(forSource: row.name)
            var current = totals[provider] ?? AnalyticsRow(
                name: provider,
                eventCount: 0,
                tokensIn: 0,
                tokensOut: 0,
                gCO2e: 0
            )
            current.eventCount += row.eventCount
            current.tokensIn += row.tokensIn
            current.tokensOut += row.tokensOut
            current.gCO2e += row.gCO2e
            totals[provider] = current
        }
        return totals.values.sorted { $0.gCO2e > $1.gCO2e }
    }

    private func providerName(forSource source: String) -> String {
        switch UsageSource(rawValue: source) {
        case .claudeCode, .claudeWeb:
            return "Anthropic"
        case .codexCLI, .openCode, .chatgptWeb:
            return "OpenAI"
        case .geminiCLI, .geminiWeb:
            return "Google"
        case .manual, .none:
            return "Other"
        }
    }

    public func offset(for path: String) throws -> UInt64 {
        try queue.sync {
            let statement = try prepare("SELECT byte_offset FROM file_offsets WHERE path = ?;")
            defer { sqlite3_finalize(statement) }
            bindText(path, to: 1, in: statement)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }
            return UInt64(sqlite3_column_int64(statement, 0))
        }
    }

    public func setOffset(_ offset: UInt64, for path: String) throws {
        try queue.sync {
            let sql = """
            INSERT INTO file_offsets (path, byte_offset, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                byte_offset = excluded.byte_offset,
                updated_at = excluded.updated_at;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindText(path, to: 1, in: statement)
            sqlite3_bind_int64(statement, 2, Int64(offset))
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    public func codexSnapshot(for path: String) throws -> CodexTokenSnapshot? {
        try queue.sync {
            let sql = """
            SELECT input_tokens, cached_input_tokens, output_tokens, total_tokens
            FROM codex_snapshots
            WHERE path = ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindText(path, to: 1, in: statement)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return CodexTokenSnapshot(
                inputTokens: Int(sqlite3_column_int64(statement, 0)),
                cachedInputTokens: Int(sqlite3_column_int64(statement, 1)),
                outputTokens: Int(sqlite3_column_int64(statement, 2)),
                totalTokens: Int(sqlite3_column_int64(statement, 3))
            )
        }
    }

    public func setCodexSnapshot(_ snapshot: CodexTokenSnapshot, for path: String) throws {
        try queue.sync {
            let sql = """
            INSERT INTO codex_snapshots (
                path, input_tokens, cached_input_tokens, output_tokens, total_tokens, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                input_tokens = excluded.input_tokens,
                cached_input_tokens = excluded.cached_input_tokens,
                output_tokens = excluded.output_tokens,
                total_tokens = excluded.total_tokens,
                updated_at = excluded.updated_at;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindText(path, to: 1, in: statement)
            sqlite3_bind_int64(statement, 2, Int64(snapshot.inputTokens))
            sqlite3_bind_int64(statement, 3, Int64(snapshot.cachedInputTokens))
            sqlite3_bind_int64(statement, 4, Int64(snapshot.outputTokens))
            sqlite3_bind_int64(statement, 5, Int64(snapshot.totalTokens))
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    private func migrate() throws {
        try execute("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS usage_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            source TEXT NOT NULL,
            model TEXT NOT NULL,
            tokens_in INTEGER NOT NULL,
            tokens_out INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            energy_wh REAL NOT NULL,
            gco2e REAL NOT NULL,
            min_gco2e REAL NOT NULL,
            max_gco2e REAL NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_usage_events_timestamp ON usage_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_usage_events_source ON usage_events(source);

        CREATE TABLE IF NOT EXISTS file_offsets (
            path TEXT PRIMARY KEY,
            byte_offset INTEGER NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS codex_snapshots (
            path TEXT PRIMARY KEY,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw SootlingDatabaseError.stepFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SootlingDatabaseError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SootlingDatabaseError.stepFailed(lastErrorMessage)
        }
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private var lastErrorMessage: String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "unknown error"
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
