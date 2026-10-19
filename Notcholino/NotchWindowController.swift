// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// Receives what is dropped on the notch (see `DropCatcher`)
final class NotchDropView: NSView {
    var notchID = UUID()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Not quite transparent: macOS lets a drag pass through a window whose pixels are fully clear (one percent is invisible)
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard ShelfManager.shared.isEnabled, ShelfManager.shared.dragActive else { return [] }
        NotificationCenter.default.post(name: .notchDropTargeted, object: notchID, userInfo: ["on": true])
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ShelfManager.shared.isEnabled && ShelfManager.shared.dragActive ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NotificationCenter.default.post(name: .notchDropTargeted, object: notchID, userInfo: ["on": false])
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NotificationCenter.default.post(name: .notchDropTargeted, object: notchID, userInfo: ["on": false])
        guard ShelfManager.shared.isEnabled else { return false }
        let board = sender.draggingPasteboard
        var accepted = false
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach { ShelfManager.shared.add(fileURL: $0) }
            accepted = true
        } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            ShelfManager.shared.add(imageData: data)
            accepted = true
        }
        if accepted { NotificationCenter.default.post(name: .notchDropped, object: notchID) }
        return accepted
    }
}

// MARK: - NSHostingView con scroll wheel e acceptsFirstMouse

final class NotchHostingView: NSHostingView<AnyView> {
    var notchID: UUID = UUID()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        NotificationCenter.default.post(
            name: .notchScrollWheel,
            object: notchID,
            userInfo: [
                "dx": event.scrollingDeltaX,
                "dy": event.scrollingDeltaY,
                "phase": event.phase.rawValue,
                "momentum": event.momentumPhase.rawValue,
                "inverted": event.isDirectionInvertedFromDevice
            ]
        )
    }
}

extension Notification.Name {
    static let notchScrollWheel = Notification.Name("notchScrollWheel")
    static let notchLayoutChanged = Notification.Name("notchLayoutChanged")
    static let notchMouseLeft = Notification.Name("notchMouseLeft")
    static let notchMouseEntered = Notification.Name("notchMouseEntered")
    static let notchMouseMoved = Notification.Name("notchMouseMoved")
    static let notchDropTargeted = Notification.Name("notchDropTargeted")
    static let notchDropped = Notification.Name("notchDropped")
}

// MARK: - Window Controller

class NotchWindowController: NSWindowController {

    /// Size of the visible notch (not the window), used to decide where clicks are ours.
    private var notchSize = NSSize(width: 174, height: 32)
    /// True while the notch is open (hover or HUD): then the whole notch keeps it open, not just the opening zone
    private var isOpen = false
    private var monitors: [Any] = []
    let notchID = UUID()

    let targetScreen: NSScreen

