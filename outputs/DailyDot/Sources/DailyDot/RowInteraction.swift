import AppKit
import SwiftUI

/// Native mouse tracking defers dragging until the pointer moves 6pt.
/// Checkbox and trash remain separate controls; editing replaces this surface.
struct TaskDragSurface: NSViewRepresentable {
    let task: TodoTask
    let beginEditing: () -> Void
    let beginDrag: () -> Void
    let endDrag: () -> Void
    let hoverChanged: (Bool) -> Void
    let makePreview: (CGSize, CGFloat) -> NSImage?

    func makeNSView(context: Context) -> DragSurfaceView { DragSurfaceView() }
    func updateNSView(_ view: DragSurfaceView, context: Context) {
        view.task = task
        view.beginEditing = beginEditing
        view.beginDrag = beginDrag
        view.endDrag = endDrag
        view.hoverChanged = hoverChanged
        view.makePreview = makePreview
    }
}

final class DragSurfaceView: NSView, NSDraggingSource {
    var task: TodoTask?
    var beginEditing: (() -> Void)?
    var beginDrag: (() -> Void)?
    var endDrag: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var makePreview: ((CGSize, CGFloat) -> NSImage?)?
    private var hoverTracking: NSTrackingArea?
    private var origin = NSPoint.zero
    private var started = false
    private var scrollTimer: Timer?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseMoved(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
    override func mouseDown(with event: NSEvent) {
        hoverChanged?(true)
        origin = event.locationInWindow
        started = false
    }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 && !started { beginEditing?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !started, let task,
              hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 6 else { return }
        // Measure the entire row, not the text/handle region receiving the drag.
        guard let anchor = rowAnchor(), let window,
              let image = makePreview?(anchor.bounds.size, window.backingScaleFactor) else { return }
        let rowRect = convert(anchor.bounds, from: anchor)
        let start = convert(origin, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        let frame = rowRect.insetBy(dx: -TaskDragPreviewMetrics.shadowInset, dy: -TaskDragPreviewMetrics.shadowInset)
            .offsetBy(dx: current.x - start.x, dy: current.y - start.y)
        started = true
        // Capture/render at full opacity before dimming the source placeholder.
        beginDrag?()
        let item = NSPasteboardItem()
        item.setString(task.id.uuidString, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.draggingFrame = frame
        // A custom component preserves the full row instead of treating it as
        // a standard icon thumbnail with system thumbnail sizing.
        draggingItem.imageComponentsProvider = {
            let component = NSDraggingImageComponent(key: .init(rawValue: "DailyDot.taskRow"))
            component.contents = image
            component.frame = NSRect(origin: .zero, size: frame.size)
            return [component]
        }
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.scrollNearEdge() }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        scrollTimer?.invalidate(); scrollTimer = nil
        started = false
        endDrag?()
    }
    private func rowAnchor() -> TaskRowCaptureView? {
        guard let id = task?.id else { return nil }
        var root: NSView = self
        while let parent = root.superview { root = parent }
        func find(in view: NSView) -> TaskRowCaptureView? {
            if let anchor = view as? TaskRowCaptureView, anchor.taskID == id { return anchor }
            for child in view.subviews { if let match = find(in: child) { return match } }
            return nil
        }
        return find(in: root)
    }
    private func scrollNearEdge() {
        guard let scroll = enclosingScrollView, let window, let document = scroll.documentView else { return }
        let mouse = scroll.contentView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let clip = scroll.contentView
        let relativeY = mouse.y - clip.bounds.minY
        let delta: CGFloat = relativeY < 25 ? -6 : (relativeY > clip.bounds.height - 25 ? 6 : 0)
        guard delta != 0 else { return }
        let y = min(max(0, clip.bounds.minY + delta), max(0, document.bounds.height - clip.bounds.height))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scroll.reflectScrolledClipView(clip)
    }
    deinit { scrollTimer?.invalidate() }
}

enum TaskDragPreviewMetrics {
    static let shadowInset: CGFloat = 6
}

/// Provides the real full-row bounds without intercepting checkbox/text events.
struct TaskRowCaptureAnchor: NSViewRepresentable {
    let taskID: UUID
    func makeNSView(context: Context) -> TaskRowCaptureView { TaskRowCaptureView() }
    func updateNSView(_ view: TaskRowCaptureView, context: Context) { view.taskID = taskID }
}
final class TaskRowCaptureView: NSView {
    var taskID: UUID?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Uses the AppKit field editor for reliable focus, select-all, and Esc handling.
struct InlineTaskEditor: NSViewRepresentable {
    @Binding var text: String
    let finish: (_ cancel: Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async { [weak field] in
            guard let field, field.window != nil else { return }
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        if view.stringValue != text { view.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTaskEditor
        private var finished = false
        init(parent: InlineTaskEditor) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) { complete(cancel: false) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) { complete(cancel: false); return true }
            if command == #selector(NSResponder.cancelOperation(_:)) { complete(cancel: true); return true }
            return false
        }
        private func complete(cancel: Bool) {
            guard !finished else { return }
            finished = true
            parent.finish(cancel)
        }
    }
}
