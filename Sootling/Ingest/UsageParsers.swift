import Foundation

public protocol UsageLineParser {
    func parseLine(_ line: String, filePath: String) -> UsageEvent?
}

public struct ClaudeCodeParser: UsageLineParser {
    public init() {}

    public func parseLine(_ line: String, filePath: String = "") -> UsageEvent? {
        // Real Claude Code logs nest usage/model under `message`; older/synthetic
        // lines put them at the top level. Accept both.
        guard let object = JSONLine.object(from: line),
              let usage = JSONLine.dictionary(object, at: ["message", "usage"])
                ?? JSONLine.dictionary(object, at: ["usage"]) else {
            return nil
        }

        let baseInput = JSONLine.int(usage, at: ["input_tokens"]) ?? 0
        let cacheCreation = JSONLine.int(usage, at: ["cache_creation_input_tokens"]) ?? 0
        let cacheRead = JSONLine.int(usage, at: ["cache_read_input_tokens"]) ?? 0
        let output = JSONLine.int(usage, at: ["output_tokens"]) ?? 0

        guard baseInput + cacheCreation + cacheRead + output > 0 else {
            return nil
        }

        let model = JSONLine.string(object, at: ["model"])
            ?? JSONLine.string(object, at: ["message", "model"])
            ?? "claude-unknown"
        let timestamp = JSONLine.date(object, at: ["timestamp"])
            ?? JSONLine.date(object, at: ["created_at"])
            ?? Date()

        return UsageEvent(
            timestamp: timestamp,
            source: .claudeCode,
            model: model,
            tokensIn: baseInput + cacheCreation + cacheRead,
            tokensOut: output,
            cachedInputTokens: cacheRead
        )
    }
}

public struct CodexTokenSnapshot: Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public static let zero = CodexTokenSnapshot(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        totalTokens: 0
    )
}

public struct CodexCLIParser {
    public init() {}

    public func parseSnapshot(_ line: String) -> (snapshot: CodexTokenSnapshot, model: String?, timestamp: Date)? {
        guard let object = JSONLine.object(from: line) else {
            return nil
        }

        let eventType = JSONLine.string(object, at: ["type"])
            ?? JSONLine.string(object, at: ["event"])
            ?? JSONLine.string(object, at: ["name"])
        let payloadType = JSONLine.string(object, at: ["payload", "type"])
        guard eventType == nil || eventType == "token_count" || payloadType == "token_count" else {
            return nil
        }

        guard let usage = JSONLine.dictionary(object, at: ["info", "total_token_usage"])
            ?? JSONLine.dictionary(object, at: ["payload", "info", "total_token_usage"])
            ?? JSONLine.dictionary(object, at: ["total_token_usage"])
            ?? JSONLine.dictionary(object, at: ["usage"]) else {
            return nil
        }

        let input = JSONLine.int(usage, at: ["input_tokens"])
            ?? JSONLine.int(usage, at: ["prompt_tokens"])
            ?? 0
        let cached = JSONLine.int(usage, at: ["cached_input_tokens"])
            ?? JSONLine.int(usage, at: ["cache_read_input_tokens"])
            ?? 0
        let output = JSONLine.int(usage, at: ["output_tokens"])
            ?? JSONLine.int(usage, at: ["completion_tokens"])
            ?? 0
        let total = JSONLine.int(usage, at: ["total_tokens"]) ?? input + output

        guard total > 0 || input + cached + output > 0 else {
            return nil
        }

        let model = JSONLine.string(object, at: ["info", "model"])
            ?? JSONLine.string(object, at: ["payload", "info", "model"])
            ?? JSONLine.string(object, at: ["model"])
            ?? JSONLine.string(object, at: ["info", "model_slug"])
            ?? JSONLine.string(object, at: ["payload", "info", "model_slug"])
        let timestamp = JSONLine.date(object, at: ["timestamp"])
            ?? JSONLine.date(object, at: ["created_at"])
            ?? Date()

        return (
            CodexTokenSnapshot(
                inputTokens: input,
                cachedInputTokens: cached,
                outputTokens: output,
                totalTokens: total
            ),
            model,
            timestamp
        )
    }

