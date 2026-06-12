import SwiftUI
import Foundation

public struct StatsPopoverView: View {
    @ObservedObject private var model: SootlingAppModel
    @State private var selectedDate: Date
    private let compact: Bool

    public init(model: SootlingAppModel, compact: Bool = false) {
        self.model = model
        self.compact = compact
        _selectedDate = State(initialValue: Date())
    }

    private func stepDate(by days: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let clamped = min(newDate, today)
        selectedDate = clamped
        model.selectedDate = clamped
    }

    public var body: some View {
        if compact {
            compactBody
        } else {
            expandedBody
        }
    }

    // The menu-bar popover: a single narrow column, hero only.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroCard
            errorBanner
            footerControls
        }
        .padding(14)
        .frame(width: 380)
    }

    // The click-to-open window: a wide, rectangular dashboard that reflows from a
    // two-column grid to a single column as the window is resized narrower.
    private var expandedBody: some View {
        GeometryReader { proxy in
            let twoColumn = proxy.size.width >= 700
            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    if twoColumn {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 14) {
                                weeklyCard
                                equivalentsCard
                                calculationCard
                            }
                            VStack(spacing: 14) {
                                analyticsCard
                                recentCard
                            }
                        }
                    } else {
                        weeklyCard
                        equivalentsCard
                        analyticsCard
                        calculationCard
                        recentCard
                    }
                    errorBanner
                    footerControls
                }
                .padding(18)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerControls: some View {
        HStack {
            Button("Scan now") {
                model.scanNow()
            }
            Spacer()
            Button(model.petVisible ? "Hide Wattson" : "Show Wattson") {
                model.togglePetVisibility()
            }
        }
        .controlSize(.small)
    }

    // MARK: Hero

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(heroGradient)

            VStack(spacing: 12) {
                HStack {
                    Text("Stats for \(formatDate(selectedDate))")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .kerning(1.1)
                    Spacer()
                    dateStepper
                }
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Calendar.current.isDateInToday(selectedDate) ? "TODAY'S FOOTPRINT" : "FOOTPRINT")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .kerning(1.1)
                        Text(formatWeight(dayImpactGCO2e))
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(formatImpactRange())
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("\(dayImpactEventCount) prompts · \(dayImpactMood)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.top, 2)
                    }
                    Spacer()
                    budgetRing
                }
            }
            .padding(16)
        }
    }

    private var dateStepper: some View {
        HStack(spacing: 8) {
            Button(action: { stepDate(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Previous day")
            Button(action: { stepDate(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Next day")
        }
    }

    private var dayImpactGCO2e: Double {
        model.dayImpact?.gCO2e ?? 0
    }

    private var dayImpactEventCount: Int {
        model.dayImpact?.eventCount ?? 0
    }

    private var dayImpactMood: String {
        model.dayImpactHealthState.mood
    }

    private func formatImpactRange() -> String {
        let min = model.dayImpact?.minGCO2e ?? 0
        let max = model.dayImpact?.maxGCO2e ?? 0
        let wh = model.dayImpact?.energyWh ?? 0
        return "\(formatWeight(min))–\(formatWeight(max)) range · \(format(wh)) Wh"
    }

    private var budgetRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 7)
            Circle()
                .trim(from: 0, to: dayBudgetProgress)
                .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((dayBudgetProgress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("budget")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 62, height: 62)
    }

    private var dayBudgetProgress: Double {
        guard model.settings.dailyBudgetGCO2e > 0 else { return 0 }
        return min(1, dayImpactGCO2e / model.settings.dailyBudgetGCO2e)
    }

    private var heroGradient: LinearGradient {
        let state = Calendar.current.isDateInToday(selectedDate) ? model.healthState : model.dayImpactHealthState
        let colors: [Color]
        switch state {
        case .thriving:
            colors = [Color(red: 0.20, green: 0.65, blue: 0.36), Color(red: 0.08, green: 0.42, blue: 0.28)]
        case .content:
            colors = [Color(red: 0.16, green: 0.55, blue: 0.50), Color(red: 0.08, green: 0.36, blue: 0.36)]
        case .sluggish:
            colors = [Color(red: 0.66, green: 0.48, blue: 0.15), Color(red: 0.45, green: 0.28, blue: 0.08)]
        case .sooty:
            colors = [Color(red: 0.28, green: 0.28, blue: 0.32), Color(red: 0.10, green: 0.10, blue: 0.13)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Weekly chart

    private var weeklyCard: some View {
        card("Last 7 days") {
            let peak = max(model.weekly.map(\.gCO2e).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(model.weekly) { day in
                    let isSelected = Calendar.current.isDate(day.day, equalTo: selectedDate, toGranularity: .day)
                    VStack(spacing: 4) {
                        Text(day.gCO2e > 0 ? formatWeightShort(day.gCO2e) : " ")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Capsule()
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [.teal, .green],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    : AnyShapeStyle(Color.secondary.opacity(0.35))
                            )
                            .frame(height: 8 + 50 * (day.gCO2e / peak))
                        Text(weekdayLetter(day.day))
                            .font(.system(size: 9, weight: isSelected ? .bold : .regular, design: .rounded))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
        }
    }

    // MARK: Equivalents

    private var equivalentsCard: some View {
        card(Calendar.current.isDateInToday(selectedDate) ? "Today feels like" : "\(formatDate(selectedDate)) feels like") {
            let items = Equivalents.describe(
                gCO2e: dayImpactGCO2e,
                gridIntensityGCO2ePerKWh: model.settings.gridIntensityGCO2ePerKWh
            )
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 9) {
                        Image(systemName: equivalentIcon(item.id))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(equivalentTint(item.id)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.value)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(item.label)
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func equivalentIcon(_ id: String) -> String {
        switch id {
        case "phone": "iphone.gen3"
        case "streaming": "play.rectangle.fill"
        case "car": "car.fill"
        case "led": "lightbulb.fill"
        default: "leaf.fill"
        }
    }

    private func equivalentTint(_ id: String) -> Color {
        switch id {
        case "phone": .blue
        case "streaming": .purple
        case "car": .orange
        case "led": .yellow.opacity(0.85)
        default: .green
        }
    }

    // MARK: Calculation

    private var calculationCard: some View {
        card("How Wattson estimates it") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Words are estimated as tokens, then tokens are mapped to model energy and your grid intensity. Sootling stores counts, not prompt text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let example = exampleEmission
                HStack(spacing: 8) {
                    calculationPill(title: "Example", value: "\(example.words) words")
                    calculationPill(title: "Tokens", value: "~\(example.tokens)")
                    calculationPill(title: "Footprint", value: formatWeightShort(example.grams))
                }

                Text("Example assumes \(example.words) typed words and a \(example.outputTokens)-token answer on a frontier model. Real results vary by model, cache hits, output length, and grid setting.")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func calculationPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var exampleEmission: (words: Int, tokens: Int, outputTokens: Int, grams: Double) {
        let words = 100
        let tokens = 130
        let outputTokens = 220
        let event = UsageEvent(
            timestamp: Date(),
            source: .manual,
            model: "gpt-5-codex",
            tokensIn: tokens,
            tokensOut: outputTokens,
            cachedInputTokens: 0
        )
        let estimate = EmissionEngine().estimate(event: event, settings: model.settings)
        return (words, tokens, outputTokens, estimate.gCO2e.mean)
    }

    // MARK: Analytics

    private var analyticsCard: some View {
        let analytics = Calendar.current.isDateInToday(selectedDate) ? model.analytics : model.dayAnalytics
        return card("Provider & model analytics") {
            VStack(alignment: .leading, spacing: 10) {
                analyticsSection(title: "Providers", rows: analytics.providers)
                Divider()
                analyticsSection(title: "Models", rows: analytics.models)
            }
        }
    }

    private func analyticsSection(title: String, rows: [AnalyticsRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(Calendar.current.isDateInToday(selectedDate) ? "No usage yet today." : "No usage on \(formatDate(selectedDate)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let total = max(rows.map(\.gCO2e).reduce(0, +), 0.001)
                ForEach(rows.prefix(5)) { row in
                    analyticsRow(row, total: total)
                }
            }
        }
    }

    private func analyticsRow(_ row: AnalyticsRow, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text(formatWeightShort(row.gCO2e))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
            }
            HStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.18))
                        Capsule()
                            .fill(gramTint(row.gCO2e))
                            .frame(width: proxy.size.width * min(1, row.gCO2e / total))
                    }
                }
                .frame(height: 5)
                Text("\(row.eventCount)x · \(formatTokenCount(row.tokensIn + row.tokensOut)) tok")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 82, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Recent prompts

    private var recentCard: some View {
        let events = Calendar.current.isDateInToday(selectedDate) ? model.recentEvents : model.dayEvents
        return card("Recent prompts") {
            if events.isEmpty {
                Text("No AI usage seen yet — Wattson is watching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(8).enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Divider()
                        }
                        HStack(spacing: 9) {
                            Image(systemName: sourceIcon(event.source))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.source.displayName)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                Text(event.model)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: Date()))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.tertiary)
                            Text(formatWeightShort(event.gCO2e))
                                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(gramTint(event.gCO2e)))
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func sourceIcon(_ source: UsageSource) -> String {
        switch source {
        case .claudeCode, .codexCLI, .geminiCLI, .openCode: "terminal.fill"
        case .chatgptWeb, .claudeWeb, .geminiWeb: "globe"
        case .manual: "hand.tap.fill"
        }
    }

    /// Matches Wattson's reaction tiers: green breeze, amber puff, red choke.
    private func gramTint(_ grams: Double) -> Color {
        if grams < 2.5 { return Color(red: 0.16, green: 0.55, blue: 0.32) }
        if grams < 18 { return Color(red: 0.72, green: 0.48, blue: 0.10) }
        return Color(red: 0.68, green: 0.20, blue: 0.16)
    }

    // MARK: Building blocks

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatWeight(_ grams: Double) -> String {
        if grams >= 1000 {
            return String(format: "%.2f kg", grams / 1000)
        }
        if grams < 10 {
            return String(format: "%.2f g", grams)
        }
        return String(format: "%.0f g", grams)
    }

    private func formatWeightShort(_ grams: Double) -> String {
        if grams >= 1000 {
            return String(format: "%.1fkg", grams / 1000)
        }
        if grams < 10 {
            return String(format: "%.1fg", grams)
        }
        return String(format: "%.0fg", grams)
    }

    private func format(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.0f", value)
    }

    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
