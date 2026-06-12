import Foundation

public struct EmissionEngine: Sendable {
    private let registry: ModelRegistry

    public init(registry: ModelRegistry = .bundled()) {
        self.registry = registry
    }

    public func estimate(event: UsageEvent, settings: EmissionSettings = EmissionSettings()) -> EmissionEstimate {
        let model = registry.match(modelID: event.model)
        let minEstimate = pointEstimate(
            event: event,
            model: model,
            activeParametersB: model.activeParametersBMin,
            pue: model.pueMin,
            gridIntensity: settings.gridIntensityGCO2ePerKWh
        )
        let meanEstimate = pointEstimate(
            event: event,
            model: model,
            activeParametersB: model.activeParametersBMean,
            pue: model.pueMean,
            gridIntensity: settings.gridIntensityGCO2ePerKWh
        )
        let maxEstimate = pointEstimate(
            event: event,
            model: model,
            activeParametersB: model.activeParametersBMax,
            pue: model.pueMax,
            gridIntensity: settings.gridIntensityGCO2ePerKWh
        )

        var assumptions = [
            "EcoLogits-inspired LLM inference model",
            "H100 80GB GPUs, 16-bit weights, batch size 64",
            "Grid intensity \(Int(settings.gridIntensityGCO2ePerKWh)) gCO2e/kWh"
        ]
        if model.id == registry.fallback.id {
            assumptions.append("Unknown model mapped to conservative fallback")
        }
        if event.cachedInputTokens > 0 {
            assumptions.append("Cached input tokens use reduced prefill factor")
        }

        return EmissionEstimate(
            energyWh: RangeValue(
                min: minEstimate.energyWh,
                mean: meanEstimate.energyWh,
                max: maxEstimate.energyWh
            ),
            gCO2e: RangeValue(
                min: minEstimate.gCO2e,
                mean: meanEstimate.gCO2e,
                max: maxEstimate.gCO2e
            ),
            embodiedGCO2e: RangeValue(
                min: minEstimate.embodiedGCO2e,
                mean: meanEstimate.embodiedGCO2e,
                max: maxEstimate.embodiedGCO2e
            ),
            modelMatched: model.id,
            assumptions: assumptions
        )
    }

    private func pointEstimate(
        event: UsageEvent,
        model: ModelRegistryEntry,
        activeParametersB: Double,
        pue: Double,
        gridIntensity: Double
    ) -> (energyWh: Double, gCO2e: Double, embodiedGCO2e: Double) {
        let batchSize = 64.0
        let gpuCount = requiredGPUCount(totalParametersB: model.totalParametersB)
        let outputTokens = Double(max(0, event.tokensOut))
        let inputTokens = Double(max(0, event.tokensIn - event.cachedInputTokens))
        let cachedTokens = Double(max(0, event.cachedInputTokens))

        let energyPerOutputTokenWh = gpuEnergyPerOutputTokenWh(activeParametersB: activeParametersB, batchSize: batchSize)
        let uncachedPrefillWh = inputTokens * energyPerOutputTokenWh * 0.08
        let cachedPrefillWh = cachedTokens * energyPerOutputTokenWh * 0.01
        let gpuEnergyWh = gpuCount * ((outputTokens * energyPerOutputTokenWh) + uncachedPrefillWh + cachedPrefillWh)

        let latencySeconds = max(0.05, outputTokens * latencyPerOutputTokenSeconds(activeParametersB: activeParametersB, batchSize: batchSize))
        let serverWithoutGPUWh = (latencySeconds / 3600.0) * 1200.0 * (gpuCount / 8.0) * (1.0 / batchSize)
        let requestEnergyWh = pue * (serverWithoutGPUWh + gpuEnergyWh)

        let usageGCO2e = (requestEnergyWh / 1000.0) * gridIntensity
        let embodiedGCO2e = embodiedImpactGCO2e(gpuCount: gpuCount, latencySeconds: latencySeconds, batchSize: batchSize)

        return (
            energyWh: requestEnergyWh,
            gCO2e: usageGCO2e + embodiedGCO2e,
            embodiedGCO2e: embodiedGCO2e
        )
    }

    private func gpuEnergyPerOutputTokenWh(activeParametersB: Double, batchSize: Double) -> Double {
        let alpha = 1.17e-6
        let beta = -1.12e-2
        let gamma = 4.05e-5
        return alpha * exp(beta * batchSize) * activeParametersB + gamma
    }

    private func latencyPerOutputTokenSeconds(activeParametersB: Double, batchSize: Double) -> Double {
        let alpha = 6.78e-4
        let beta = 3.12e-4
        let gamma = 1.94e-2
        return alpha * activeParametersB + beta * batchSize + gamma
    }

    private func requiredGPUCount(totalParametersB: Double) -> Double {
        let quantizationBits = 16.0
        let gpuMemoryGB = 80.0
        let modelMemoryGB = 1.2 * totalParametersB * quantizationBits / 8.0
        let rawCount = max(1.0, ceil(modelMemoryGB / gpuMemoryGB))

        var powerOfTwo = 1.0
        while powerOfTwo < rawCount {
            powerOfTwo *= 2.0
        }
        return powerOfTwo
    }

    private func embodiedImpactGCO2e(gpuCount: Double, latencySeconds: Double, batchSize: Double) -> Double {
        let serverWithoutGPUKgCO2e = 5700.0
        let h100GPUKgCO2e = 273.0
        let lifetimeSeconds = 3.0 * 365.0 * 24.0 * 3600.0
        let serverKgCO2e = (gpuCount / 8.0) * serverWithoutGPUKgCO2e + gpuCount * h100GPUKgCO2e
        return (latencySeconds / (batchSize * lifetimeSeconds)) * serverKgCO2e * 1000.0
    }
}

