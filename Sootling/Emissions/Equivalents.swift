import Foundation

public struct Equivalent: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public enum Equivalents {
    public static func describe(gCO2e grams: Double, gridIntensityGCO2ePerKWh: Double = 480) -> [Equivalent] {
        let phoneCharges = grams / 5.0
        let streamingMinutes = grams / (55.0 / 60.0)
        let carMeters = grams / 0.251
        let ledHours = grams / ((8.0 / 1000.0) * gridIntensityGCO2ePerKWh)

        return [
            Equivalent(id: "phone", label: "Phone charges", value: format(phoneCharges)),
            Equivalent(id: "streaming", label: "Video streaming", value: "\(format(streamingMinutes)) min"),
            Equivalent(id: "car", label: "Car travel", value: "\(format(carMeters)) m"),
            Equivalent(id: "led", label: "LED bulb", value: "\(format(ledHours)) h")
        ]
    }

    private static func format(_ value: Double) -> String {
        if value < 0.1 {
            return "<0.1"
        }
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.0f", value)
    }
}

