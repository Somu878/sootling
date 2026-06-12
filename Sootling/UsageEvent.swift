import Foundation

public enum UsageSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codexCLI
    case geminiCLI
    case openCode
    case chatgptWeb
    case claudeWeb
    case geminiWeb
    case manual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codexCLI: "Codex CLI"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        case .chatgptWeb: "ChatGPT Web"
        case .claudeWeb: "Claude Web"
        case .geminiWeb: "Gemini Web"
        case .manual: "Manual"
        }
    }
}

public struct UsageEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timestamp: Date
    public var source: UsageSource
    public var model: String
    public var tokensIn: Int
    public var tokensOut: Int
    public var cachedInputTokens: Int

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        source: UsageSource,
        model: String,
        tokensIn: Int,
        tokensOut: Int,
        cachedInputTokens: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.model = model
        self.tokensIn = max(0, tokensIn)
        self.tokensOut = max(0, tokensOut)
        self.cachedInputTokens = max(0, cachedInputTokens)
    }
}

public struct StoredUsageEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var source: UsageSource
    public var model: String
    public var tokensIn: Int
    public var tokensOut: Int
    public var cachedInputTokens: Int
    public var energyWh: Double
    public var gCO2e: Double
    public var minGCO2e: Double
    public var maxGCO2e: Double

    public init(
        id: String,
        timestamp: Date,
        source: UsageSource,
        model: String,
        tokensIn: Int,
        tokensOut: Int,
        cachedInputTokens: Int,
        energyWh: Double,
        gCO2e: Double,
        minGCO2e: Double,
        maxGCO2e: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.model = model
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.cachedInputTokens = cachedInputTokens
        self.energyWh = energyWh
        self.gCO2e = gCO2e
        self.minGCO2e = minGCO2e
        self.maxGCO2e = maxGCO2e
    }
}

public struct DailyImpact: Equatable, Sendable {
    public var eventCount: Int
    public var energyWh: Double
    public var gCO2e: Double
    public var minGCO2e: Double
    public var maxGCO2e: Double

    public static let zero = DailyImpact(
        eventCount: 0,
        energyWh: 0,
        gCO2e: 0,
        minGCO2e: 0,
        maxGCO2e: 0
    )
}

public struct AnalyticsRow: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var eventCount: Int
    public var tokensIn: Int
    public var tokensOut: Int
    public var gCO2e: Double

    public init(name: String, eventCount: Int, tokensIn: Int, tokensOut: Int, gCO2e: Double) {
        self.name = name
        self.eventCount = eventCount
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.gCO2e = gCO2e
    }
}

public struct UsageAnalytics: Equatable, Sendable {
    public var providers: [AnalyticsRow]
    public var models: [AnalyticsRow]

    public static let empty = UsageAnalytics(providers: [], models: [])
}
