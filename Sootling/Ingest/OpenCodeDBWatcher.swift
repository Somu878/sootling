import Foundation
import OSLog
import SQLite3

public final class OpenCodeDBWatcher {
    public static let log = Logger(subsystem: "app.sootling", category: "opencode-db")

    private let dbURL: URL
    private var openCodeDB: OpaquePointer?
    private var lastTimestamp: Int64
    private let onEvent: (UsageEvent) -> Void
    private let onError: (String) -> Void
    private let queue = DispatchQueue(label: "app.sootling.opencode-db", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isScanning = false

    public init(onEvent: @escaping (UsageEvent) -> Void, onError: @escaping (String) -> Void = { OpenCodeDBWatcher.log.error("\($0, privacy: .public)") }) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dbURL = home.appendingPathComponent(".local/share/opencode/opencode.db")
        lastTimestamp = 0
        self.onEvent = onEvent
        self.onError = onError
    }

    public func start() {
        stop()
        do {
            try openDB()
        } catch {
            onError("OpenCodeDB: \(error.localizedDescription)")
            return
        }
        queue.async { [weak self] in
            self?.scanOnce()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.scanOnce()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        if let db = openCodeDB {
            sqlite3_close(db)
            openCodeDB = nil
        }
    }

    deinit {
        stop()
    }

    private func openDB() throws {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw NSError(domain: "OpenCodeDB", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "opencode.db not found at \(dbURL.path)"])
        }
        let status = sqlite3_open_v2(dbURL.path, &openCodeDB, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK else {
            let msg = openCodeDB
                .map { String(cString: sqlite3_errmsg($0)) }
                .map { ": \($0)" } ?? ""
            throw NSError(domain: "OpenCodeDB", code: Int(status),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to open opencode.db\(msg)"])
        }
    }

    private func ensureDB() {
        if openCodeDB == nil {
            try? openDB()
        }
    }

    public func scanOnce() {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        ensureDB()
        guard let db = openCodeDB else { return }

        let sql = """
        SELECT id, time_created, data
        FROM message
        WHERE time_created > ?
        ORDER BY time_created ASC
        LIMIT 100;
        """

        var statement: OpaquePointer?
        let prepStatus = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepStatus == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            onError("OpenCodeDB prepare: \(msg)")
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, lastTimestamp)

        var events: [UsageEvent] = []
        var maxTimestamp = lastTimestamp

        var result: Int32
        while true {
            result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let ts = sqlite3_column_int64(statement, 1)
                if ts > maxTimestamp { maxTimestamp = ts }

                guard let dataPtr = sqlite3_column_text(statement, 2) else { continue }
                let data = String(cString: dataPtr)
                let messageId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let timestamp = Date(timeIntervalSince1970: Double(ts) / 1000)

                guard let event = parseMessageData(data, messageId: messageId, timestamp: timestamp) else { continue }
                events.append(event)
            } else if result == SQLITE_DONE {
                break
            } else {
                let msg = String(cString: sqlite3_errmsg(db))
                onError("OpenCodeDB step: \(msg)")
                break
            }
        }

        lastTimestamp = maxTimestamp

        for event in events {
            onEvent(event)
        }
    }

    private func parseMessageData(_ json: String, messageId: String, timestamp: Date) -> UsageEvent? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let role = object["role"] as? String, role == "assistant",
              let modelID = object["modelID"] as? String,
              let tokens = object["tokens"] as? [String: Any] else {
            return nil
        }

        let input = tokens["input"] as? Int ?? 0
        let output = tokens["output"] as? Int ?? 0
        let reasoning = tokens["reasoning"] as? Int ?? 0

        var cacheRead = 0
        var cacheWrite = 0
        if let cache = tokens["cache"] as? [String: Any] {
            cacheRead = cache["read"] as? Int ?? 0
            cacheWrite = cache["write"] as? Int ?? 0
        }

        let total = input + output + reasoning + cacheRead + cacheWrite
        guard total > 0 else { return nil }

        return UsageEvent(
            id: "opencode-db-\(messageId)",
            timestamp: timestamp,
            source: .openCode,
            model: modelID,
            tokensIn: input + cacheRead + cacheWrite,
            tokensOut: output + reasoning,
            cachedInputTokens: cacheRead
        )
    }
}
