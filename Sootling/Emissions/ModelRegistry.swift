import Foundation

public struct ModelRegistryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: String
    public var aliases: [String]
    public var totalParametersB: Double
    public var activeParametersBMin: Double
    public var activeParametersBMax: Double
    public var pueMin: Double
    public var pueMax: Double
    public var notes: String

    public var activeParametersBMean: Double {
        (activeParametersBMin + activeParametersBMax) / 2
    }

    public var pueMean: Double {
        (pueMin + pueMax) / 2
    }
}

public struct ModelRegistry: Sendable {
    public var entries: [ModelRegistryEntry]
    public var fallback: ModelRegistryEntry

    public init(entries: [ModelRegistryEntry], fallback: ModelRegistryEntry) {
        self.entries = entries
        self.fallback = fallback
    }

    public static func bundled() -> ModelRegistry {
        let bundleName = "Sootling_SootlingCore.bundle"
        let packagedBundles = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName)
        ]

        for bundleURL in packagedBundles {
            guard let bundleURL,
                  let bundle = Bundle(url: bundleURL),
                  let registry = load(from: bundle) else {
                continue
            }
            return registry
        }

        if let registry = load(from: Bundle.module) {
            return registry
        }
        return ModelRegistry(entries: [], fallback: ModelRegistry.defaultFallback)
    }

    private static func load(from bundle: Bundle) -> ModelRegistry? {
        guard let url = bundle.url(forResource: "model-registry", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ModelRegistryFile.self, from: data) else {
            return nil
        }
        return ModelRegistry(entries: decoded.models, fallback: decoded.fallback)
    }

    public func match(modelID: String) -> ModelRegistryEntry {
        let normalized = normalize(modelID)
        for entry in entries {
            let names = ([entry.id] + entry.aliases).map(normalize)
            if names.contains(normalized) {
                return entry
            }
            if names.contains(where: { !$0.isEmpty && normalized.contains($0) }) {
                return entry
            }
        }
        return fallback
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let defaultFallback = ModelRegistryEntry(
        id: "unknown-frontier",
        provider: "unknown",
        aliases: [],
        totalParametersB: 400,
        activeParametersBMin: 70,
        activeParametersBMax: 220,
        pueMin: 1.12,
        pueMax: 1.20,
        notes: "Conservative fallback for unknown hosted frontier models."
    )
}

private struct ModelRegistryFile: Codable {
    var models: [ModelRegistryEntry]
    var fallback: ModelRegistryEntry
}
