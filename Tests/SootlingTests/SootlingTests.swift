import Foundation
@testable import SootlingCore
import XCTest

final class SootlingTests: XCTestCase {
    func testClaudeParserReadsUsage() throws {
        let line = try fixtureLines("claude").first!
        let event = ClaudeCodeParser().parseLine(line)

        XCTAssertEqual(event?.source, .claudeCode)
        XCTAssertEqual(event?.model, "claude-fable-5")
        XCTAssertEqual(event?.tokensIn, 150)
        XCTAssertEqual(event?.cachedInputTokens, 30)
        XCTAssertEqual(event?.tokensOut, 50)
    }

    func testClaudeParserReadsNestedMessageUsage() throws {
        // Mirrors the real Claude Code log shape: usage and model live under `message`.
        let line = """
        {"type":"assistant","timestamp":"2026-06-12T01:00:00Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":3009,"cache_creation_input_tokens":10437,"cache_read_input_tokens":58167,"output_tokens":171}}}
        """
        let event = try XCTUnwrap(ClaudeCodeParser().parseLine(line))

        XCTAssertEqual(event.source, .claudeCode)
        XCTAssertEqual(event.model, "claude-opus-4-8")
        XCTAssertEqual(event.tokensIn, 3009 + 10437 + 58167)
        XCTAssertEqual(event.cachedInputTokens, 58167)
        XCTAssertEqual(event.tokensOut, 171)
    }

    func testCodexParserComputesCumulativeDeltas() throws {
        let lines = try fixtureLines("codex")
        let parser = CodexCLIParser()

        let first = try XCTUnwrap(parser.parseSnapshot(lines[0]))
        let firstEvent = parser.event(
            from: first.snapshot,
            previous: nil,
            model: first.model,
            timestamp: first.timestamp
        )

        let second = try XCTUnwrap(parser.parseSnapshot(lines[1]))
        let secondEvent = parser.event(
            from: second.snapshot,
            previous: first.snapshot,
            model: second.model,
            timestamp: second.timestamp
        )

        XCTAssertEqual(firstEvent?.tokensIn, 100)
        XCTAssertEqual(firstEvent?.cachedInputTokens, 20)
        XCTAssertEqual(firstEvent?.tokensOut, 30)
        XCTAssertEqual(secondEvent?.tokensIn, 80)
        XCTAssertEqual(secondEvent?.cachedInputTokens, 10)
        XCTAssertEqual(secondEvent?.tokensOut, 40)
    }

    func testGeminiParserReadsUsageMetadata() throws {
        let line = try fixtureLines("gemini").first!
        let event = GeminiCLIParser().parseLine(line)

        XCTAssertEqual(event?.source, .geminiCLI)
        XCTAssertEqual(event?.model, "gemini-2.5-pro")
        XCTAssertEqual(event?.tokensIn, 52)
        XCTAssertEqual(event?.cachedInputTokens, 8)
        XCTAssertEqual(event?.tokensOut, 12)
    }

    func testOpenCodeParserReadsCompletedAssistantMessage() throws {
        // Mirrors a real ~/.local/share/opencode/storage/message/<ses>/<msg>.json file.
        let content = """
        {"id":"msg_b7a179620001cr4aTweYj7F9vp","role":"assistant","sessionID":"ses_x",
         "time":{"created":1767279924768,"completed":1767279932293},
         "modelID":"glm-4.7-free","providerID":"opencode","cost":0,
         "tokens":{"input":1041,"output":327,"reasoning":0,"cache":{"read":57213,"write":0}}}
        """
        let event = try XCTUnwrap(OpenCodeParser().parseFile(content))

        XCTAssertEqual(event.id, "opencode-msg_b7a179620001cr4aTweYj7F9vp")
        XCTAssertEqual(event.source, .openCode)
        XCTAssertEqual(event.model, "glm-4.7-free")
        XCTAssertEqual(event.tokensIn, 1041 + 57213)
        XCTAssertEqual(event.cachedInputTokens, 57213)
        XCTAssertEqual(event.tokensOut, 327)

        // Still-streaming messages (no time.completed) must be skipped.
        let streaming = """
        {"id":"msg_x","role":"assistant","time":{"created":1767279924768},
         "modelID":"glm-4.7-free","tokens":{"input":10,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}
        """
        XCTAssertNil(OpenCodeParser().parseFile(streaming))
    }