    init(screen: NSScreen) {
        self.targetScreen = screen

        let W: CGFloat = 520
        let H: CGFloat = 340

        let panel = NSPanel(
            contentRect: NSRect(
                x: screen.frame.midX - W / 2,
                y: screen.frame.maxY - H,
                width: W, height: H),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = false
        panel.level              = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable          = false

        super.init(window: panel)

        var notchWidth: CGFloat = 162      // a typical one, for Macs without a notch
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }
        let root = AnyView(NotchContentView(notchID: notchID, topInset: screen.safeAreaInsets.top, hardwareWidth: notchWidth))
        let hosting = NotchHostingView(rootView: root)
        hosting.notchID = notchID
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        // Don't let SwiftUI resize the window to its content (it did: 406x210, and
        // the constraint update loop crashed with NSGenericException)
        hosting.sizingOptions = []

        // Host inside a plain container so the hosting view can never drive the
        // window's size or size limits
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: W, height: H)))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        NotificationCenter.default.addObserver(
            forName: .notchLayoutChanged, object: nil, queue: .main
        ) { [weak self] notif in
            guard (notif.object as? UUID) == self?.notchID else { return }
            guard let w = notif.userInfo?["w"] as? CGFloat,
                  let h = notif.userInfo?["h"] as? CGFloat else { return }
            self?.notchSize = NSSize(width: w, height: h)
            self?.isOpen = notif.userInfo?["open"] as? Bool ?? false
            self?.updateMouseTransparency()
        }

        // The window stays at full size (resizing it made the expansion glitch), so
        // instead let clicks fall through to other apps whenever the cursor is
        // outside the visible notch.
        panel.ignoresMouseEvents = true
        let handler: (NSEvent) -> Void = { [weak self] _ in
            // The mouse moves freely again: any drag to or from the shelf is over
            ShelfManager.shared.draggingOut = false
            if ShelfManager.shared.dragActive { ShelfManager.shared.dragActive = false }
            self?.hideCatcher()
            self?.updateMouseTransparency()
        }
        // Dragging a file toward the notch opens the shelf. Events of other apps' drags come to the global monitors.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.pasteboardCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        }) { monitors.append(g) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in self?.handleDrag() }) { monitors.append(g) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            ShelfManager.shared.dragActive = false
            self?.hideCatcher()
            self?.updateMouseTransparency()
        }) { monitors.append(g) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { monitors.append(l) }
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }

    /// Where the pointer counts as being on the notch.
    /// Once the notch is open, anywhere on it keeps it open. To *open* it, the default is a thin strip along the top
    /// edge, a bit narrower than the hardware notch, so that moving to a browser's tab bar or address bar doesn't
    /// trigger it by accident. "Normal" (Settings → General) is the whole closed notch.
    private func hoverRect(in f: NSRect) -> NSRect {
        let whole = NSRect(x: f.midX - notchSize.width / 2, y: f.maxY - notchSize.height,
                           width: notchSize.width, height: notchSize.height).insetBy(dx: -4, dy: -4)
        if isOpen || UserDefaults.standard.integer(forKey: "hoverArea") == 1 { return whole }

        // Width of the hardware notch (the gap between the two sides of the menu bar), or a typical one
        var hardwareWidth: CGFloat = 162
        if let left = targetScreen.auxiliaryTopLeftArea, let right = targetScreen.auxiliaryTopRightArea {
            hardwareWidth = targetScreen.frame.width - left.width - right.width
        }
        let width = min(max(hardwareWidth * 0.8, 90), notchSize.width)
        let height: CGFloat = 12
        return NSRect(x: f.midX - width / 2, y: f.maxY - height, width: width, height: height)
    }

    private var pasteboardCountAtMouseDown = 0

    /// The notch's own window sits at the screen-saver level, and macOS doesn't offer windows that high as drop targets.
    /// So while a file is being dragged near the notch, a small invisible window one level lower waits right there to take it.
    private lazy var catcher: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: 500)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        let view = NotchDropView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        view.notchID = notchID
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }()

    private func hideCatcher() {
        if catcher.isVisible { catcher.orderOut(nil) }
    }

    /// Where a dragged file counts as being on the notch: a wider strip than for hovering, since you are carrying something
    private func dragRect(in f: NSRect) -> NSRect {
        if isOpen { return hoverRect(in: f) }
        let width = max(notchSize.width + 120, 260)
        return NSRect(x: f.midX - width / 2, y: f.maxY - 40, width: width, height: 40)
    }

    private func handleDrag() {
        guard let window, ShelfManager.shared.isEnabled else { return }
        let board = NSPasteboard(name: .drag)
        // Only a drag that put files or an image on the drag pasteboard (moving a window, selecting text, etc. don't)
        guard board.changeCount != pasteboardCountAtMouseDown,
              board.availableType(from: [.fileURL, .tiff, .png]) != nil else { return }
        let zone = dragRect(in: window.frame)
        let mouse = NSEvent.mouseLocation
        let inside = zone.contains(mouse)
        if ShelfManager.shared.dragActive != inside { ShelfManager.shared.dragActive = inside }
        // The catcher has to be in place a little before the pointer arrives: the system picks the window under a drag
        // at each movement
        if zone.insetBy(dx: -30, dy: -30).contains(mouse) {
            if catcher.frame != zone { catcher.setFrame(zone, display: false) }
            if !catcher.isVisible { catcher.orderFrontRegardless() }
        } else {
            hideCatcher()
        }
    }

    private func updateMouseTransparency() {
        guard let window else { return }
        // A file is being dragged out of the shelf: keep the notch (and the drag) alive until it lands
        if ShelfManager.shared.draggingOut { return }
        if ShelfManager.shared.dragActive { return }
        let f = window.frame
        let mouse = NSEvent.mouseLocation
        let inside = hoverRect(in: f).contains(mouse)
        // Only tell the view about the mouse while it is over the notch (position relative to the
        // top-center of the window, so the view can hit-test its own controls)
        if inside {
            NotificationCenter.default.post(
                name: .notchMouseMoved, object: notchID,
                userInfo: ["x": mouse.x - f.midX, "y": f.maxY - mouse.y])
        }
        guard window.ignoresMouseEvents == inside else { return }
        window.ignoresMouseEvents = !inside
        // A window that ignores events never gets mouseExited, so tell the view
        if inside {
            NotificationCenter.default.post(name: .notchMouseEntered, object: notchID)
        } else {
            NotificationCenter.default.post(name: .notchMouseLeft, object: notchID)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Notch Shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var flareRadius:  CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(cornerRadius, flareRadius) }
        set { cornerRadius = newValue.first; flareRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (w, h, r1, r2) = (rect.width, rect.height, flareRadius, cornerRadius)
        p.move(to: .init(x: 0, y: 0))
        p.addArc(center: .init(x: 0,       y: r1),     radius: r1, startAngle: .degrees(-90), endAngle: .degrees(0),   clockwise: false)
        p.addArc(center: .init(x: r1+r2,   y: h-r2),   radius: r2, startAngle: .degrees(180), endAngle: .degrees(90),  clockwise: true)
        p.addArc(center: .init(x: w-r1-r2, y: h-r2),   radius: r2, startAngle: .degrees(90),  endAngle: .degrees(0),   clockwise: true)
        p.addArc(center: .init(x: w,       y: r1),     radius: r1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Main Notch Content View

/// The panels the notch can show, in display order.
enum NotchTab: Int, CaseIterable {
    case controlCenter = -2, shelf = -1, music = 0, calendar = 1, notchy = 2, extensions = 3
}

struct NotchContentView: View {
    let notchID: UUID
    /// Height of the hardware notch on this screen (0 on Macs without one)
    let topInset: CGFloat
    @State private var isHovering   = false
    @State private var closing      = false
    @State private var activeTab: NotchTab = .music
    @State private var goingForward = true
    @State private var hoveredDot: NotchTab?
    @State private var scrollAcc: CGFloat = 0
    @State private var scrollHandled = false
    @State private var lastScrollSwitch = Date.distantPast
    @State private var collapseTask: Task<Void, Never>?

    @AppStorage("nowPlayingEnabled")    private var nowPlayingEnabled    = true
    @AppStorage("calendarEnabled")      private var calendarEnabled      = true
    @AppStorage("controlCenterEnabled") private var controlCenterEnabled = true
    @AppStorage("shelfEnabled")         private var shelfEnabled = true
    @ObservedObject private var shelf = ShelfManager.shared
    @ObservedObject private var notchy = NotchySettings.shared
    @ObservedObject private var notchyPresence = NotchyPresence.shared
    @ObservedObject private var popups = PopupCenter.shared
    @State private var dropTargeted = false
    /// Reverses the direction of the two-finger swipe (and of the mouse wheel)
    @AppStorage("invertScroll")         private var invertScroll = false
    @AppStorage("calDisplayMode")       private var calDisplayMode = 0
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var focusMonitor = FocusMonitor.shared
    private var focusOn: Bool { focusMonitor.isFocused }

    @StateObject private var music   = MusicManager()
    @StateObject private var sysEvt  = SystemEventsManager()
    @ObservedObject private var calMgr = CalendarManager.shared
    @ObservedObject private var extensionManager = ExtensionManager.shared

    @AppStorage("notchWidth")  private var tuningW: Double = 0
    @AppStorage("notchHeight") private var tuningH: Double = 0

    /// Width of the hardware notch of this screen (185 pt on the 14" MacBook Pro), measured from the gap in the menu bar.
    /// The closed pill, and the strip that grows under it, are exactly this wide so they line up with the real notch.
    let hardwareWidth: CGFloat
    // Collapsed pill: as wide and as tall as the real notch
    /// The black of the real notch is a little wider than the gap macOS leaves in the menu bar (the curve of its sides), so
    /// the drawn one is 4 pt wider than the gap: that is what makes the two look like one
    private var baseW: CGFloat { hardwareWidth + 4 }
    private let baseH: CGFloat = 32
    private let flare: CGFloat = 12

    private var enabledTabs: [NotchTab] {
        NotchTab.allCases.filter {
            switch $0 {
            case .controlCenter: return controlCenterEnabled
            // The shelf has a page only while it holds something (or something is being dragged to it)
            case .shelf:         return shelfEnabled && (!shelf.items.isEmpty || shelf.pending > 0 || shelf.dragActive)
            case .music:         return nowPlayingEnabled
            case .calendar:      return calendarEnabled
            case .notchy:        return notchy.enabled && notchy.pageVisible
            case .extensions:    return !extensionManager.pages.isEmpty
            }
        }
    }

    /// The tab actually on screen: the selected one, or the first enabled if it was switched off
    private var shownTab: NotchTab? {
        let tabs = enabledTabs
        if tabs.contains(activeTab) { return activeTab }
        return tabs.contains(.music) ? .music : tabs.first
    }

    private var hoverExpands: Bool { (isHovering || (shelfEnabled && shelf.dragActive)) && !enabledTabs.isEmpty }

    /// Space reserved above the tab dots so they clear the hardware notch
    private var topPad: CGFloat { topInset > 0 ? topInset + 2 : 24 }
    private let dotsRowH: CGFloat = 14
    private let dotPitch: CGFloat = 16

    private var isPlayingCompact: Bool {
        nowPlayingEnabled && music.isPlaying && !isHovering && !isSystemHudActive
    }

    private var isSystemHudActive: Bool {
        switch sysEvt.currentMode {
        case .volume, .brightness: return true
        default: return false
        }
    }

    /// Icons that live inside the black, beside the hardware notch: the moon on the left, plugins' icons on the right
    private var notchyPeeking: Bool { notchyPresence.peeking && notchy.enabled && !isExpanded }
    private var leftIconCount: Int { isExpanded ? 0 : (focusOn ? 1 : 0) + (notchyPeeking ? 1 : 0) }
    private var rightIconCount: Int { isExpanded ? 0 : pluginManager.sideIcons.count }
    private let iconSlot: CGFloat = 22

    /// Room the icons need on each side of the hardware notch (the same on both, so the notch stays centered)
    private var iconWing: CGFloat {
        let n = max(leftIconCount, rightIconCount)
        return n == 0 ? 0 : CGFloat(n) * iconSlot + 8
    }

    private var pillW: CGFloat {
        let base = baseW + CGFloat(tuningW) + flare * 2
        let music: CGFloat = isPlayingCompact ? 130 : 0 // Extra width to clear wide MacBook Pro hardware notches
        return base + music + iconWing * 2
    }

    private var pillH: CGFloat { baseH + CGFloat(tuningH) }

    // Expanded size based on mode
    private var expandW: CGFloat {
        if hoverExpands { return 400 }
        return isSystemHudActive ? 340 : 400
    }

    private var expandH: CGFloat {
        // The month grid can have six weeks: give it room so it doesn't touch the bottom edge
        let monthExtra: CGFloat = (shownTab == .calendar && calDisplayMode == 0) ? 22 : 0
        // More than one row of plugin buttons (four fit on a row) needs a taller panel
        let pluginRowsExtra: CGFloat = (shownTab == .controlCenter && pluginManager.buttonPlugins.count > 4) ? 36 : 0
        let baseH: CGFloat = ((shownTab == .music) ? (180 + 24) : (200 + 24)) + (topPad - 24) + (dotsRowH - 9) + monthExtra + pluginRowsExtra
        if hoverExpands {
            return isSystemHudActive ? baseH + 46 : baseH
        } else {
            switch sysEvt.currentMode {
            case .volume, .brightness: return 54 // scaled down from 60 to fit perfectly when closed
            default: return baseH
            }
        }
    }

    private var isExpanded: Bool {
        return hoverExpands || isSystemHudActive
    }

    /// What grows under the closed notch (a popup, or a plugin's countdown), as part of the notch itself
    private var notchExtension: NotchExtension? {
        guard !isExpanded else { return nil }
        if let popup = popups.current { return .popup(popup) }
        if let ext = pluginManager.extensionText { return .text(ext.text, Color(hex: ext.colorHex) ?? .white) }
        return nil
    }

    private var curW: CGFloat {
        if isExpanded { return expandW }
        // The strip is exactly as wide as the notch (as the notch is right now: wider while music plays, say);
        // a long text shrinks and is cut to fit, the notch never widens for it
        return pillW
    }
    private var curH: CGFloat { isExpanded ? expandH : pillH + (notchExtension?.height ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Invisible footprint to maintain size and catch hover
                Color.clear
                    .frame(width: curW, height: curH)
                    .contentShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))

                // Content Layer
                Group {
                    if isExpanded {
                        VStack(spacing: 0) {
                            if hoverExpands || !isSystemHudActive {
                                VStack(spacing: 0) {
                                    Spacer().frame(height: topPad)
                                    if isMusicMode && enabledTabs.count > 1 {
                                        tabDots
                                    } else {
                                        Spacer().frame(height: dotsRowH)
                                    }
                                    if let tab = shownTab {
                                        tabContent(tab)
                                            .id(tab)
                                            // While the notch closes only the whole content fades: a second, sliding
                                            // fade of the tab would show as a ghost
                                            .transition(closing ? .identity : .asymmetric(
                                                insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                                                removal:   .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)))
                                    }
                                }
                            }

                            if isSystemHudActive {
                                activeContent
                                    .frame(height: isHovering ? 46 : 54, alignment: .bottom)
                                    .padding(.bottom, isHovering ? 0 : 8)
                                    .scaleEffect(isHovering ? 0.7 : 0.85) // Scale down appropriately
                            }
                        }
                        .frame(width: expandW, height: expandH)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.14))))
                    } else if isPlayingCompact || notchExtension != nil {
                        VStack(spacing: 0) {
                            if isPlayingCompact {
                                compactMusicContent.frame(width: pillW, height: pillH)
                            } else {
                                Color.clear.frame(height: pillH)
                            }
                            if let ext = notchExtension {
                                NotchExtensionView(content: ext)
                                    .frame(height: ext.height)
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: curW)
                        .transition(.opacity)
                    }
                }
                // Top aligned: the content stays put while the shape closes over it, instead of sliding up
                .frame(width: curW, height: curH, alignment: .top)
                // Perfect clipping to avoid ghosting
                .clipShape(NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare))
            }
            // Icons beside the closed notch, inside its black: the notch grows a little wider to hold them (like it does for the
            // album art and the waveform). Placed from the middle, next to the hardware notch.
            .overlay(alignment: .top) {
                let edge = (baseW + CGFloat(tuningW)) / 2 + 4
                ZStack {
                    if focusOn && !isExpanded {
                        SideIcon(symbol: "moon.fill", color: Color(red: 0.62, green: 0.55, blue: 1))
                            .offset(x: -(edge + 4 + iconSlot / 2))
                    }
                    if notchyPeeking {
                        NotchyCube(mood: notchyPresence.mood, size: 20, alive: false)
                            .offset(x: -(edge + 4 + iconSlot / 2 + (focusOn ? iconSlot : 0)))
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                    ForEach(Array(pluginManager.sideIcons.enumerated()), id: \.offset) { i, icon in
                        if !isExpanded {
                            SideIcon(symbol: icon.symbol, color: Color(hex: icon.colorHex) ?? .white)
                                .offset(x: edge + 4 + iconSlot / 2 + CGFloat(i) * iconSlot)
                        }
                    }
                }
                .frame(height: pillH)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: notchExtension)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: iconWing)
            .background(
                // Background and Shadow Layer
                NotchShape(cornerRadius: isExpanded ? 28 : 10, flareRadius: flare)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(isExpanded ? 0.6 : 0), radius: 24, y: 16)
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curH)
            .animation(.spring(response: 0.38, dampingFraction: 0.74), value: curW)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: sysEvt.currentMode)
            .animation(.spring(response: 0.3,  dampingFraction: 0.8),  value: isPlayingCompact)
            .onAppear { publishLayout() }
            .onChange(of: isHovering) { _ in publishLayout() }
            .onChange(of: sysEvt.currentMode) { _ in publishLayout() }
            .onChange(of: music.isPlaying) { _ in publishLayout() }
            .onChange(of: shownTab) { _ in publishLayout() }
            .onChange(of: notchExtension) { _ in publishLayout() }
            .onReceive(NotificationCenter.default.publisher(for: .notchDropTargeted)) { notif in
                if (notif.object as? UUID) == notchID { dropTargeted = notif.userInfo?["on"] as? Bool ?? false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchDropped)) { notif in
                guard (notif.object as? UUID) == notchID else { return }
                setHovering(true)            // stay open after the drop, as long as the pointer is on the notch
                shelf.dragActive = false
            }
            .onChange(of: shelf.dragActive) { dragging in
                // Something is being dragged to the notch: open on the shelf
                if dragging, shelfEnabled { goingForward = false; activeTab = .shelf }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchMouseEntered)) { notif in
                if (notif.object as? UUID) == notchID { setHovering(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchMouseLeft)) { notif in
                if (notif.object as? UUID) == notchID { setHovering(false); hoveredDot = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchMouseMoved)) { notif in
                guard (notif.object as? UUID) == notchID,
                      let x = notif.userInfo?["x"] as? CGFloat,
                      let y = notif.userInfo?["y"] as? CGFloat else { return }
                updateHoveredDot(x: x, y: y)
            }
            // Click-and-drag horizontally: left goes to the next panel
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { val in
                        guard isExpanded, isMusicMode else { return }
                        if val.translation.width < -30 {
                            step(1)
                        } else if val.translation.width > 30 {
                            step(-1)
                        }
                    }
            )
            // Two-finger horizontal swipe on the trackpad: same direction as the drag
            .onReceive(NotificationCenter.default.publisher(for: .notchScrollWheel)) { notif in
                guard (notif.object as? UUID) == notchID, isExpanded, isMusicMode,
                      let info = notif.userInfo,
                      let dx = info["dx"] as? CGFloat,
                      let dy = info["dy"] as? CGFloat else { return }
                handleScroll(dx: dx, dy: dy,
                             phase: NSEvent.Phase(rawValue: info["phase"] as? UInt ?? 0),
                             momentum: NSEvent.Phase(rawValue: info["momentum"] as? UInt ?? 0),
                             inverted: info["inverted"] as? Bool ?? true)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(calMgr)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(_ tab: NotchTab) -> some View {
        switch tab {
        case .controlCenter: ControlCenterNotchView()
        case .shelf:         ShelfNotchView(dropTargeted: dropTargeted)
        case .music:         NowPlayingNotchView(music: music)
        case .calendar:      CalendarNotchView()
        case .notchy:        NotchyNotchView(musicPlaying: music.isPlaying)
        case .extensions:    ExtensionNotchView()
        }
    }

    private var tabDots: some View {
        HStack(spacing: dotPitch - 14) {
            ForEach(enabledTabs, id: \.self) { tab in
                let hovered = hoveredDot == tab
                Circle()
                    .fill(shownTab == tab ? Color.white : Color.white.opacity(hovered ? 0.65 : 0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(hovered ? 1.8 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
                    .frame(width: 14, height: dotsRowH)
                    .contentShape(Rectangle())
                    .onTapGesture { select(tab) }
            }
        }
        .frame(height: dotsRowH)
    }

    private func select(_ tab: NotchTab) {
        let tabs = enabledTabs
        guard let from = shownTab.flatMap({ tabs.firstIndex(of: $0) }),
              let to = tabs.firstIndex(of: tab), from != to else { return }
        goingForward = to > from
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { activeTab = tab }
    }

    /// Move one panel forward (+1) or back (-1) among the enabled ones
    private func step(_ delta: Int) {
        let tabs = enabledTabs
        guard tabs.count > 1, let shown = shownTab, let i = tabs.firstIndex(of: shown) else { return }
        let n = max(0, min(tabs.count - 1, i + delta))
        if n != i { select(tabs[n]) }
    }

    private func updateHoveredDot(x: CGFloat, y: CGFloat) {
        let tabs = enabledTabs
        var found: NotchTab?
        if isExpanded, isMusicMode, tabs.count > 1 {
            let cy = topPad + dotsRowH / 2
            for (i, tab) in tabs.enumerated() {
                let cx = (CGFloat(i) - CGFloat(tabs.count - 1) / 2) * dotPitch
                if abs(x - cx) <= dotPitch / 2, abs(y - cy) <= dotsRowH / 2 + 2 { found = tab }
            }
        }
        if found != hoveredDot { hoveredDot = found }
    }

    private func handleScroll(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase, inverted: Bool) {
        if !momentum.isEmpty { return }   // ignore inertia after the fingers lift
        // Direction of the fingers, whatever the "natural scrolling" setting; the app setting can reverse it
        let finger = (inverted ? dx : -dx) * (invertScroll ? -1 : 1)

        if phase.isEmpty {
            // Mouse wheel: no gesture phases, so debounce
            guard abs(dx) > abs(dy), abs(dx) > 0,
                  Date().timeIntervalSince(lastScrollSwitch) > 0.3 else { return }
            lastScrollSwitch = Date()
            step(finger < 0 ? 1 : -1)
            return
        }

        if phase.contains(.began) || phase.contains(.mayBegin) {
            scrollAcc = 0
            scrollHandled = false
        }
        if abs(dx) > abs(dy) {
            scrollAcc += finger
            if !scrollHandled && abs(scrollAcc) > 24 {
                scrollHandled = true
                step(scrollAcc < 0 ? 1 : -1)
            }
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            scrollAcc = 0
            scrollHandled = false
        }
    }

    private func setHovering(_ hovering: Bool) {
        collapseTask?.cancel()
        if hovering {
            // Permissions may have been granted in System Settings meanwhile
            PermissionsManager.shared.refresh()
            calMgr.refreshAccess()
            closing = false
            // Notchy just said something under the notch: moving to it opens Notchy's page, where the whole note is
            if popups.current?.opensNotchy == true, notchy.enabled, notchy.pageVisible, !isExpanded {
                goingForward = false
                activeTab = .notchy
                popups.dismiss()
            }
            withAnimation { isHovering = true }
        } else {
            collapseTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                // One frame to let the view pick up the closing transition before the notch actually closes
                await MainActor.run { closing = true }
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled else { await MainActor.run { closing = false }; return }
                await MainActor.run { withAnimation { isHovering = false } }
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run { closing = false }
            }
        }
    }

    private func publishLayout() {
        NotificationCenter.default.post(
            name: .notchLayoutChanged, object: notchID,
            userInfo: ["w": curW, "h": curH, "open": isExpanded])
    }

    private var isMusicMode: Bool {
        sysEvt.currentMode == .music || sysEvt.currentMode == .calendar
    }

    // MARK: - Compact Content (Live Activity Style)
    @ViewBuilder
    private var compactMusicContent: some View {
        HStack(spacing: 0) {
            // Left: Album Art
            ZStack {
                if let img = music.albumArt {
                    Image(nsImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, flare + 14)

            Spacer()

            // Right: Waveform
            WaveformView(isPlaying: true, color: music.primaryColor)
                .frame(width: 24, height: 14)
                .padding(.trailing, flare + 14)
        }
    }

    // MARK: - Expanded Content
    @ViewBuilder
    private var activeContent: some View {
        switch sysEvt.currentMode {
        case .volume(let v):
            SystemHUDView(
                icon: v == 0 ? "speaker.slash.fill" : (v < 0.4 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                value: CGFloat(v),
                isVolume: true
            )
        case .brightness(let b):
            SystemHUDView(icon: "sun.max.fill", value: CGFloat(b), isVolume: false)

        case .mediaKey, .micMute:
            EmptyView()

        default:
            EmptyView()
        }
    }
}

// MARK: - System HUD (Volume / Brightness)

struct SystemHUDView: View {
    let icon:  String
    let value: CGFloat
    let isVolume: Bool

    @AppStorage("soundTheme")      private var soundTheme = 1
    @AppStorage("soundShowText")   private var soundShowText = true

    @AppStorage("displayTheme")    private var displayTheme = 1
    @AppStorage("displayShowText") private var displayShowText = true

    private var barColor: Color {
        if isVolume {
            if soundTheme == 0 { return .white }
            if value > 0.8 { return .red }
            if value > 0.6 { return .yellow }
            return .white
        } else {
            if displayTheme == 0 { return .white }
            return .yellow
        }
    }

    private var textString: String {
        return "\(Int(value * 100))%"
    }

    private var showText: Bool {
        return isVolume ? soundShowText : displayShowText
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(barColor)
                .frame(width: 24)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(barColor)
                        .frame(width: max(6, geo.size.width * value), height: 6)
                }
            }
            .frame(height: 6)

            if showText {
                Text(textString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Media Key HUD

struct MediaKeyHUDView: View {
    let event: NotchMode.MediaKeyKind
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(music.trackName.isEmpty ? "—" : music.trackName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artistName.isEmpty ? "" : music.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var iconName: String {
        switch event {
        case .play:     return "play.fill"
        case .pause:    return "pause.fill"
        case .next:     return "forward.fill"
        case .previous: return "backward.fill"
        }
    }
}

// MARK: - Mic HUD

struct MicHUDView: View {
    let muted: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(muted ? .red : .green)
                .frame(width: 32)

            Text(muted ? "Microphone Off" : "Microphone On")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Now Playing Notch View

struct NowPlayingNotchView: View {
    @ObservedObject var music: MusicManager

    @AppStorage("npLeftAccessory")  private var leftAccessory  = "shuffle"
    @AppStorage("npRightAccessory") private var rightAccessory = "repeat"
    @AppStorage("npLiveWaveform")   private var liveWaveform   = true
    @AppStorage("npColorStyle")     private var colorStyle     = 2

    @ObservedObject private var spotify = SpotifyAuth.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    @State private var isDraggingSeek = false
    @State private var seekPreview:    Double = 0
    @State private var iconScale: CGFloat = 1.0

    /// A track is known (playing or paused)
    private var hasTrack: Bool { music.activePlayer != "None" && !music.trackName.isEmpty }

    /// Color of the waveform for the chosen style: white, the artwork color, or the start of the gradient
    private var waveColor: Color { colorStyle == 0 ? Color.white.opacity(0.85) : music.primaryColor }

    private var activeFill: AnyShapeStyle {
        switch colorStyle {
        case 0:
            return AnyShapeStyle(Color.white.opacity(0.85))
        case 1:
            return AnyShapeStyle(music.primaryColor)
        case 2:
            return music.primaryColor.spectrogramGradient()
        default:
            return AnyShapeStyle(Color.white.opacity(0.85))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(music.primaryColor.spectrogramGradient())
                    if let img = music.albumArt {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if !hasTrack, let blocked = permissions.blockedPlayer {
                        // A player is open but Notcholino isn't allowed to read it yet
                        Text("\(blocked.name) needs permission")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        AuthorizeButton(title: blocked.state == .denied ? "Open Settings" : "Authorize") {
                            permissions.requestAutomation(bundleID: blocked.bundleID)
                        }
                    } else {
                        Text(hasTrack ? music.trackName : "Nothing Playing")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(hasTrack ? music.artistName : "Open Spotify or Music")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if music.isPlaying && liveWaveform {
                    WaveformView(isPlaying: music.isPlaying, primary: waveColor, gradient: colorStyle == 2)
                        .frame(width: 24, height: 16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                openActivePlayer()
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let pct: CGFloat = music.trackDuration > 0
                        ? (isDraggingSeek ? CGFloat(seekPreview / music.trackDuration) : CGFloat(music.trackPosition / music.trackDuration))
                        : 0

                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 6)
                        Capsule().fill(activeFill)
                            .frame(width: max(6, geo.size.width * pct), height: 6)

                        Circle().fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, geo.size.width * pct - 6))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                isDraggingSeek = true
                                let fraction = max(0, min(1, val.location.x / geo.size.width))
                                seekPreview = fraction * music.trackDuration
                            }
                            .onEnded { val in
                                let fraction = max(0, min(1, val.location.x / geo.size.width))
                                music.seek(to: fraction * music.trackDuration)
                                isDraggingSeek = false
                            }
                    )
                }
                .frame(height: 12)

                HStack {
                    Text(music.formatTime(isDraggingSeek ? seekPreview : music.trackPosition))
                    Spacer()
                    let rem = music.trackDuration - (isDraggingSeek ? seekPreview : music.trackPosition)
                    Text(rem > 0 ? "-\(music.formatTime(rem))" : "")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Fixed layout for buttons so they don't move around
            ZStack {
                // Left-aligned accessories
                HStack {
                    accessoryButton(type: leftAccessory)
                    Spacer()
                }

                // Center-aligned main controls
                HStack(spacing: 28) {
                    IconButton(icon: "backward.fill", size: 22) {
                        music.previousTrack()
                    }

                    Button {
                        togglePlayWithAnimation()
                    } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.15)).frame(width: 44, height: 44)
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .scaleEffect(iconScale)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(TapGesture().onEnded { togglePlayWithAnimation() })

                    IconButton(icon: "forward.fill", size: 22) {
                        music.nextTrack()
                    }
                }

                // Right-aligned accessories
                HStack {
                    Spacer()
                    accessoryButton(type: rightAccessory)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func accessoryButton(type: String) -> some View {
        // Shuffle, repeat and like only exist for Spotify and Music
        if music.isGenericSource && type != "devices" {
            EmptyView()
        } else {
            accessoryContent(type: type)
        }
    }

    @ViewBuilder
    private func accessoryContent(type: String) -> some View {
        switch type {
        case "shuffle":
            IconButton(icon: "shuffle", size: 15, opacity: music.isShuffleEnabled ? 1.0 : 0.5, color: music.isShuffleEnabled ? .green : .white) {
                music.toggleShuffle()
                music.isShuffleEnabled.toggle()
            }
        case "repeat":
            IconButton(icon: "repeat", size: 15, opacity: music.isRepeatEnabled ? 1.0 : 0.5, color: music.isRepeatEnabled ? .green : .white) {
                music.toggleRepeat()
                music.isRepeatEnabled.toggle()
            }
        case "like":
            if music.activePlayer == "Spotify" && !spotify.isConnected {
                // Likes on Spotify go through the Web API: connect first
                AuthorizeButton(title: "Connect") {
                    if !spotify.clientID.isEmpty { spotify.connect() }
                }
            } else {
                let isLiked = music.isLiked
                IconButton(icon: isLiked ? "heart.fill" : "heart", size: 15, opacity: isLiked ? 1.0 : 0.5, color: isLiked ? .green : .white) {
                    music.toggleLike()
                    music.isLiked.toggle()
                }
            }
        case "devices":
            IconButton(icon: "airplayaudio", size: 15, opacity: 0.5, color: .white) { music.toggleAirPlay() }
        default:
            EmptyView()
        }
    }
    private func openActivePlayer() {
        let bundleID = music.activeBundleID
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    private func togglePlayWithAnimation() {
        music.playPause()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            iconScale = 0.7
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                iconScale = 1.0
            }
        }
    }
}

// MARK: - Waveform

/// The animated bars. They are Core Animation layers, so the animation runs in the system's render server:
/// the app does no work per frame. (A SwiftUI version that re-randomized the heights every 0.28 s stacked a new
/// animation on top of the previous ones, and the CPU use grew the longer the music played.)
struct WaveformView: NSViewRepresentable {
    let isPlaying: Bool
    /// One color, or two for a gradient from top-left to bottom-right
    var colors: [Color]

    init(isPlaying: Bool, color: Color) {
        self.isPlaying = isPlaying
        self.colors = [color]
    }

    /// For the styles the Now Playing view builds: a plain color, or the spectrogram gradient
    init(isPlaying: Bool, primary: Color, gradient: Bool) {
        self.isPlaying = isPlaying
        self.colors = gradient ? [primary, Self.opposing(of: primary)] : [primary]
    }

    func makeNSView(context: Context) -> WaveformLayerView { WaveformLayerView() }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.update(colors: colors.map { NSColor($0).cgColor }, playing: isPlaying)
    }

    /// Same hue shift as `Color.spectrogramGradient()`
    private static func opposing(of color: Color) -> Color {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
        ns.getHue(&h, saturation: &sat, brightness: &br, alpha: &al)
        return Color(hue: Double(fmod(h + 0.5, 1.0)), saturation: Double(sat), brightness: Double(br), opacity: Double(al))
    }
}

final class WaveformLayerView: NSView {
    private let gradient = CAGradientLayer()
    private let mask = CALayer()
    private var bars: [CALayer] = []
    private var isAnimating = false

    private static let barCount = 7
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 2
    private static let maxHeight: CGFloat = 14
    private static let minScale: CGFloat = 0.28
    /// Different speeds and phases so the bars don't move in step
    private static let durations: [CFTimeInterval] = [0.42, 0.31, 0.5, 0.36, 0.46, 0.34, 0.4]

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 16) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        gradient.mask = mask
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = 1.5
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)   // grow from the bottom
            bar.transform = CATransform3DMakeScale(1, Self.minScale, 1)
            mask.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        mask.frame = bounds
        // Bars are centered, as the SwiftUI HStack was
        let total = CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.spacing
        let x0 = (bounds.width - total) / 2
        let y0 = (bounds.height - Self.maxHeight) / 2
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.maxHeight)
            bar.position = CGPoint(x: x0 + CGFloat(i) * (Self.barWidth + Self.spacing) + Self.barWidth / 2, y: y0)
        }
        CATransaction.commit()
    }

    func update(colors: [CGColor], playing: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.count > 1 ? colors : [colors.first ?? NSColor.white.cgColor, colors.first ?? NSColor.white.cgColor]
        CATransaction.commit()
        guard playing != isAnimating else { return }
        isAnimating = playing
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "wave")
            guard playing else {
                bar.transform = CATransform3DMakeScale(1, Self.minScale, 1)
                continue
            }
            let wave = CABasicAnimation(keyPath: "transform.scale.y")
            wave.fromValue = Self.minScale
            wave.toValue = 1.0
            wave.duration = Self.durations[i]
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.timeOffset = Double(i) * 0.07
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(wave, forKey: "wave")
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon:    String
    let size:    CGFloat
    var opacity: Double = 1.0
    var color:   Color  = .white
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color.opacity(opacity))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Notch View

struct CalendarNotchView: View {
    @EnvironmentObject var calMgr: CalendarManager
    @ObservedObject private var permissions = PermissionsManager.shared
    @AppStorage("calDisplayMode") private var displayMode = 0

    private var cal:   Calendar { .current }
    private var today: Date     { Date() }

    private var dayName: String  { format("EEEE").uppercased() } // Full day name
    private var dayNum:  String  { format("d") }
    private var monthName: String { format("MMMM yyyy").uppercased() } // Full month year

    private func format(_ f: String) -> String {
        let df = DateFormatter(); df.dateFormat = f; return df.string(from: today)
    }

    private var monthGrid: [[String]] {
        var c = cal.dateComponents([.year, .month], from: today); c.day = 1
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        var wd = cal.component(.weekday, from: first) - 2
        if wd < 0 { wd += 7 }
        var flat = Array(repeating: "", count: wd) + (1...range.count).map { "\($0)" }
        while flat.count % 7 != 0 { flat.append("") }
        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<min($0+7, flat.count)]) }
    }

    private let wds = ["M","T","W","T","F","S","S"]

    var body: some View {
        if displayMode == 1 { singleDayBody } else { monthBody }
    }

    // MARK: Single day: weekday on the left, the day's events on the right

    private var singleDayBody: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.red)
                Text(dayNum)
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(.white)
                    .padding(.top, -8)
                Text(monthName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .frame(width: 150, alignment: .leading)
            .padding(.leading, 32)
            .padding(.top, 16)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 18)

            dayEvents
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.trailing, 28)
                .padding(.top, 20)
                .padding(.bottom, 14)
        }
    }

    private let maxRows = 4

    @ViewBuilder
    private var dayEvents: some View {
        if !calMgr.hasAccess {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar access needed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                AuthorizeButton(title: permissions.calendar == .denied ? "Open Settings" : "Authorize Calendar") {
                    permissions.requestCalendar()
                }
            }
        } else {
            let events = calMgr.todayEvents
            let reminders = calMgr.showsReminders && calMgr.hasRemindersAccess ? calMgr.todayReminders : []
            let askReminders = calMgr.showsReminders && !calMgr.hasRemindersAccess
            let rows = askReminders ? maxRows - 1 : maxRows
            let shownEvents = Array(events.prefix(rows))
            let shownReminders = Array(reminders.prefix(max(0, rows - shownEvents.count)))
            let hidden = events.count + reminders.count - shownEvents.count - shownReminders.count
            if events.isEmpty && reminders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No events today")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Your schedule is clear")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    if askReminders { remindersButton }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shownEvents, id: \.eventIdentifier) { eventRow($0) }
                    ForEach(shownReminders, id: \.calendarItemIdentifier) { reminderRow($0) }
                    if hidden > 0 {
                        Text("+\(hidden) more")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if askReminders { remindersButton }
                }
            }
        }
    }

    private var remindersButton: some View {
        AuthorizeButton(title: permissions.reminders == .denied ? "Reminders: Open Settings" : "Authorize Reminders") {
            permissions.requestReminders()
        }
    }

    private func reminderRow(_ reminder: EKReminder) -> some View {
        let overdue = calMgr.isOverdue(reminder)
        return HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation { calMgr.complete(reminder) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(overdue ? Color.red : Color.orange)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(calMgr.dueTime(of: reminder) ?? (overdue ? "Overdue" : "Reminder"))
                    .font(.system(size: 11))
                    .foregroundStyle(overdue ? Color.red.opacity(0.9) : Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        let finished = !event.isAllDay && event.endDate < Date()
        return HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .red))
                .frame(width: 3)
                .cornerRadius(1.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(event.isAllDay ? "All day"
                     : "\(calMgr.formatTime(event.startDate)) - \(calMgr.formatTime(event.endDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !finished, let meeting = MeetingLink.find(in: event) {
                // Green from a few minutes before the start until the end
                let soon = event.startDate.timeIntervalSinceNow < 10 * 60
                Button { NSWorkspace.shared.open(meeting.url) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill").font(.system(size: 9, weight: .bold))
                        Text("Join").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(soon ? Color.black : Color.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(soon ? Color.green : Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Join the \(meeting.service) meeting")
            }
        }
        .opacity(finished ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { calMgr.openCalendar(at: event.startDate) }
    }

    // MARK: Month grid

    private var monthBody: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.red)
                Text(dayNum)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
                    .padding(.top, -8)
                    .padding(.bottom, 4)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    if let event = calMgr.upcomingEvent {
                        HStack(alignment: .top, spacing: 6) {
                            Rectangle()
                                .fill(Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .red))
                                .frame(width: 3)
                                .cornerRadius(1.5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let location = event.location, !location.isEmpty {
                                    Text(location)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }

                                Text("\(calMgr.formatTime(event.startDate)) - \(calMgr.formatTime(event.endDate))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            calMgr.openCalendar(at: event.startDate)
                        }
                    } else if calMgr.hasAccess {
                        if let first = calMgr.showsReminders && calMgr.hasRemindersAccess ? calMgr.todayReminders.first : nil {
                            reminderRow(first)
                        } else {
                            Text("No events today")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                            Text("Your schedule is clear")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        Text("Calendar access needed")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                        AuthorizeButton(title: permissions.calendar == .denied ? "Open Settings" : "Authorize") {
                            permissions.requestCalendar()
                        }
                    }
                    if calMgr.hasAccess, calMgr.showsReminders {
                        if calMgr.hasRemindersAccess {
                            let extra = calMgr.todayReminders.count - (calMgr.upcomingEvent == nil ? 1 : 0)
                            if extra > 0 {
                                Text("\(extra) reminder\(extra == 1 ? "" : "s") today")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.orange.opacity(0.9))
                            }
                        } else {
                            remindersButton
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.leading, 32)
            .padding(.top, 16)

            Group {
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(monthName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)

                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(wds[i])
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(i >= 5 ? .white.opacity(0.3) : .white.opacity(0.5))
                                .frame(width: 22, alignment: .center)
                        }
                    }
                    .padding(.bottom, 2)

                    ForEach(0..<monthGrid.count, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { col in
                                let t = monthGrid[row][col]
                                ZStack {
                                    if t == dayNum { Circle().fill(Color.red).frame(width: 20, height: 20) }
                                    Text(t)
                                        .font(.system(size: 11, weight: t == dayNum ? .bold : .medium))
                                        .foregroundStyle(t.isEmpty ? .clear : t == dayNum ? .white : .white.opacity(0.6))
                                }
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !t.isEmpty, let d = Int(t) {
                                        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
                                        comps.day = d
                                        if let target = Calendar.current.date(from: comps) {
                                            calMgr.openCalendar(at: target)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 28)
                .padding(.top, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: "ical://") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
// MARK: - Control Center

/// Plugin buttons. Tapping one opens its options (the plugin's declarative menu) right inside the notch.
struct ControlCenterNotchView: View {
    @ObservedObject private var pluginManager = PluginManager.shared
    @State private var selectedID: String?
    /// Bumped after every tap so the plugin's new state shows at once, not at the next one-second refresh
    @State private var refresh = 0

    private let tileColumns = [GridItem(.adaptive(minimum: 64, maximum: 84), spacing: 14, alignment: .top)]
    private let optionColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        // Re-read plugin state every second (countdowns, active state)
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Group {
                let _ = refresh
                if let id = selectedID,
                   let plugin = pluginManager.loadedPlugins.first(where: { $0.pluginIdentifier == id }) {
                    detail(plugin)
                } else {
                    overview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control Center")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.top, 14)

            if pluginManager.buttonPlugins.isEmpty {
                VStack(spacing: 3) {
                    Spacer()
                    Text("No plugins installed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Get plugins from Settings → Control Center")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: tileColumns, alignment: .center, spacing: 14) {
                        ForEach(pluginManager.buttonPlugins, id: \.pluginIdentifier) { plugin in
                            tile(plugin)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    /// Every button is built the same: a 48 pt circle (symbol or a short text in the same font size for all)
    /// and the plugin's name, one line, same font. Anything more (state, countdowns) goes in the options.
    private static func activeColor(for id: String) -> Color {
        switch id {
        case "scrolly": return Color(hex: "#0A84FF") ?? .blue
        case "tomato":  return Color(hex: "#FF453A") ?? .red
        case "dusty":   return Color(hex: "#64D2FF") ?? .cyan
        case "closeme": return Color(hex: "#BF5AF2") ?? .purple
        default:        return Color(hex: "#FF9F0A") ?? .orange     // Espresso and anything else
        }
    }

    private func tile(_ plugin: NotcholinoPlugin) -> some View {
        let active = plugin.isActive
        let label = plugin.controlCenterLabel ?? ""
        // The plugin's own color when it gives one, else the color this plugin is known by
        let tint = Color(hex: plugin.controlCenterTintColor ?? "")
            ?? (active ? Self.activeColor(for: plugin.pluginIdentifier) : nil)
        let showsText = !label.isEmpty
        return Button {
            if plugin.responds(to: Selector(("controlCenterButtonTapped"))) {
                // A simple switch: no options to open
                plugin.controlCenterButtonTapped?()
                refreshSoon()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedID = plugin.pluginIdentifier }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // A reading (a temperature, a percentage) is its color on a dark tint of it; a switch is filled
                    Circle()
                        .fill(tint.map { showsText ? $0.opacity(0.2) : $0 } ?? Color.white.opacity(0.12))
                        .frame(width: 48, height: 48)
                    if showsText {
                        Text(label)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(tint ?? .white)
                            .frame(width: 44)
                    } else {
                        Image(systemName: plugin.controlCenterIcon.isEmpty ? "puzzlepiece.extension.fill" : plugin.controlCenterIcon)
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                Text(plugin.pluginName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { refresh += 1 }
    }

    // MARK: Plugin options

    private func detail(_ plugin: NotcholinoPlugin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedID = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let label = plugin.controlCenterLabel, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: plugin.controlCenterTintColor ?? "") ?? .white)
                } else {
                    Image(systemName: plugin.controlCenterIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(plugin.isActive ? .orange : .white)
                }
                Text(plugin.pluginName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if !plugin.statusText.isEmpty {
                    Text(plugin.statusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: plugin.controlCenterTintColor ?? "") ?? .orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(groups(of: plugin.menuItems()).enumerated()), id: \.offset) { _, group in
                        if let header = group.header {
                            Text(header)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        if let graph = group.graph {
                            SparklineView(values: graph.values, caption: graph.caption, color: graph.color)
                        }
                        ForEach(group.steppers, id: \.id) { stepper in
                            StepperRow(label: stepper.label, value: stepper.value, unit: stepper.unit,
                                       range: stepper.min...stepper.max, step: stepper.step) { newValue in
                                plugin.performMenuAction("\(stepper.id)=\(newValue)")
                                refreshSoon()
                            }
                        }
                        ForEach(Array(group.infos.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.label)
                                    .foregroundStyle(.white.opacity(0.55))
                                Spacer()
                                Text(row.value)
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        // Wide options take a whole row (for text that doesn't fit in a small chip)
                        ForEach(group.items.filter { $0.wide }, id: \.id) { item in
                            optionChip(item) { plugin.performMenuAction(item.id); refreshSoon() }
                        }
                        LazyVGrid(columns: optionColumns, spacing: 6) {
                            ForEach(group.items.filter { !$0.wide }, id: \.id) { item in
                                optionChip(item) { plugin.performMenuAction(item.id); refreshSoon() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private struct Option { let id: String; let title: String; let checked: Bool; let destructive: Bool; var wide = false }
    private struct Graph { var values: [Double]; var caption: String; var color: Color }
    private struct InfoRow { let label: String; let value: String }
    private struct StepperItem { let id: String; let label: String; let value: Int; let unit: String; let min: Int; let max: Int; let step: Int }
    private struct OptionGroup {
        var header: String?; var items: [Option]; var graph: Graph? = nil
        var infos: [InfoRow] = []; var steppers: [StepperItem] = []
    }

    /// Turns the plugin's menu dictionaries into groups (a header starts a new group)
    private func groups(of raw: [[String: Any]]) -> [OptionGroup] {
        var result: [OptionGroup] = [OptionGroup(header: nil, items: [])]
        for entry in raw {
            if let label = entry["stepper"] as? String, let id = entry["id"] as? String {
                // Number rows, like the read-only ones, come before any chips of their group
                if !result[result.count - 1].items.isEmpty || result[result.count - 1].graph != nil {
                    result.append(OptionGroup(header: nil, items: []))
                }
                let lo = entry["min"] as? Int ?? 0
                result[result.count - 1].steppers.append(StepperItem(
                    id: id, label: label, value: entry["value"] as? Int ?? lo, unit: entry["unit"] as? String ?? "",
                    min: lo, max: max(lo, entry["max"] as? Int ?? 999), step: max(1, entry["step"] as? Int ?? 1)))
            } else if let label = entry["info"] as? String {
                // Rows of "label  value" (consecutive ones share a group; chips come after them)
                if !result[result.count - 1].items.isEmpty || result[result.count - 1].graph != nil {
                    result.append(OptionGroup(header: nil, items: []))
                }
                result[result.count - 1].infos.append(InfoRow(label: label, value: entry["value"] as? String ?? ""))
            } else if let values = entry["graph"] as? [Double] {
                let color = Color(hex: entry["color"] as? String ?? "") ?? .white
                result.append(OptionGroup(header: nil, items: [],
                                          graph: Graph(values: values, caption: entry["caption"] as? String ?? "", color: color)))
                result.append(OptionGroup(header: nil, items: []))
            } else if let header = entry["header"] as? String {
                result.append(OptionGroup(header: header, items: []))
            } else if let id = entry["id"] as? String, let title = entry["title"] as? String {
                result[result.count - 1].items.append(Option(
                    id: id, title: title,
                    checked: entry["checked"] as? Bool ?? false,
                    destructive: entry["destructive"] as? Bool ?? false,
                    wide: entry["wide"] as? Bool ?? false))
            }
        }
        return result.filter { !$0.items.isEmpty || $0.graph != nil || !$0.infos.isEmpty || !$0.steppers.isEmpty }
    }

    private func optionChip(_ item: Option, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(item.checked ? Color.black : (item.destructive ? Color.red : Color.white))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    Capsule().fill(item.checked ? Color.white
                                   : (item.destructive ? Color.red.opacity(0.18) : Color.white.opacity(0.12)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Number rows for plugins

/// "Label   (−) 25 min (+)". A tap changes the number by one step, holding repeats.
private struct StepperRow: View {
    let label: String
    let value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    @State private var current: Int

    init(label: String, value: Int, unit: String, range: ClosedRange<Int>, step: Int, onChange: @escaping (Int) -> Void) {
        self.label = label; self.value = value; self.unit = unit; self.range = range; self.step = step; self.onChange = onChange
        _current = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            HoldButton(symbol: "minus", enabled: current > range.lowerBound) { move(-step) }
            Text(unit.isEmpty ? "\(current)" : "\(current) \(unit)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 66)
            HoldButton(symbol: "plus", enabled: current < range.upperBound) { move(step) }
        }
        .onChange(of: value) { current = $0 }
    }

    private func move(_ delta: Int) {
        let next = min(max(current + delta, range.lowerBound), range.upperBound)
        guard next != current else { return }
        current = next
        onChange(next)
    }
}

/// A round button that acts once when pressed and keeps acting, faster and faster, while it is held
private struct HoldButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var task: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard task == nil, enabled else { return }
                    task = Task {
                        action()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        var delay: UInt64 = 110_000_000
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(nanoseconds: delay)
                            delay = max(40_000_000, delay - 6_000_000)
                        }
                    }
                }
                .onEnded { _ in task?.cancel(); task = nil })
            .onDisappear { task?.cancel(); task = nil }
    }
}

// MARK: - Small shared views

/// A compact line graph for plugins (the `"graph"` menu element)
struct SparklineView: View {
    let values: [Double]
    let caption: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let pts = points(in: geo.size)
                ZStack {
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: pts[0])
                            pts.dropFirst().forEach { p.addLine(to: $0) }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 38)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        // Never zoom into noise: keep at least 6 units of range
        let span = max(hi - lo, 6)
        let mid = (hi + lo) / 2
        let bottom = mid - span / 2
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: size.height * (1 - CGFloat((v - bottom) / span)))
        }
    }
}

extension Color {
    /// "#RRGGBB" (or "RRGGBB"); nil when the text isn't a color
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}


/// A small symbol beside the closed notch
struct SideIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
    }
}
