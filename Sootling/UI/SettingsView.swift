import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var model: SootlingAppModel

    public init(model: SootlingAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Carbon estimates") {
                Picker("Grid preset", selection: gridPresetBinding) {
                    ForEach(GridIntensityPreset.presets) { preset in
                        Text("\(preset.name) (\(Int(preset.gCO2ePerKWh)) g/kWh)")
                            .tag(preset.id)
                    }
                    Text("Custom")
                        .tag("custom")
                }

                TextField(
                    "Grid intensity",
                    value: $model.settings.gridIntensityGCO2ePerKWh,
                    format: .number.precision(.fractionLength(0))
                )
                TextField(
                    "Daily budget",
                    value: $model.settings.dailyBudgetGCO2e,
                    format: .number.precision(.fractionLength(0))
                )
            }

            Section("Pet") {
                Toggle("Show floating pet", isOn: $model.petVisible)
                Toggle("Fill screen with smoke on emissions", isOn: $model.screenSmokeEnabled)
                Text("Each prompt briefly fogs the screen in proportion to its CO₂e, then fades. The smoke is click-through and never blocks your work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLoginController.isEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Browser bridge") {
                if let bridge = model.browserBridgeInfo {
                    LabeledContent("Usage URL", value: bridge.usageURL)
                        .textSelection(.enabled)
                    LabeledContent("Secret", value: bridge.secret)
                        .textSelection(.enabled)
                    Text("Browser text stays in the extension. Sootling receives token counts, model/source metadata, and timestamps only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Starting local bridge...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                if let url = model.databaseURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Database not opened yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 360)
    }

    private var gridPresetBinding: Binding<String> {
        Binding(
            get: {
                GridIntensityPreset.presets.first {
                    abs($0.gCO2ePerKWh - model.settings.gridIntensityGCO2ePerKWh) < 0.1
                }?.id ?? "custom"
            },
            set: { id in
                guard let preset = GridIntensityPreset.presets.first(where: { $0.id == id }) else {
                    return
                }
                model.settings.gridIntensityGCO2ePerKWh = preset.gCO2ePerKWh
            }
        )
    }
}
