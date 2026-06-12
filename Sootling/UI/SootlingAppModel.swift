import AppKit
import Foundation
import SwiftUI

@MainActor
public final class SootlingAppModel: ObservableObject {
    @Published public private(set) var today: DailyImpact = .zero
    @Published public private(set) var weekly: [DayTotal] = []
    @Published public private(set) var analytics: UsageAnalytics = .empty
    @Published public private(set) var recentEvents: [StoredUsageEvent] = []
    @Published public private(set) var lastEvent: UsageEvent?
    @Published public private(set) var lastEstimate: EmissionEstimate?
    @Published public private(set) var lastReaction: PetReaction?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var browserBridgeInfo: BrowserBridgeInfo?
    @Published public var settings: EmissionSettings {
        didSet {
            saveSettings()
            refresh()
        }
    }
    @Published public var petVisible: Bool {
        didSet {
            UserDefaults.standard.set(petVisible, forKey: DefaultsKeys.petVisible)
            guard started else { return }
            petVisible ? showPet() : hidePet()
        }
    }
    @Published public var screenSmokeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(screenSmokeEnabled, forKey: DefaultsKeys.screenSmoke)
            guard started else { return }
            screenSmokeEnabled ? showSmoke() : smokeController?.hide()
        }
    }

    public private(set) var databaseURL: URL?

    private let engine = EmissionEngine()
    private var database: SootlingDatabase?
    private var watcher: LogDirectoryWatcher?
    private var browserBridge: BrowserBridge?
    private var petController: PetPanelController?
    private var smokeController: ScreenSmokeController?
    private var statsWindowController: StatsWindowController?
    private var started = false

    public init() {
        settings = Self.loadSettings()
        if UserDefaults.standard.object(forKey: DefaultsKeys.petVisible) == nil {
            petVisible = true
        } else {
            petVisible = UserDefaults.standard.bool(forKey: DefaultsKeys.petVisible)
        }
        if UserDefaults.standard.object(forKey: DefaultsKeys.screenSmoke) == nil {
            screenSmokeEnabled = true
        } else {
            screenSmokeEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.screenSmoke)
        }
    }

    public static func bootstrap() -> SootlingAppModel {
        SootlingAppModel()
    }

    public var budgetProgress: Double {
        guard settings.dailyBudgetGCO2e > 0 else {
            return 0
        }
        return min(1, today.gCO2e / settings.dailyBudgetGCO2e)
    }

    public var healthState: PetHealthState {
        PetHealthState.fromBudgetProgress(budgetProgress)
    }

    public var menuBarTitle: String {
        if today.gCO2e < 10 {
            return String(format: "%.1fg", today.gCO2e)
        }
        return "\(Int(today.gCO2e.rounded()))g"
    }

    public func start() {
        guard !started else {
            return
        }
        started = true
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            let url = try SootlingDatabase.defaultURL()
            databaseURL = url
            let database = try SootlingDatabase(url: url)
            self.database = database
            refresh()

            let watcher = LogDirectoryWatcher(database: database) { [weak self] event in
                Task { @MainActor in
                    self?.record(event: event)
                }
            }
            self.watcher = watcher
            watcher.start()

            let bridge = BrowserBridge(
                onUsage: { [weak self] event in
                    Task { @MainActor in
                        self?.record(event: event)
                    }
                },
                onReady: { [weak self] info in
                    Task { @MainActor in
                        self?.browserBridgeInfo = info
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.errorMessage = message
                    }
                }
            )
            try bridge.start(configDirectory: url.deletingLastPathComponent())
            browserBridge = bridge

            // Smoke first, then the pet, so Wattson floats above the fog.
            if screenSmokeEnabled {
                showSmoke()
            }
            if petVisible {
                showPet()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func scanNow() {
        // Scan happens on the watcher's queue; new events arrive via the onEvent
        // callback (which refreshes). Refresh now too so totals update even if the
        // scan finds nothing new.
        watcher?.requestScan()
        refresh()
    }

    /// Events older than this are treated as backfill (e.g. the first-launch scan of
    /// historical logs) and counted silently — Wattson only reacts to genuinely live prompts.
    private static let liveReactionWindow: TimeInterval = 45

    public func record(event: UsageEvent) {
        guard let database else {
            return
        }
        let estimate = engine.estimate(event: event, settings: settings)
        do {
            // Whole-file sources re-parse on every change; only a genuinely new row
            // should update state or trigger a reaction.
            guard try database.insert(event: event, estimate: estimate) else {
                return
            }
            lastEvent = event
            lastEstimate = estimate
            scheduleRefresh()
            // Only puff/bounce for fresh prompts so launch backfill doesn't spam reactions.
            if Date().timeIntervalSince(event.timestamp) <= Self.liveReactionWindow {
                lastReaction = PetReaction(
                    grams: estimate.gCO2e.mean,
                    source: event.source,
                    state: healthState,
                    model: event.model,
                    tokensIn: event.tokensIn,
                    tokensOut: event.tokensOut,
                    dailyTotal: today.gCO2e + estimate.gCO2e.mean
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var refreshPending = false

    /// Coalesces bursts of inserts (one prompt appends many lines; first launch ingests
    /// thousands) into at most one refresh per ~150ms so the main thread stays responsive.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            refreshPending = false
            refresh()
        }
    }

    public func refresh() {
        guard let database else {
            return
        }
        do {
            today = try database.dailyImpact(since: Calendar.current.startOfDay(for: Date()))
            weekly = try database.dailyTotals(days: 7)
            analytics = try database.analytics(since: Calendar.current.startOfDay(for: Date()))
            recentEvents = try database.recentEvents(limit: 12)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func showPet() {
        if petController == nil {
            petController = PetPanelController(model: self)
        }
        petController?.show()
    }

    public func hidePet() {
        petController?.hide()
    }

    public func showSmoke() {
        if smokeController == nil {
            smokeController = ScreenSmokeController(model: self)
        }
        smokeController?.show()
        // Both panels share the .floating level; re-front the pet so it stays on top.
        if petVisible {
            petController?.show()
        }
    }

    public func togglePetVisibility() {
        petVisible.toggle()
    }

    public func toggleStatsWindow() {
        if statsWindowController == nil {
            statsWindowController = StatsWindowController(model: self)
        }
        statsWindowController?.toggle()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
        } catch {
            errorMessage = "Launch at login needs a signed app bundle: \(error.localizedDescription)"
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(settings.gridIntensityGCO2ePerKWh, forKey: DefaultsKeys.gridIntensity)
        UserDefaults.standard.set(settings.dailyBudgetGCO2e, forKey: DefaultsKeys.dailyBudget)
    }

    private static func loadSettings() -> EmissionSettings {
        let defaults = UserDefaults.standard
        let grid = defaults.object(forKey: DefaultsKeys.gridIntensity) as? Double ?? 480
        let budget = defaults.object(forKey: DefaultsKeys.dailyBudget) as? Double ?? 2000
        return EmissionSettings(gridIntensityGCO2ePerKWh: grid, dailyBudgetGCO2e: budget)
    }
}

private enum DefaultsKeys {
    static let gridIntensity = "settings.gridIntensityGCO2ePerKWh"
    static let dailyBudget = "settings.dailyBudgetGCO2e"
    static let petVisible = "settings.petVisible"
    static let screenSmoke = "settings.screenSmoke"
}
