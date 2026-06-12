import AppKit
import SwiftUI

@MainActor
public final class PetPanelController {
    private let panel: NSPanel

    // The panel is taller than Wattson so puffs and bubbles have headroom.
    static let panelSize = CGSize(width: 210, height: 240)

    public init(model: SootlingAppModel) {
        let panel = NSPanel(
            contentRect: NSRect(origin: CGPoint(x: 80, y: 120), size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        self.panel = panel

        // The frame provider lets Wattson convert the mouse's screen position
        // into a gaze direction relative to wherever the panel was dragged.
        let view = PetView(model: model, panelFrame: { [weak panel] in panel?.frame })
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hostingView
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - Wattson

public struct PetView: View {
    @ObservedObject private var model: SootlingAppModel
    private let panelFrame: () -> CGRect?

    /// Live soot puffs / sparkles spawned by detected prompts.
    @State private var puffs: [Puff] = []
    @State private var lastReactionAt: Date?
    @State private var lastTier: PetReaction.Tier?
    @State private var lastBubble: Bubble?
    @State private var recentQuips: [String] = []
    @State private var hovering = false
    @State private var appearedAt = Date()

    private let center = CGPoint(x: 105, y: 158)
    /// No live prompt for this long → Wattson dozes off.
    private static let sleepAfter: TimeInterval = 480

    public init(model: SootlingAppModel, panelFrame: @escaping () -> CGRect? = { nil }) {
        self.model = model
        self.panelFrame = panelFrame
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let asleep = isAsleep(at: now)
            let gaze = gazeDirection(t: t, asleep: asleep)
            let anim = MotionState(now: now, t: t, lastReactionAt: lastReactionAt, tier: lastTier)

            ZStack {
                glow(anim, asleep: asleep)
                ambientParticles(anim)
                ForEach(puffs) { puff in
                    puffView(puff, now: now)
                }
                wattson(anim, gaze: gaze, asleep: asleep)
                if asleep {
                    snores(anim)
                }
                bubble(now: now)
                nameTag(asleep: asleep)
            }
            .frame(width: PetPanelController.panelSize.width,
                   height: PetPanelController.panelSize.height)
            .scaleEffect(hovering ? 1.05 : 1.0, anchor: .bottom)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { model.toggleStatsWindow() }
            .contextMenu {
                Text(model.healthState.mood)
                Divider()
                Button(model.petVisible ? "Hide Wattson" : "Show Wattson") {
                    model.togglePetVisibility()
                }
                Button("Scan now") { model.scanNow() }
                Button("Open stats") { model.toggleStatsWindow() }
            }
        }
        .onChange(of: model.lastReaction?.id) {
            guard let reaction = model.lastReaction else { return }
            spawnReaction(reaction)
        }
        .task {
            // Idle chatter so Wattson feels alive between prompts (but not while asleep).
            while !Task.isCancelled {
                let pause = Double.random(in: 75...150)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                let now = Date()
                let idleFor = now.timeIntervalSince(lastReactionAt ?? .distantPast)
                if idleFor > 60, !isAsleep(at: now) {
                    lastBubble = Bubble.idle(PetQuips.idle(for: model.healthState), at: now)
                }
            }
        }
    }

    // MARK: Liveliness

    private func isAsleep(at now: Date) -> Bool {
        guard !hovering else { return false }
        let lastActivity = max(appearedAt, lastReactionAt ?? .distantPast)
        return now.timeIntervalSince(lastActivity) > Self.sleepAfter
    }

    /// Where Wattson is looking, in -1…1 per axis (SwiftUI coords: +y is down).
    /// Follows the mouse cursor — wherever you're working — and falls back to a
    /// slow wander when the panel frame is unavailable.
    private func gazeDirection(t: Double, asleep: Bool) -> CGPoint {
        guard !asleep else { return .zero }
        if let frame = panelFrame() {
            let mouse = NSEvent.mouseLocation
            let petX = frame.minX + center.x
            let petY = frame.minY + (PetPanelController.panelSize.height - center.y)
            let dx = (mouse.x - petX) / 260
            let dy = (mouse.y - petY) / 260
            return CGPoint(
                x: max(-1, min(1, dx)),
                y: max(-1, min(1, -dy))
            )
        }
        return CGPoint(x: sin(t * 0.5) * 0.4, y: 0)
    }

    // MARK: Body

    private func wattson(_ anim: MotionState, gaze: CGPoint, asleep: Bool) -> some View {
        let state = model.healthState
        let breatheSpeed = asleep ? 0.8 : 1.4
        let breathe = 1 + sin(anim.t * breatheSpeed) * (asleep ? 0.035 : 0.025)
        let squashX = 1 + anim.bounce * 0.13
        let squashY = 1 - anim.bounce * 0.20
        // An occasional happy hop while thriving and awake.
        let hopCycle = anim.t.truncatingRemainder(dividingBy: 16)
        let hop = (state == .thriving && !asleep && hopCycle < 0.6)
            ? sin(hopCycle / 0.6 * .pi) * 10
            : 0
        let bob = sin(anim.t * 1.9) * 3 - anim.bounce * 9 - hop
        let sway = sin(anim.t * 0.7) * 2.2
        // Lean and tilt toward whatever Wattson is watching.
        let gazeTilt = gaze.x * 4
        let shake = anim.chokeEnvelope * sin(anim.t * 42) * 3

        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.16))
                .frame(width: 70, height: 14)
                .position(x: center.x, y: center.y + 52)
                .blur(radius: 3)

            ZStack {
                tufts(state)
                bodyBlob(state)
                face(anim, state: state, gaze: gaze, asleep: asleep)
                sprout(state)
                sweatDrop(anim, state: state)
            }
            .scaleEffect(
                x: breathe * squashX + anim.inhale,
                y: breathe * squashY + anim.inhale,
                anchor: .bottom
            )
            .rotationEffect(.degrees(sway + shake + gazeTilt + anim.actionAngle), anchor: .bottom)
            .position(x: center.x + gaze.x * 3, y: center.y + bob + anim.actionLift)
        }
    }

