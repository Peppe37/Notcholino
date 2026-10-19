// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import SwiftUI

/// Where a window can go: halves, quarters, or the whole screen. The nine zones are the nine cells of a 3 × 3 grid.
enum SnapZone: CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    /// Column and row (row 0 is the top) in the 3 × 3 grid
    var cell: (col: Int, row: Int) {
        switch self {
        case .topLeft: return (0, 0)
        case .top: return (1, 0)
        case .topRight: return (2, 0)
        case .left: return (0, 1)
        case .center: return (1, 1)
        case .right: return (2, 1)
        case .bottomLeft: return (0, 2)
        case .bottom: return (1, 2)
        case .bottomRight: return (2, 2)
        }
    }

    static func at(col: Int, row: Int) -> SnapZone { allCases.first { $0.cell.col == col && $0.cell.row == row } ?? .center }

    /// The part of the screen it covers, as fractions (x, y from the top-left, width, height): for drawing the preview
    var fractions: CGRect {
        switch self {
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .top: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .left: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .center: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .right: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottom: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        }
    }
}

/// What the little dot in the middle does
enum SnapCenterAction: String { case fill, center }

/// What is going on while a window is being moved, for the page in the notch to draw
final class SnapState: ObservableObject {
    static let shared = SnapState()
    @Published var dragging = false
    @Published var zone: SnapZone?

    /// The page views that are on screen (one per display with a notch)
    private var views: [Weak] = []
    private struct Weak { weak var view: SnapHostingView? }

    func register(_ view: SnapHostingView) {
        views.removeAll { $0.view == nil || $0.view === view }
        views.append(Weak(view: view))
    }

    /// The zone under the pointer: the rectangle drawn in the notch, cut in thirds both ways, with a little room around it
    func zone(at point: NSPoint) -> SnapZone? {
        for entry in views {
            guard let rect = entry.view?.rectOnScreen, rect.insetBy(dx: -14, dy: -14).contains(point) else { continue }
            let col = min(2, max(0, Int((point.x - rect.minX) / rect.width * 3)))
            let row = min(2, max(0, Int((rect.maxY - point.y) / rect.height * 3)))
            return SnapZone.at(col: col, row: row)
        }
        return nil
    }
}

/// Moves a window to a zone when the user lets go of it over the rectangle in the notch. It works out that a window is being
/// moved (and not resized, or text being selected) by watching the window itself: it grabs the window under the pointer at the
/// mouse-down and sees whether it moves with the pointer. All the Accessibility calls are made off the main thread, with a
/// short timeout, so a busy app can never freeze Notcholino.
final class SnapEngine {
    static let shared = SnapEngine()

    var centerAction: SnapCenterAction = .fill
    var gap: CGFloat = 0

    private var monitors: [Any] = []
    private let queue = DispatchQueue(label: "com.giuseppe.Notcholino.snap", qos: .userInteractive)
    private var window: AXUIElement?
    private var startOrigin = CGPoint.zero
    private var startSize = CGSize.zero
    private var moving = false
    private var lastCheck = Date.distantPast
    private var host: NotcholinoHost? { SnapBridge.shared.host }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() } as Any,
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.mouseDragged() } as Any,
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() } as Any,
        ]
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        finish()
    }

    // MARK: Following the pointer

    private func mouseDown() {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async { [weak self] in
            guard let self else { return }
            self.window = nil; self.moving = false
            guard AXIsProcessTrusted() else { return }
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.15)
            var hit: AXUIElement?
            let r1 = AXUIElementCopyElementAtPosition(system, Float(mouse.x), Float(primaryHeight - mouse.y), &hit)
            guard r1 == .success, let hit else { return }
            var pid: pid_t = 0
            AXUIElementGetPid(hit, &pid)
            guard pid != getpid() else { return }
            guard let element = Self.window(of: hit) else { return }
            AXUIElementSetMessagingTimeout(element, 0.15)
            var full: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &full) == .success, (full as? Bool) == true { return }
            guard let origin = Self.point(element, kAXPositionAttribute), let size = Self.size(element) else { return }
            self.window = element
            self.startOrigin = origin
            self.startSize = size
        }
    }

    private func mouseDragged() {
        let now = Date()
        if SnapState.shared.dragging {
            // Moving: tell the page which zone the pointer is over
            let zone = SnapState.shared.zone(at: NSEvent.mouseLocation)
            if zone != SnapState.shared.zone { SnapState.shared.zone = zone }
            return
        }
        guard now.timeIntervalSince(lastCheck) > 0.08 else { return }
        lastCheck = now
        queue.async { [weak self] in
            guard let self, let window = self.window, !self.moving,
                  let origin = Self.point(window, kAXPositionAttribute), let size = Self.size(window) else { return }
            let moved = hypot(origin.x - self.startOrigin.x, origin.y - self.startOrigin.y)
            // Moved, and not resized: the window is being dragged
            guard moved > 8, abs(size.width - self.startSize.width) < 2, abs(size.height - self.startSize.height) < 2 else { return }
            self.moving = true
            DispatchQueue.main.async {
                SnapState.shared.dragging = true
                self.host?.setNotchOpen(true)
            }
        }
    }

    private func mouseUp() {
        let mouse = NSEvent.mouseLocation
        guard SnapState.shared.dragging else { window = nil; return }
        let zone = SnapState.shared.zone(at: mouse)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let window = self.window
        finish()
        guard let zone, let window, let screen else { return }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let visible = screen.visibleFrame
        let center = centerAction, gap = self.gap
        // A moment for the system to let go of the window, then place it
        queue.asyncAfter(deadline: .now() + 0.06) {
            let size = Self.size(window) ?? CGSize(width: 800, height: 600)
            var target = Self.target(for: zone, in: visible, center: center, current: size)
            target = target.insetBy(dx: gap / 2, dy: gap / 2)
            // Back to the top-left origin Accessibility uses
            let frame = CGRect(x: target.minX, y: primaryHeight - target.maxY, width: target.width, height: target.height)
            Self.setFrame(window, frame)
        }
    }

    private func finish() {
        window = nil
        moving = false
        if SnapState.shared.dragging || SnapState.shared.zone != nil {
            SnapState.shared.dragging = false
            SnapState.shared.zone = nil
            host?.setNotchOpen(false)
        }
    }

    // MARK: Geometry and Accessibility

    /// The window's frame for a zone, in the usual Cocoa coordinates (origin bottom-left), inside the visible part of the screen
    static func target(for zone: SnapZone, in v: CGRect, center: SnapCenterAction, current: CGSize) -> CGRect {
        if zone == .center, center == .center {
            let w = min(current.width, v.width), h = min(current.height, v.height)
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        }
        let f = zone.fractions
        return CGRect(x: v.minX + f.minX * v.width, y: v.maxY - (f.minY + f.height) * v.height, width: f.width * v.width, height: f.height * v.height)
    }

    /// The window an element belongs to: the element itself when it is the window (the title bar), else the one it says it is in,
    /// else the first window found going up through the parents
    private static func window(of start: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = start
        for _ in 0..<10 {
            guard let element = current else { return nil }
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success, (role as? String) == kAXWindowRole { return element }
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &win) == .success, let win { return (win as! AXUIElement) }
            var parent: CFTypeRef?
            current = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success ? (parent as! AXUIElement?) : nil
        }
        return nil
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let v = value else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let v = value else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    private static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin, size = frame.size
        guard let o = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return }
        // Position, size, position again: some apps only accept the last one once the size has changed
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, o)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, o)
    }
}

/// What Snap asks of the app
final class SnapBridge {
    static let shared = SnapBridge()
    var host: NotcholinoHost?
}
