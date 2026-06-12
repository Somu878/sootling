import CoreServices
import Foundation

public struct LogSourceDefinition: Equatable, Sendable {
    /// How files under this root are read.
    public enum ReadMode: Equatable, Sendable {
        /// Append-only JSONL: read new bytes past the persisted offset.
        case tailJSONL
        /// One JSON document per file, rewritten in place while streaming:
        /// re-parse the whole file whenever its size changes. Events must carry
        /// stable ids so re-parses dedupe in the store.
        case wholeFileJSON
    }

    public var root: URL
    public var source: UsageSource
    public var allowedExtensions: Set<String>
    public var readMode: ReadMode

    public init(
        root: URL,
        source: UsageSource,
        allowedExtensions: Set<String>,
        readMode: ReadMode = .tailJSONL
    ) {
        self.root = root
        self.source = source
        self.allowedExtensions = allowedExtensions
        self.readMode = readMode
    }

    public static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LogSourceDefinition] {
        [
            LogSourceDefinition(
                root: home.appendingPathComponent(".claude/projects", isDirectory: true),
                source: .claudeCode,
                allowedExtensions: ["jsonl"]
            ),
            LogSourceDefinition(
                root: home.appendingPathComponent(".codex/sessions", isDirectory: true),
                source: .codexCLI,
                allowedExtensions: ["jsonl"]
            ),
            LogSourceDefinition(
                root: home.appendingPathComponent(".gemini/tmp", isDirectory: true),
                source: .geminiCLI,
                allowedExtensions: ["json", "jsonl", "log"]
            ),
        ]
    }
}

public final class LogDirectoryWatcher {
    private let sources: [LogSourceDefinition]
    private let database: SootlingDatabase
    private let onEvent: (UsageEvent) -> Void
    private let queue = DispatchQueue(label: "app.sootling.log-watcher", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var eventStream: FSEventStreamRef?
    private var pendingScan: DispatchWorkItem?

    private let claudeParser = ClaudeCodeParser()
    private let codexParser = CodexCLIParser()
    private let geminiParser = GeminiCLIParser()

    public init(
        sources: [LogSourceDefinition] = LogSourceDefinition.defaults(),
        database: SootlingDatabase,
        onEvent: @escaping (UsageEvent) -> Void
    ) {
        self.sources = sources
        self.database = database
        self.onEvent = onEvent
    }

    /// Starts an `FSEventStream` for instant reactions, plus a slow polling timer
    /// as a safety net for missed events and for directories that don't exist yet.
    public func start(interval: TimeInterval = 5) {
        stop()

        // Initial catch-up scan so totals are correct on launch.
        queue.async { [weak self] in
            self?.scanOnce()
        }

        startEventStream()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.scanOnce()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        pendingScan?.cancel()
        pendingScan = nil
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    deinit {
        stop()
    }

    private func startEventStream() {
        let paths = sources
            .map { $0.root.path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else {
            // Nothing to watch yet; the polling timer will pick the dirs up once created.
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<LogDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleDebouncedScan()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    /// Coalesces bursts of file-system events into a single scan ~0.12s later so
    /// a flurry of writes (one prompt can append many lines) does one pass.
    private func scheduleDebouncedScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanOnce()
        }
        pendingScan = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    public func scanOnce() {
        for source in sources {
            scan(source: source)
        }
    }

    /// Requests a one-off scan on the watcher's serial queue so it never races
    /// the timer or FSEvents-driven scans. Safe to call from the main thread.
    public func requestScan() {
        queue.async { [weak self] in
            self?.scanOnce()
        }
    }

    private func scan(source: LogSourceDefinition) {
        guard FileManager.default.fileExists(atPath: source.root.path),
              let enumerator = FileManager.default.enumerator(
                at: source.root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for case let url as URL in enumerator {
            guard shouldRead(url: url, source: source) else {
                continue
            }
            do {
                switch source.readMode {
                case .tailJSONL:
                    try tail(url: url, source: source.source)
                case .wholeFileJSON:
                    try ingestWholeFile(url: url, source: source.source)
                }
            } catch {
                // Log files can rotate or be written concurrently. The next scan gets another chance.
                continue
            }
        }
    }

    private func shouldRead(url: URL, source: LogSourceDefinition) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return source.allowedExtensions.contains(ext)
    }

    private func tail(url: URL, source: UsageSource) throws {
        let path = url.path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        var offset = try database.offset(for: path)

        if fileSize < offset {
            offset = 0
        }
        guard fileSize > offset else {
            return
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        let newOffset = try handle.offset()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            try database.setOffset(newOffset, for: path)
            return
        }

        for line in text.split(whereSeparator: \.isNewline) {
            parse(line: String(line), source: source, path: path)
        }
        try database.setOffset(newOffset, for: path)
    }

    /// Whole-file mode: the offsets table stores the last size we parsed at; any
    /// size change triggers a re-parse. Stable event ids keep this idempotent.
    private func ingestWholeFile(url: URL, source: UsageSource) throws {
        let path = url.path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize != (try database.offset(for: path)) else {
            return
        }

        try database.setOffset(fileSize, for: path)
    }

    private func parse(line: String, source: UsageSource, path: String) {
        switch source {
        case .claudeCode:
            if let event = claudeParser.parseLine(line, filePath: path) {
                onEvent(event)
            }
        case .codexCLI:
            guard let parsed = codexParser.parseSnapshot(line) else {
                return
            }
            let previous = try? database.codexSnapshot(for: path)
            if let event = codexParser.event(
                from: parsed.snapshot,
                previous: previous,
                model: parsed.model,
                timestamp: parsed.timestamp
            ) {
                onEvent(event)
            }
            try? database.setCodexSnapshot(parsed.snapshot, for: path)
        case .geminiCLI:
            if let event = geminiParser.parseLine(line, filePath: path) {
                onEvent(event)
            }
        case .openCode, .chatgptWeb, .claudeWeb, .geminiWeb, .manual:
            // openCode is whole-file mode and never reaches line parsing.
            return
        }
    }
}

