import AppKit
import SwiftUI

/// A click-through, full-screen overlay that behaves like smoke in a room:
/// each prompt releases blobs that rise to the top of the screen, settle into a
/// smog layer along the "ceiling" that thickens with further prompts, lingers,
/// and then slowly dissolves. Purely ambient: it ignores all mouse events and
/// pauses rendering entirely while the air is clear.
@MainActor
public final class ScreenSmokeController {
    private let panel: NSPanel

    public init(model: SootlingAppModel) {
        panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
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
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: ScreenSmokeView(model: model))
    }

    public func show() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(screen.frame, display: false)
        }
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - Smoke rendering

public struct ScreenSmokeView: View {
    @ObservedObject private var model: SootlingAppModel
    /// Blobs currently rising toward the ceiling.
    @State private var blobs: [SmokeBlob] = []
    /// Smoke mass that has reached the ceiling; each entry ramps in when its
    /// blob arrives, holds, then decays.
    @State private var ceiling: [CeilingPuff] = []

    /// How long a blob takes to reach the top.
    private static let riseDuration: TimeInterval = 2.4

    public init(model: SootlingAppModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: blobs.isEmpty && ceiling.isEmpty)) { context in
                let now = context.date
                ZStack(alignment: .top) {
                    ceilingLayer(now: now, size: geo.size)
                    ForEach(blobs) { blob in
                        blobView(blob, now: now)
                    }
                }
            }
            .onChange(of: model.lastReaction?.id) {
                guard let reaction = model.lastReaction else { return }
                spawn(reaction: reaction, in: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Rising blobs

    @ViewBuilder
    private func blobView(_ blob: SmokeBlob, now: Date) -> some View {
        let age = now.timeIntervalSince(blob.birth)
        if age >= 0, age < blob.lifetime {
            let progress = age / blob.lifetime
            // Ease-out climb: fast lift-off, slowing as it nears the ceiling.
            let climb = 1 - pow(1 - progress, 2)
            // Visible mid-flight, fading as the mass merges into the ceiling.
            let envelope = min(1, age / 0.5) * (1 - pow(progress, 3))
            let scale = 1 + progress * 0.7
            let sway = sin(age * 1.1 + blob.seed) * 26
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [blob.color.opacity(blob.peakOpacity * envelope), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: blob.size * scale / 2
                    )
                )
                .frame(width: blob.size * scale, height: blob.size * scale * 0.85)
                .position(
                    x: blob.origin.x + sway + blob.driftX * age,
                    y: blob.origin.y - (blob.origin.y - 40) * climb
                )
        }
    }

    // MARK: Ceiling smog

    @ViewBuilder
    private func ceilingLayer(now: Date, size: CGSize) -> some View {
        let density = ceilingDensity(at: now)
        if density > 0.005 {
            let height = 60 + 190 * density
            let t = now.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color(white: 0.10).opacity(0.55 * density),
                        Color(white: 0.16).opacity(0.30 * density),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)

                // Slow-drifting billows along the layer's underside so the smog
                // reads as smoke, not a gradient bar.
                ForEach(0..<3, id: \.self) { i in
                    let phase = Double(i) * 2.1
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.12).opacity(0.30 * density), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 230
                            )
                        )
                        .frame(width: 460, height: 180)
                        .position(
                            x: size.width * (0.2 + 0.3 * CGFloat(i)) + sin(t * 0.18 + phase) * 70,
                            y: height * 0.55 + sin(t * 0.27 + phase) * 14
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Total smog mass at the ceiling right now (0…1). Each contribution ramps
    /// in as its blob arrives, holds for a while, then exponentially dissolves.
    private func ceilingDensity(at now: Date) -> Double {
        let hold: TimeInterval = 7
        let dissolveTau: TimeInterval = 16
        let total = ceiling.reduce(0.0) { sum, puff in
            let age = now.timeIntervalSince(puff.settlesAt)
            guard age > 0 else { return sum }
            let ramp = min(1, age / 1.6)
            let decay = age > hold ? exp(-(age - hold) / dissolveTau) : 1
            return sum + puff.amount * ramp * decay
        }
        return min(1, total)
    }

    // MARK: Spawning

    private func spawn(reaction: PetReaction, in size: CGSize) {
        guard size.width > 0 else { return }
        let count: Int
        let peak: Double
        let color: Color
        let ceilingAmount: Double
        switch reaction.tier {
        case .breeze:
            count = 1
            peak = 0.07
            color = Color(white: 0.55)
            ceilingAmount = 0.03
        case .puff:
            count = 6
            peak = 0.16
            color = Color(white: 0.30)
            ceilingAmount = 0.16
        case .choke:
            count = 14
            peak = 0.28
            color = Color(white: 0.12)
            ceilingAmount = 0.42
        }

        let now = Date()
        for index in 0..<count {
            let blob = SmokeBlob(
                birth: now.addingTimeInterval(Double(index) * 0.07),
                lifetime: Self.riseDuration + Double.random(in: -0.4...0.4),
                origin: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: size.height * 0.45...size.height)
                ),
                driftX: CGFloat.random(in: -22...22),
                size: CGFloat.random(in: 200...420),
                peakOpacity: peak,
                color: color,
                seed: Double.random(in: 0...(2 * .pi))
            )
            blobs.append(blob)
            DispatchQueue.main.asyncAfter(deadline: .now() + blob.lifetime + 0.2 + Double(index) * 0.07) {
                blobs.removeAll { $0.id == blob.id }
            }
        }

        // The prompt's smoke mass joins the ceiling once the blobs arrive.
        let puff = CeilingPuff(amount: ceilingAmount, settlesAt: now.addingTimeInterval(Self.riseDuration * 0.8))
        ceiling.append(puff)
        DispatchQueue.main.asyncAfter(deadline: .now() + 95) {
            ceiling.removeAll { $0.id == puff.id }
        }

        // A burst of prompts shouldn't pile up unbounded fog.
        if blobs.count > 36 {
            blobs.removeFirst(blobs.count - 36)
        }
        if ceiling.count > 40 {
            ceiling.removeFirst(ceiling.count - 40)
        }
    }
}

private struct SmokeBlob: Identifiable {
    let id = UUID()
    let birth: Date
    let lifetime: TimeInterval
    let origin: CGPoint
    let driftX: CGFloat
    let size: CGFloat
    let peakOpacity: Double
    let color: Color
    let seed: Double
}

private struct CeilingPuff: Identifiable {
    let id = UUID()
    let amount: Double
    let settlesAt: Date
}
