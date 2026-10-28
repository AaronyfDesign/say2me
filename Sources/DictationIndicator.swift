import AppKit
import SwiftUI
import ApplicationServices

/// Floating "listening" pill shown near the text caret while dictating.
/// Position is best-effort: caret bounds via the Accessibility API first,
/// then the mouse location, then bottom-center of the main screen.
final class DictationIndicator {
    static let shared = DictationIndicator()
    private var panel: NSPanel?
    private var lastAnchor: NSPoint?

    // must be called on the main thread
    func update(state: DictationController.State) {
        switch state {
        case .idle:
            hide()
        case .recording:
            let anchor = resolveAnchor()
            lastAnchor = anchor
            show(symbol: "mic.fill", text: "听写中…", anchor: anchor)
        case .transcribing:
            let anchor = lastAnchor ?? resolveAnchor()
            show(symbol: "hourglass", text: "识别中…", anchor: anchor)
        }
    }

    // MARK: - Panel

    private func show(symbol: String, text: String, anchor: NSPoint) {
        let hosting = NSHostingView(rootView: IndicatorView(symbol: symbol, text: text))
        hosting.setFrameSize(hosting.fittingSize)
        let size = CGSize(width: min(hosting.fittingSize.width, 240),
                          height: hosting.fittingSize.height)

        let p = panel ?? makePanel()
        panel = p
        p.contentView = hosting
        position(p, contentSize: size, anchor: anchor)
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = true // never take focus, never block clicks
        return p
    }

    private func position(_ p: NSPanel, contentSize: CGSize, anchor: NSPoint) {
        let screen = NSScreen.screens.first { NSPointInRect(anchor, $0.frame) } ?? NSScreen.main
        guard let s = screen else { return }
        let visible = s.visibleFrame
        var x = anchor.x - contentSize.width / 2
        var y = anchor.y - contentSize.height - 14 // just below the anchor point
        x = max(visible.minX + 4, min(x, visible.maxX - contentSize.width - 4))
        y = max(visible.minY + 4, min(y, visible.maxY - contentSize.height))
        p.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: contentSize), display: true)
    }

    // MARK: - Anchor resolution

    private func resolveAnchor() -> NSPoint {
        if let p = caretCocoaPoint() { return p }
        let mouse = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: { NSPointInRect(mouse, $0.frame) }) {
            return NSPoint(x: mouse.x, y: mouse.y + 20) // above the cursor
        }
        if let s = NSScreen.main {
            return NSPoint(x: s.visibleFrame.midX, y: s.visibleFrame.minY + 80)
        }
        return .zero
    }

    /// Caret position of the focused text field via the Accessibility API.
    /// Global AX coordinates are top-left origin; convert to Cocoa bottom-left.
    private func caretCocoaPoint() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }
        let sys = AXUIElementCreateSystemWide()
        var focusedCF: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString,
                                            &focusedCF) == .success,
              let focusedRaw = focusedCF else { return nil }
        let focused = unsafeBitCast(focusedRaw, to: AXUIElement.self)
        var rangeCF: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString,
                                            &rangeCF) == .success,
              let rangeVal = rangeCF else { return nil }
        var boundsCF: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal, &boundsCF) == .success,
            let boundsRaw = boundsCF else { return nil }
        let boundsVal = unsafeBitCast(boundsRaw, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal, .cgRect, &rect) else { return nil }

        // flip AX (top-left, primary-display origin) to Cocoa (bottom-left)
        guard let topY = NSScreen.screens.map({ $0.frame.maxY }).max() else { return nil }
        let bottomCaretY = topY - rect.maxY          // cocoa y of the caret's bottom edge
        return NSPoint(x: rect.midX, y: bottomCaretY)
    }
}

private struct IndicatorView: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .foregroundStyle(.white)
        .fixedSize()
    }
}