    func testInsertReportsDuplicates() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SootlingDupes-\(UUID().uuidString)", isDirectory: true)
        let database = try SootlingDatabase(url: temp.appendingPathComponent("db.sqlite"))
        let event = UsageEvent(
            id: "stable-id",
            timestamp: Date(),
            source: .openCode,
            model: "glm-4.7-free",
            tokensIn: 10,
            tokensOut: 5,
            cachedInputTokens: 0
        )
        let estimate = EmissionEngine().estimate(event: event)

        XCTAssertTrue(try database.insert(event: event, estimate: estimate))
        XCTAssertFalse(try database.insert(event: event, estimate: estimate))
        XCTAssertEqual(try database.recentEvents(limit: 10).count, 1)
    }

    func testEmissionEngineProducesHonestRange() throws {
        let event = UsageEvent(
            timestamp: Date(),
            source: .claudeCode,
            model: "claude-fable-5",
            tokensIn: 1_000,
            tokensOut: 200,
            cachedInputTokens: 300
        )

        let estimate = EmissionEngine().estimate(event: event)

        XCTAssertEqual(estimate.modelMatched, "claude-sonnet")
        XCTAssertGreaterThan(estimate.energyWh.mean, 0)
        XCTAssertGreaterThan(estimate.gCO2e.mean, 0)
        XCTAssertLessThanOrEqual(estimate.gCO2e.min, estimate.gCO2e.mean)
        XCTAssertLessThanOrEqual(estimate.gCO2e.mean, estimate.gCO2e.max)
    }

    func testDatabasePersistsEventsOffsetsAndSnapshots() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SootlingTests-\(UUID().uuidString)", isDirectory: true)
        let dbURL = temp.appendingPathComponent("test.sqlite")
        let database = try SootlingDatabase(url: dbURL)
        let event = UsageEvent(
            timestamp: Date(),
            source: .codexCLI,
            model: "gpt-5-codex",
            tokensIn: 10,
            tokensOut: 5,
            cachedInputTokens: 2
        )
        let estimate = EmissionEngine().estimate(event: event)

        try database.insert(event: event, estimate: estimate)
        try database.setOffset(42, for: "/tmp/session.jsonl")
        try database.setCodexSnapshot(
            CodexTokenSnapshot(inputTokens: 10, cachedInputTokens: 2, outputTokens: 5, totalTokens: 15),
            for: "/tmp/session.jsonl"
        )

        let today = try database.dailyImpact(since: Calendar.current.startOfDay(for: Date()))
        let recent = try database.recentEvents(limit: 5)
        let snapshot = try database.codexSnapshot(for: "/tmp/session.jsonl")
        let weekly = try database.dailyTotals(days: 7)

        XCTAssertEqual(today.eventCount, 1)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(try database.offset(for: "/tmp/session.jsonl"), 42)
        XCTAssertEqual(snapshot?.totalTokens, 15)
        XCTAssertEqual(weekly.count, 7)
        XCTAssertEqual(weekly.last?.day, Calendar.current.startOfDay(for: Date()))
        XCTAssertGreaterThan(weekly.last?.gCO2e ?? 0, 0)
        XCTAssertEqual(weekly.dropLast().map(\.gCO2e), [0, 0, 0, 0, 0, 0])
    }

    func testWatcherDeliversNewLinesInRealtime() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SootlingWatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let database = try SootlingDatabase(url: temp.appendingPathComponent("db.sqlite"))
        let source = LogSourceDefinition(root: temp, source: .claudeCode, allowedExtensions: ["jsonl"])

        let received = expectation(description: "event delivered for appended line")
        let watcher = LogDirectoryWatcher(sources: [source], database: database) { event in
            if event.source == .claudeCode {
                received.fulfill()
            }
        }
        // Short poll interval keeps the safety net snappy if FSEvents is slow under CI.
        watcher.start(interval: 1)
        defer { watcher.stop() }

        // Give the stream a beat to arm, then append a real Claude-format line.
        let line = try fixtureLines("claude").first!
        let logURL = temp.appendingPathComponent("session.jsonl")
        Thread.sleep(forTimeInterval: 0.3)
        try (line + "\n").data(using: .utf8)!.write(to: logURL)

        wait(for: [received], timeout: 6)
    }

    private func fixtureLines(_ name: String) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name,
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        ))
        return try String(contentsOf: url)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}