    public func event(
        from current: CodexTokenSnapshot,
        previous: CodexTokenSnapshot?,
        model: String?,
        timestamp: Date
    ) -> UsageEvent? {
        let baseline = previous ?? .zero
        let inputDelta = max(0, current.inputTokens - baseline.inputTokens)
        let cachedDelta = max(0, current.cachedInputTokens - baseline.cachedInputTokens)
        let outputDelta = max(0, current.outputTokens - baseline.outputTokens)

        guard inputDelta + cachedDelta + outputDelta > 0 else {
            return nil
        }

        return UsageEvent(
            timestamp: timestamp,
            source: .codexCLI,
            model: model ?? "gpt-5-codex",
            tokensIn: inputDelta,
            tokensOut: outputDelta,
            cachedInputTokens: cachedDelta
        )
    }
}

/// OpenCode writes one JSON document per message at
/// `~/.local/share/opencode/storage/message/<session>/<msg>.json` and rewrites it
/// in place while the reply streams. So this parses whole files (not tailed lines)
/// and only accepts completed assistant messages; the stable message id makes
/// re-parses idempotent via INSERT OR IGNORE.
public struct OpenCodeParser {
    public init() {}

    public func parseFile(_ content: String) -> UsageEvent? {
        guard let object = JSONLine.object(from: content),
              JSONLine.string(object, at: ["role"]) == "assistant",
              let id = JSONLine.string(object, at: ["id"]),
              let completedMs = JSONLine.int(object, at: ["time", "completed"]),
              let tokens = JSONLine.dictionary(object, at: ["tokens"]) else {
            return nil
        }

        let input = JSONLine.int(tokens, at: ["input"]) ?? 0
        let output = JSONLine.int(tokens, at: ["output"]) ?? 0
        let reasoning = JSONLine.int(tokens, at: ["reasoning"]) ?? 0
        let cacheRead = JSONLine.int(tokens, at: ["cache", "read"]) ?? 0
        let cacheWrite = JSONLine.int(tokens, at: ["cache", "write"]) ?? 0

        guard input + output + reasoning + cacheRead + cacheWrite > 0 else {
            return nil
        }

        let model = JSONLine.string(object, at: ["modelID"]) ?? "opencode-unknown"

        return UsageEvent(
            id: "opencode-\(id)",
            timestamp: Date(timeIntervalSince1970: Double(completedMs) / 1000),
            source: .openCode,
            model: model,
            tokensIn: input + cacheRead + cacheWrite,
            tokensOut: output + reasoning,
            cachedInputTokens: cacheRead
        )
    }
}

public struct GeminiCLIParser: UsageLineParser {
    public init() {}

    public func parseLine(_ line: String, filePath: String = "") -> UsageEvent? {
        guard let object = JSONLine.object(from: line) else {
            return nil
        }

        let usage = JSONLine.dictionary(object, at: ["usageMetadata"])
            ?? JSONLine.dictionary(object, at: ["usage_metadata"])
            ?? JSONLine.dictionary(object, at: ["usage"])
            ?? JSONLine.dictionary(object, at: ["response", "usageMetadata"])

        guard let usage else {
            return nil
        }

        let input = JSONLine.int(usage, at: ["promptTokenCount"])
            ?? JSONLine.int(usage, at: ["prompt_token_count"])
            ?? JSONLine.int(usage, at: ["input_tokens"])
            ?? JSONLine.int(usage, at: ["prompt_tokens"])
            ?? 0
        let output = JSONLine.int(usage, at: ["candidatesTokenCount"])
            ?? JSONLine.int(usage, at: ["candidates_token_count"])
            ?? JSONLine.int(usage, at: ["output_tokens"])
            ?? JSONLine.int(usage, at: ["completion_tokens"])
            ?? 0
        let cached = JSONLine.int(usage, at: ["cachedContentTokenCount"])
            ?? JSONLine.int(usage, at: ["cached_content_token_count"])
            ?? JSONLine.int(usage, at: ["cached_input_tokens"])
            ?? 0

        guard input + output + cached > 0 else {
            return nil
        }

        let model = JSONLine.string(object, at: ["model"])
            ?? JSONLine.string(object, at: ["request", "model"])
            ?? JSONLine.string(object, at: ["response", "modelVersion"])
            ?? "gemini-unknown"
        let timestamp = JSONLine.date(object, at: ["timestamp"])
            ?? JSONLine.date(object, at: ["created_at"])
            ?? Date()

        return UsageEvent(
            timestamp: timestamp,
            source: .geminiCLI,
            model: model,
            tokensIn: input + cached,
            tokensOut: output,
            cachedInputTokens: cached
        )
    }
}
