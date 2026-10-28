import AppKit
import SwiftUI
import QuartzCore

final class DotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowController: NSObject, NSWindowDelegate, ObservableObject {
    @Published private(set) var isPinned = UserDefaults.standard.bool(forKey: "DailyDot.pinned")
    private var animating = false
    private let dotSize: CGFloat = 40
    private let expandedSize = NSSize(width: 390, height: 550)
    private let inset: CGFloat = 20
    private var expanded = false
    private var anchor = NSPoint.zero // Circle center in global screen coordinates.
    private var window: DotWindow!
    private var dot: DotView!
    private var host: NSHostingView<ContentView>!
    private var monitor: Any?
    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
        super.init()
        window = DotWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView()
        window.contentView = root
        host = NSHostingView(rootView: ContentView(store: store, controller: self))
        root.addSubview(host)
        dot = DotView()
        dot.controller = self
        root.addSubview(dot)
        if let position = UserDefaults.standard.array(forKey: "DailyDot.position") as? [Double], position.count == 2 {
            anchor = NSPoint(x: position[0], y: position[1])
        } else if let screen = NSScreen.main {
            anchor = NSPoint(x: screen.visibleFrame.maxX - 70, y: screen.visibleFrame.maxY - 70)
        }
        clampAnchor()
        layout()
        window.orderFrontRegardless()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.expanded else { return event }
            if event.window !== self.window {
                NotificationCenter.default.post(name: .dailyDotCommit, object: nil)
            } else if let hit = self.window.contentView?.hitTest(event.locationInWindow), !(hit is NSTextField), !((hit as? NSTextView)?.isFieldEditor ?? false) {
                NotificationCenter.default.post(name: .dailyDotCommit, object: nil)
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func togglePin() {
        isPinned.toggle()
        UserDefaults.standard.set(isPinned, forKey: "DailyDot.pinned")
        window.level = isPinned ? .floating : .normal
    }

    func toggle() {
        guard !animating else { return }
        NotificationCenter.default.post(name: .dailyDotCommit, object: nil)
        store.refreshDay()
        let opening = !expanded
        // Keep the full-size canvas during animation, preserving the circle anchor.
        expanded = true
        layout()
        if opening { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            expanded = opening; layout(); return
        }
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let image = bitmap.cgImage, let root = window.contentView else {
            expanded = opening; layout(); return
        }
        animating = true
        let canvas = NSView(frame: root.bounds)
        canvas.wantsLayer = true
        root.addSubview(canvas, positioned: .below, relativeTo: dot)
        host.isHidden = true
        window.hasShadow = false
        let target = CGPoint(x: expandedSize.width - inset - dotSize / 2,
                             y: expandedSize.height - inset - dotSize / 2)
        // Thin horizontal slices form a curved funnel, then flow into the dot.
        // Public Core Animation only; no private Dock/WindowServer APIs.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak canvas] in
            canvas?.removeFromSuperview()
            guard let self else { return }
            self.expanded = opening
            self.animating = false
            self.layout()
        }
        let duration: CFTimeInterval = 0.4
        // CSS equivalent: cubic-bezier(0.32, 0.08, 0.24, 1).
        // Gentle start, acceleration through the middle, soft ease-out at arrival.
        let timing = CAMediaTimingFunction(controlPoints: 0.32, 0.08, 0.24, 1)
        let frameCount = 120
        let count = 180
        let stripHeight = expandedSize.height / CGFloat(count)
        let size = expandedSize

        // Each source point travels on an actual cubic Bezier, not a straight
        // translation with eased time. Left/right edges have separate controls.
        func mapped(_ source: CGPoint, progress p: CGFloat) -> CGPoint {
            let u = source.x / size.width
            let v = source.y / size.height
            let destination = CGPoint(
                x: target.x + (source.x - size.width / 2) * dotSize / size.width,
                y: target.y + (source.y - size.height / 2) * dotSize / size.height)
            let dx = destination.x - source.x
            let dy = destination.y - source.y
            let belly = sin(.pi * v)
            // Opposing edge offsets pull the sides inward, while a small
            // common bow carries the contents along a gently curved funnel.
            let inward = (1 - 2 * u) * 90 * (0.4 + 0.6 * belly)
            let c1 = CGPoint(x: source.x + 0.12 * dx + inward * 0.65,
                             y: source.y + 0.06 * dy - 18 * belly - 34 * v * v)
            let c2 = CGPoint(x: source.x + 0.70 * dx + inward * 0.35 + 42 * belly,
                             y: source.y + 0.88 * dy - 22 * belly - 18 * v * v)
            let q = 1 - p
            return CGPoint(
                x: q*q*q*source.x + 3*q*q*p*c1.x + 3*q*p*p*c2.x + p*p*p*destination.x,
                y: q*q*q*source.y + 3*q*q*p*c1.y + 3*q*p*p*c2.y + p*p*p*destination.y)
        }

        func animationGroup(_ animations: [CAAnimation]) -> CAAnimationGroup {
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.timingFunction = timing
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            return group
        }

        for row in 0..<count {
            let layer = CALayer()
            layer.contents = image
            layer.contentsGravity = .resize
            layer.contentsRect = CGRect(x: 0, y: CGFloat(row) / CGFloat(count), width: 1, height: 1 / CGFloat(count))
            let bottom = CGFloat(row) * stripHeight
            let top = bottom + stripHeight
            var positions: [NSValue] = []
            var bounds: [NSValue] = []
            for frame in 0...frameCount {
                let t = CGFloat(frame) / CGFloat(frameCount)
                let p = opening ? 1 - t : t
                let left = mapped(CGPoint(x: 0, y: (bottom + top) / 2), progress: p)
                let right = mapped(CGPoint(x: size.width, y: (bottom + top) / 2), progress: p)
                let low = mapped(CGPoint(x: size.width / 2, y: bottom), progress: p)
                let high = mapped(CGPoint(x: size.width / 2, y: top), progress: p)
                positions.append(NSValue(point: CGPoint(x: (left.x + right.x) / 2, y: (low.y + high.y) / 2)))
                bounds.append(NSValue(rect: CGRect(x: 0, y: 0, width: right.x - left.x, height: high.y - low.y + 0.4)))
            }
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = positions
            let dimensions = CAKeyframeAnimation(keyPath: "bounds")
            dimensions.values = bounds
            canvas.layer?.addSublayer(layer)
            layer.add(animationGroup([position, dimensions]), forKey: "genie")
        }

        // The mask follows the same curved coordinate mapping as the contents.
        // Elliptical source corners grow continuously from 25pt to half-size,
        // so the final silhouette is a 40pt circle, rather than a squeezed line.
        let mask = CAShapeLayer()
        mask.frame = canvas.bounds
        mask.fillColor = NSColor.black.cgColor
        canvas.layer?.mask = mask
        var paths: [CGPath] = []
        var opacities: [NSNumber] = []
        for frame in 0...frameCount {
            let t = CGFloat(frame) / CGFloat(frameCount)
            let p = opening ? 1 - t : t
            let rounded = p * p * (3 - 2 * p)
            let rx = 25 + (size.width / 2 - 25) * rounded
            let ry = 25 + (size.height / 2 - 25) * rounded
            let centers = [CGPoint(x: size.width - rx, y: size.height - ry),
                           CGPoint(x: rx, y: size.height - ry),
                           CGPoint(x: rx, y: ry),
                           CGPoint(x: size.width - rx, y: ry)]
            let path = CGMutablePath()
            for corner in 0..<4 {
                // Sample both arcs and straight edges: their mapped image is curved.
                let center = centers[corner]
                for step in 0...16 {
                    let angle = CGFloat(corner) * .pi / 2 + CGFloat(step) / 16 * .pi / 2
                    let point = mapped(CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle)), progress: p)
                    if corner == 0 && step == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
                let next = centers[(corner + 1) % 4]
                let angle = CGFloat(corner + 1) * .pi / 2
                let from = CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
                let to = CGPoint(x: next.x + rx * cos(angle), y: next.y + ry * sin(angle))
                for step in 1...24 {
                    let fraction = CGFloat(step) / 24
                    path.addLine(to: mapped(CGPoint(x: from.x + (to.x - from.x) * fraction,
                                                    y: from.y + (to.y - from.y) * fraction), progress: p))
                }
            }
            path.closeSubpath()
            paths.append(path)
            // Keep the silhouette visible while it bends, then fade gently into
            // the dot. Zero slope at both fade endpoints avoids an abrupt vanish.
            let fade = max(0, min(1, (p - 0.18) / 0.82))
            opacities.append(NSNumber(value: Double(1 - fade * fade * (3 - 2 * fade))))
        }
        let outline = CAKeyframeAnimation(keyPath: "path")
        outline.values = paths
        mask.add(animationGroup([outline]), forKey: "curvedOutline")
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = opacities
        canvas.layer?.add(animationGroup([opacity]), forKey: "coordinatedFade")
        CATransaction.commit()
    }

    func moveDot(by delta: NSSize) {
        guard !animating else { return }
        anchor.x += delta.width; anchor.y += delta.height
        clampAnchor(); layout(); savePosition()
    }

    private func screenForAnchor() -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func clampAnchor() {
        guard let frame = screenForAnchor()?.visibleFrame else { return }
        // Keep the circle reachable without restricting dragging to a single corner.
        anchor.x = min(max(anchor.x, frame.minX + dotSize / 2), frame.maxX - dotSize / 2)
        anchor.y = min(max(anchor.y, frame.minY + dotSize / 2), frame.maxY - dotSize / 2)
    }

    private func layout() {
        let size = expanded ? expandedSize : NSSize(width: dotSize, height: dotSize)
        let origin = expanded
            ? NSPoint(x: anchor.x - size.width + inset + dotSize / 2, y: anchor.y - size.height + inset + dotSize / 2)
            : NSPoint(x: anchor.x - dotSize / 2, y: anchor.y - dotSize / 2)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        host.isHidden = !expanded
        host.frame = NSRect(origin: .zero, size: size)
        dot.frame = NSRect(x: expanded ? size.width - inset - dotSize : 0, y: expanded ? size.height - inset - dotSize : 0, width: dotSize, height: dotSize)
        window.level = expanded ? (isPinned ? .floating : .normal) : .floating
        window.hasShadow = expanded
    }

    private func savePosition() { UserDefaults.standard.set([Double(anchor.x), Double(anchor.y)], forKey: "DailyDot.position") }
    @objc private func screensChanged() { clampAnchor(); layout(); savePosition() }
    func windowDidResignKey(_ notification: Notification) { NotificationCenter.default.post(name: .dailyDotCommit, object: nil) }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) }; NotificationCenter.default.removeObserver(self) }
}

private final class DotView: NSView {
    weak var controller: WindowController?
    private var start = NSPoint.zero
    private var last = NSPoint.zero
    private var dragged = false
    override func draw(_ dirtyRect: NSRect) {
        // Neutral solid gray in both states.
        NSColor(calibratedWhite: 0.48, alpha: 1).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation; last = start; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if hypot(point.x - start.x, point.y - start.y) > 3 { dragged = true }
        if dragged { controller?.moveDot(by: NSSize(width: point.x - last.x, height: point.y - last.y)) }
        last = point
    }
    override func mouseUp(with event: NSEvent) { if !dragged { controller?.toggle() } }
    override func accessibilityLabel() -> String? { "展开或收起待办清单" }
}
