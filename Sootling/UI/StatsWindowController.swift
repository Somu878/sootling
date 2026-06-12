import AppKit
import SwiftUI

@MainActor
public final class StatsWindowController {
    private let window: NSWindow

    public init(model: SootlingAppModel) {
        window = NSWindow(
            contentRect: NSRect(x: 120, y: 160, width: 840, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wattson — Sootling"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 440, height: 460)
        window.contentView = NSHostingView(rootView: StatsPopoverView(model: model))
    }

    public func toggle() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        }
    }
}

