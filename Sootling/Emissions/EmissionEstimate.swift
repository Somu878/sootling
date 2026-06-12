import Foundation

public struct RangeValue: Codable, Equatable, Sendable {
    public var min: Double
    public var mean: Double
    public var max: Double

    public init(min: Double, mean: Double, max: Double) {
        self.min = min
        self.mean = mean
        self.max = max
    }
}

public struct EmissionEstimate: Codable, Equatable, Sendable {
    public var energyWh: RangeValue
    public var gCO2e: RangeValue
    public var embodiedGCO2e: RangeValue
    public var modelMatched: String
    public var assumptions: [String]

    public init(
        energyWh: RangeValue,
        gCO2e: RangeValue,
        embodiedGCO2e: RangeValue,
        modelMatched: String,
        assumptions: [String]
    ) {
        self.energyWh = energyWh
        self.gCO2e = gCO2e
        self.embodiedGCO2e = embodiedGCO2e
        self.modelMatched = modelMatched
        self.assumptions = assumptions
    }
}

public struct EmissionSettings: Codable, Equatable, Sendable {
    public var gridIntensityGCO2ePerKWh: Double
    public var dailyBudgetGCO2e: Double

    public init(
        gridIntensityGCO2ePerKWh: Double = 480,
        // A real day of agentic CLI usage lands in the hundreds-to-thousands of grams;
        // a 50g budget pinned the pet permanently to "sooty" with zero visual range.
        dailyBudgetGCO2e: Double = 2000
    ) {
        self.gridIntensityGCO2ePerKWh = gridIntensityGCO2ePerKWh
        self.dailyBudgetGCO2e = dailyBudgetGCO2e
    }
}

public struct GridIntensityPreset: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var gCO2ePerKWh: Double

    public static let presets: [GridIntensityPreset] = [
        GridIntensityPreset(id: "world", name: "World average", gCO2ePerKWh: 480),
        GridIntensityPreset(id: "us", name: "United States", gCO2ePerKWh: 370),
        GridIntensityPreset(id: "india", name: "India", gCO2ePerKWh: 710),
        GridIntensityPreset(id: "eu", name: "European Union", gCO2ePerKWh: 250),
        GridIntensityPreset(id: "france", name: "France", gCO2ePerKWh: 55)
    ]
}