    private func bodyBlob(_ state: PetHealthState) -> some View {
        Circle()
            .fill(bodyGradient(state))
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.35), .clear],
                            center: .init(x: 0.35, y: 0.28),
                            startRadius: 2,
                            endRadius: 52
                        )
                    )
            )
            .frame(width: 88, height: 88)
            .shadow(color: shadowColor(state), radius: 10, y: 6)
    }

    // Fuzzy lumps around the crown so Wattson reads as a critter, not a ball.
    private func tufts(_ state: PetHealthState) -> some View {
        let color = tuftColor(state)
        return ZStack {
            Circle().fill(color).frame(width: 26, height: 26).offset(x: -30, y: -22)
            Circle().fill(color).frame(width: 22, height: 22).offset(x: 30, y: -20)
            Circle().fill(color).frame(width: 20, height: 20).offset(x: 0, y: -38)
            Circle().fill(color).frame(width: 18, height: 18).offset(x: 38, y: 8)
            Circle().fill(color).frame(width: 18, height: 18).offset(x: -40, y: 6)
        }
    }

    // A tiny sprout grows from Wattson's head while it's healthy.
    private func sprout(_ state: PetHealthState) -> some View {
        let show = state == .thriving || state == .content
        return ZStack {
            Capsule()
                .fill(Color.green)
                .frame(width: 3, height: 14)
                .offset(y: -46)
            Ellipse()
                .fill(Color.green.opacity(0.9))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(-35))
                .offset(x: -7, y: -50)
            Ellipse()
                .fill(Color.green.opacity(0.9))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(35))
                .offset(x: 7, y: -50)
        }
        .opacity(show ? 1 : 0)
        .scaleEffect(show ? 1 : 0.4, anchor: .bottom)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: show)
    }

    // A nervous sweat drop slides down when Wattson is struggling.
    private func sweatDrop(_ anim: MotionState, state: PetHealthState) -> some View {
        let show = state == .sluggish || state == .sooty
        let slide = (anim.t * 0.6).truncatingRemainder(dividingBy: 1)
        return Circle()
            .fill(Color.cyan.opacity(0.8))
            .frame(width: 8, height: 11)
            .offset(x: 34, y: -28 + CGFloat(slide) * 16)
            .opacity(show ? (1 - slide) * 0.9 : 0)
    }

    private func snores(_ anim: MotionState) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (anim.t * 0.45 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 10 + CGFloat(i) * 4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity((1 - phase) * 0.85))
                    .position(
                        x: center.x + 32 + CGFloat(phase) * 22 + CGFloat(i) * 7,
                        y: center.y - 42 - CGFloat(phase) * 30 - CGFloat(i) * 9
                    )
            }
        }
    }

    // MARK: Face

    private func face(_ anim: MotionState, state: PetHealthState, gaze: CGPoint, asleep: Bool) -> some View {
        let eyeOpen = blink(anim.t) * (1 + max(0, anim.bounce) * 0.35)

        return VStack(spacing: 7) {
            HStack(spacing: 16) {
                eyeUnit(anim, state: state, open: eyeOpen, gaze: gaze, asleep: asleep)
                eyeUnit(anim, state: state, open: eyeOpen, gaze: gaze, asleep: asleep)
            }
            mouth(state, anim: anim, asleep: asleep)
        }
        .offset(y: 4)
        .overlay(alignment: .center) {
            if state == .thriving || state == .content {
                HStack(spacing: 44) {
                    cheek
                    cheek
                }
                .offset(y: 6)
            }
        }
    }

    @ViewBuilder
    private func eyeUnit(_ anim: MotionState, state: PetHealthState, open: Double, gaze: CGPoint, asleep: Bool) -> some View {
        if asleep {
            // Peacefully closed: a soft downward arc.
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                p.addQuadCurve(to: CGPoint(x: 13, y: 4), control: CGPoint(x: 6.5, y: 9))
            }
            .stroke(Color.white.opacity(0.9), style: .init(lineWidth: 3, lineCap: .round))
            .frame(width: 13, height: 12)
        } else if anim.chokeEnvelope > 0.05 {
            // Dizzy X eyes while reeling from a heavy prompt.
            ZStack {
                Capsule().fill(Color.white.opacity(0.95)).frame(width: 13, height: 3)
                    .rotationEffect(.degrees(45))
                Capsule().fill(Color.white.opacity(0.95)).frame(width: 13, height: 3)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: 13, height: 14)
        } else if anim.breezeEnvelope > 0.05 {
            // Happy closed ^^ eyes for a feather-light prompt.
            Path { p in
                p.move(to: CGPoint(x: 0, y: 8))
                p.addQuadCurve(to: CGPoint(x: 13, y: 8), control: CGPoint(x: 6.5, y: 0))
            }
            .stroke(Color.white.opacity(0.95), style: .init(lineWidth: 3, lineCap: .round))
            .frame(width: 13, height: 12)
        } else {
            ZStack(alignment: .top) {
                eyebrow(state)
                eye(open: open, gaze: gaze, state: state)
                    .padding(.top, 5)
            }
        }
    }

    @ViewBuilder
    private func eyebrow(_ state: PetHealthState) -> some View {
        switch state {
        case .thriving, .content:
            EmptyView()
        case .sluggish:
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 12, height: 2.5)
                .rotationEffect(.degrees(12))
        case .sooty:
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 12, height: 2.5)
                .rotationEffect(.degrees(22))
        }
    }

    private func eye(open: Double, gaze: CGPoint, state: PetHealthState) -> some View {
        let baseHeight: CGFloat = state == .sluggish || state == .sooty ? 12 : 17
        return Capsule()
            .fill(Color.white.opacity(0.96))
            .frame(width: 14, height: max(2, baseHeight * open))
            .overlay(
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.88))
                        .frame(width: 7, height: 7)
                    // Catchlight makes the eyes read as glossy and alive.
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2.5, height: 2.5)
                        .offset(x: -1.5, y: -1.5)
                }
                .offset(x: gaze.x * 3.5, y: 1 + gaze.y * 2.5)
                .opacity(open > 0.4 ? 1 : 0)
            )
    }

    private var cheek: some View {
        Circle()
            .fill(Color.pink.opacity(0.35))
            .frame(width: 10, height: 10)
            .blur(radius: 1)
    }

    @ViewBuilder
    private func mouth(_ state: PetHealthState, anim: MotionState, asleep: Bool) -> some View {
        if asleep {
            // A tiny open "o" — softly snoring.
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 6 + CGFloat(abs(sin(anim.t * 0.8))) * 3)
        } else if anim.chokeEnvelope > 0.05 {
            // Wobbly open mouth mid-choking-fit.
            Ellipse()
                .fill(Color.black.opacity(0.6))
                .frame(width: 12, height: 10 + CGFloat(abs(sin(anim.t * 18))) * 5)
        } else if anim.puffEnvelope > 0.05 {
            // Small popping mouth in rhythm with the cough jerks.
            Ellipse()
                .fill(Color.black.opacity(0.55))
                .frame(width: 9, height: 5 + CGFloat(abs(sin(anim.t * 14))) * 5)
        } else {
            switch state {
            case .thriving:
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addQuadCurve(to: CGPoint(x: 24, y: 0), control: CGPoint(x: 12, y: 11))
                }
                .stroke(Color.black.opacity(0.55), style: .init(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 12)
            case .content:
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 16, height: 4)
            case .sluggish:
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 16, height: 4)
                    .rotationEffect(.degrees(-8))
            case .sooty:
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 8))
                    p.addQuadCurve(to: CGPoint(x: 22, y: 8), control: CGPoint(x: 11, y: -2))
                }
                .stroke(Color.white.opacity(0.55), style: .init(lineWidth: 3, lineCap: .round))
                .frame(width: 22, height: 10)
            }
        }
    }

    // MARK: Effects

    private func glow(_ anim: MotionState, asleep: Bool) -> some View {
        let pulse = 0.5 + 0.5 * sin(anim.t * (asleep ? 0.6 : 1.2))
        return Circle()
            .fill(glowColor)
            .frame(width: 120, height: 120)
            .blur(radius: 26)
            .opacity((0.18 + pulse * 0.12) * (asleep ? 0.4 : 1))
            .position(x: center.x, y: center.y)
    }

    // Continuously rising spores (healthy) or smoke flecks (sooty) — Wattson's aura.
    private func ambientParticles(_ anim: MotionState) -> some View {
        let dark = model.healthState == .sluggish || model.healthState == .sooty
        return ZStack {
            ForEach(0..<5, id: \.self) { i in
                let phase = (anim.t * 0.2 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let drift = sin(anim.t * 0.8 + Double(i)) * 12
                Circle()
                    .fill((dark ? Color.gray : Color.green).opacity((1 - phase) * 0.5))
                    .frame(width: 4 + CGFloat(i % 2) * 2)
                    .position(
                        x: center.x + drift + CGFloat(i - 2) * 14.0,
                        y: center.y + 20 - CGFloat(phase) * 90.0
                    )
            }
        }
    }

    @ViewBuilder
    private func puffView(_ puff: Puff, now: Date) -> some View {
        let progress = min(1, max(0, now.timeIntervalSince(puff.birth)) / Puff.lifetime)
        let rise = CGFloat(progress) * 78 + 26
        let wobble = sin(progress * 6 + Double(puff.dx)) * 5
        if puff.kind == .sparkle {
            Image(systemName: "sparkle")
                .font(.system(size: 10 + puff.intensity * 6))
                .foregroundStyle(Color.yellow.opacity((1 - progress) * 0.9))
                .rotationEffect(.degrees(progress * 180))
                .position(x: center.x + puff.dx + wobble, y: center.y - 10 - rise)
        } else {
            let size = (10 + puff.intensity * 28) * (0.55 + progress * 0.8)
            Circle()
                .fill(Color.black.opacity((1 - progress) * 0.5))
                .frame(width: size, height: size)
                .blur(radius: 1.5)
                .position(x: center.x + puff.dx + wobble, y: center.y - 10 - rise)
        }
    }

    // MARK: Bubble

    @ViewBuilder
    private func bubble(now: Date) -> some View {
        if let bubble = lastBubble {
            let age = now.timeIntervalSince(bubble.birth)
            if age >= 0, age < Bubble.lifetime {
                let progress = age / Bubble.lifetime
                // Springy pop-in: quick scale-up with a damped overshoot.
                let pop = min(1, age / 0.18) * (1 + 0.16 * exp(-age * 5) * sin(age * 20))

                VStack(spacing: 2) {
                    if let headline = bubble.headline {
                        Text(headline)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                    }
                    Text(bubble.text)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                    if let equiv = bubble.equivalents {
                        Text(equiv)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .opacity(0.82)
                            .padding(.top, 1)
                    }
                    if let source = bubble.source {
                        Text(source)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .opacity(0.60)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(bubbleGradient(bubble.tier))
                            .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
                        // Tail pointing down at Wattson.
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bubbleTailColor(bubble.tier))
                            .frame(width: 11, height: 11)
                            .rotationEffect(.degrees(45))
                            .offset(y: 4)
                    }
                )
                .frame(maxWidth: 220)
                .scaleEffect(pop, anchor: .bottom)
                .opacity(1 - max(0, (progress - 0.75) / 0.25))
                .offset(y: -CGFloat(progress) * 6)
                .position(x: center.x, y: center.y - 84)
            }
        }
    }

    private func bubbleGradient(_ tier: PetReaction.Tier?) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .breeze:
            colors = [Color(red: 0.15, green: 0.60, blue: 0.34), Color(red: 0.07, green: 0.42, blue: 0.25)]
        case .puff:
            colors = [Color(red: 0.78, green: 0.52, blue: 0.10), Color(red: 0.55, green: 0.33, blue: 0.05)]
        case .choke:
            colors = [Color(red: 0.75, green: 0.20, blue: 0.16), Color(red: 0.42, green: 0.07, blue: 0.10)]
        case nil:
            colors = [Color.black.opacity(0.8), Color.black.opacity(0.65)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func bubbleTailColor(_ tier: PetReaction.Tier?) -> Color {
        switch tier {
        case .breeze: Color(red: 0.07, green: 0.42, blue: 0.25)
        case .puff: Color(red: 0.55, green: 0.33, blue: 0.05)
        case .choke: Color(red: 0.42, green: 0.07, blue: 0.10)
        case nil: Color.black.opacity(0.65)
        }
    }

    private func nameTag(asleep: Bool) -> some View {
        let label = asleep ? "Wattson 💤" : (hovering ? model.healthState.mood : "Wattson")
        return Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(hovering ? 0.7 : 0.35)))
            .position(x: center.x, y: center.y + 70)
            .animation(.easeInOut(duration: 0.2), value: hovering)
    }

    // MARK: Reaction spawning

    private func spawnReaction(_ reaction: PetReaction) {
        let now = Date()
        lastReactionAt = now
        lastTier = reaction.tier

        let candidates = PetQuips.reactionLines(
            tier: reaction.tier,
            grams: reaction.grams,
            source: reaction.source,
            model: reaction.model,
            tokensOut: reaction.tokensOut
        )
        let fresh = candidates.filter { !recentQuips.contains($0) }
        let line = (fresh.isEmpty ? candidates : fresh).randomElement() ?? candidates[0]
        recentQuips.append(line)
        if recentQuips.count > 6 { recentQuips.removeFirst(recentQuips.count - 6) }

        // Vivid facts row — different equivalents per tier to match the drama.
        let g = reaction.grams
        let equiv: String? = {
            switch reaction.tier {
            case .breeze:
                let led = max(1, Int((g / 3.84 * 60).rounded()))
                let searches = max(1, Int((g / 0.2).rounded()))
                return "💡 \(led)min LED  ·  🔍 \(searches) search\(searches == 1 ? "" : "es")"
            case .puff:
                let car = max(1, Int((g / 0.251).rounded()))
                let netflix = max(1, Int((g / 55.0 * 3600).rounded()))
                return "🚗 \(car)m  ·  📺 \(netflix)s Netflix"
            case .choke:
                let car = max(1, Int((g / 0.251).rounded()))
                let netflix = max(1, Int((g / 55.0 * 60).rounded()))
                let charges = String(format: "%.1f", g / 5.0)
                return "🚗 \(car)m  ·  📺 \(netflix)min  ·  🔋 \(charges)×"
            }
        }()

        // Source attribution: "Claude Code · opus-4-8" or just "Claude Code".
        let modelShort: String? = {
            guard !reaction.model.isEmpty else { return nil }
            let stripped = reaction.model.hasPrefix("claude-")
                ? String(reaction.model.dropFirst(7))
                : reaction.model
            return String((stripped.components(separatedBy: "-202").first ?? stripped).prefix(16))
        }()
        let sourceLabel: String = modelShort.map { "\(reaction.source.displayName) · \($0)" }
            ?? reaction.source.displayName

        lastBubble = Bubble(
            headline: reaction.formattedGrams,
            text: line,
            equivalents: equiv,
            source: sourceLabel,
            tier: reaction.tier,
            birth: now
        )

        let kind: Puff.Kind = reaction.tier == .breeze ? .sparkle : .soot
        let count: Int
        switch reaction.tier {
        case .breeze: count = 2
        case .puff: count = 3
        case .choke: count = 5
        }
        for index in 0..<count {
            let puff = Puff(
                birth: now.addingTimeInterval(Double(index) * 0.12),
                intensity: reaction.intensity,
                kind: kind,
                dx: CGFloat([-14, 16, 0, -24, 24][index % 5])
            )
            puffs.append(puff)
            DispatchQueue.main.asyncAfter(deadline: .now() + Puff.lifetime + 0.3 + Double(index) * 0.12) {
                puffs.removeAll { $0.id == puff.id }
            }
        }
        // Safety cap so a burst of prompts can't grow the array unbounded.
        if puffs.count > 18 {
            puffs.removeFirst(puffs.count - 18)
        }
    }

    // MARK: Styling helpers

    private func bodyGradient(_ state: PetHealthState) -> LinearGradient {
        let colors: [Color]
        switch state {
        case .thriving: colors = [Color(red: 0.45, green: 0.85, blue: 0.45), Color(red: 0.18, green: 0.62, blue: 0.30)]
        case .content: colors = [Color(red: 0.40, green: 0.78, blue: 0.62), Color(red: 0.22, green: 0.58, blue: 0.45)]
        case .sluggish: colors = [Color(red: 0.55, green: 0.55, blue: 0.42), Color(red: 0.38, green: 0.36, blue: 0.30)]
        case .sooty: colors = [Color(red: 0.30, green: 0.30, blue: 0.32), Color(red: 0.10, green: 0.10, blue: 0.12)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func tuftColor(_ state: PetHealthState) -> Color {
        switch state {
        case .thriving: Color(red: 0.30, green: 0.70, blue: 0.36)
        case .content: Color(red: 0.28, green: 0.62, blue: 0.50)
        case .sluggish: Color(red: 0.44, green: 0.42, blue: 0.34)
        case .sooty: Color(red: 0.16, green: 0.16, blue: 0.18)
        }
    }

    private func shadowColor(_ state: PetHealthState) -> Color {
        switch state {
        case .thriving, .content: Color.green.opacity(0.4)
        case .sluggish: Color.orange.opacity(0.3)
        case .sooty: Color.black.opacity(0.5)
        }
    }

    private var glowColor: Color {
        switch model.healthState {
        case .thriving: .green
        case .content: .mint
        case .sluggish: .orange
        case .sooty: .gray
        }
    }

    // Eyes blink for ~0.14s every ~4.3s; returns an openness factor 0…1.
    private func blink(_ t: Double) -> Double {
        let cycle = t.truncatingRemainder(dividingBy: 4.3)
        guard cycle < 0.14 else { return 1 }
        return abs(cos(cycle / 0.14 * .pi))
    }
}

// MARK: - Supporting types

private struct MotionState {
    let now: Date
    let t: Double
    /// Damped 1…0 bounce envelope right after a reaction.
    let bounce: Double
    /// 1…0 envelopes while a tiered face override is active.
    let breezeEnvelope: Double
    let puffEnvelope: Double
    let chokeEnvelope: Double
    /// Choreographed body action for the current reaction: a sneeze (wind up,
    /// snap forward), a cough (rhythmic jerks), or a choking fit (convulsions
    /// then a dazed sway). Angle in degrees, lift in points (+ is down).
    let actionAngle: Double
    let actionLift: CGFloat
    /// Extra body scale during the sneeze inhale.
    let inhale: Double

    init(now: Date, t: Double, lastReactionAt: Date?, tier: PetReaction.Tier?) {
        self.now = now
        self.t = t
        guard let last = lastReactionAt, let tier else {
            bounce = 0
            breezeEnvelope = 0
            puffEnvelope = 0
            chokeEnvelope = 0
            actionAngle = 0
            actionLift = 0
            inhale = 0
            return
        }
        let s = now.timeIntervalSince(last)
        bounce = s >= 0 && s < 0.7 ? exp(-s * 5) * cos(s * 16) : 0

        var angle = 0.0
        var lift = 0.0
        var inh = 0.0

        switch tier {
        case .breeze:
            // Sneeze: lean back inhaling and puff up… aaa-CHOO! snap forward, recover.
            if s < 0.45 {
                let p = s / 0.45
                angle = -16 * p
                inh = 0.10 * p
            } else if s < 0.62 {
                let p = (s - 0.45) / 0.17
                angle = -16 + 40 * p
                lift = 7 * p
                inh = 0.10 * (1 - p)
            } else if s < 1.3 {
                let r = s - 0.62
                angle = 24 * exp(-r * 5.5) * cos(r * 12)
                lift = 7 * exp(-r * 4)
            }
            breezeEnvelope = s >= 0 && s < 1.3 ? 1 - s / 1.3 : 0
            puffEnvelope = 0
            chokeEnvelope = 0

        case .puff:
            // Cough: three fading forward jerks.
            for (k, start) in [0.10, 0.55, 1.00].enumerated() where s >= start && s < start + 0.3 {
                let u = (s - start) / 0.3
                angle += sin(.pi * u) * 13 * (1 - Double(k) * 0.22)
                lift += sin(.pi * u) * 4
            }
            breezeEnvelope = 0
            puffEnvelope = s >= 0 && s < 1.7 ? 1 - s / 1.7 : 0
            chokeEnvelope = 0

        case .choke:
            // Choking fit: alternating convulsions, then a dazed wobble.
            for (k, start) in [0.10, 0.50, 0.90, 1.30].enumerated() where s >= start && s < start + 0.33 {
                let u = (s - start) / 0.33
                let sign: Double = k.isMultiple(of: 2) ? 1 : -1
                angle += sign * sin(.pi * u) * 16
                lift += sin(.pi * u) * 6
            }
            if s >= 1.6, s < 2.6 {
                let d = s - 1.6
                angle += sin(d * 5) * 7 * (1 - d)
            }
            breezeEnvelope = 0
            puffEnvelope = 0
            chokeEnvelope = s >= 0 && s < 2.6 ? 1 - s / 2.6 : 0
        }

        actionAngle = angle
        actionLift = CGFloat(lift)
        inhale = inh
    }
}

private struct Puff: Identifiable {
    enum Kind { case soot, sparkle }

    static let lifetime: TimeInterval = 1.9
    let id = UUID()
    let birth: Date
    let intensity: Double
    let kind: Kind
    let dx: CGFloat
}

private struct Bubble {
    static let lifetime: TimeInterval = 4.5

    let headline: String?
    let text: String
    let equivalents: String?
    let source: String?
    let tier: PetReaction.Tier?
    let birth: Date

    static func idle(_ text: String, at date: Date) -> Bubble {
        Bubble(headline: nil, text: text, equivalents: nil, source: nil, tier: nil, birth: date)
    }
}
