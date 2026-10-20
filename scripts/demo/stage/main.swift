// SPDX-License-Identifier: GPL-3.0-only
// The stage for the demo video: a clean wallpaper that covers the whole screen except the notch window (which sits above it),
// captions, a screenshot thumbnail you can drag, and an end card. Controlled by writing lines to /tmp/stage-cmd.txt:
//
//   caption: Some text      shows a caption (empty text hides it)
//   voice: Some text        a pill with a microphone that types the text out, like what you say to Notchy (voice: hide hides it)
//   notchy: 1.6|The answer  makes Notchy (a debug build with the demo hook) think for 1.6 s and answer with that text
//   thumb: show | hide      the screenshot thumbnail, which the video drags to the notch
//   end: show | hide        the end card
//   quit
//
// Build and run:  swiftc -o /tmp/stage scripts/demo/stage/main.swift && /tmp/stage <image-for-the-thumbnail>
import AppKit

let screen = NSScreen.screens[0]
let sw = screen.frame.width, sh = screen.frame.height

// MARK: Wallpaper

func wallpaper(_ size: NSSize) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        let base = NSGradient(colors: [NSColor(red: 0.04, green: 0.04, blue: 0.12, alpha: 1),
                                       NSColor(red: 0.16, green: 0.10, blue: 0.36, alpha: 1),
                                       NSColor(red: 0.50, green: 0.16, blue: 0.42, alpha: 1)],
                              atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        base.draw(in: rect, angle: -35)
        func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
            NSGradient(colors: [c, c.withAlphaComponent(0)])!.draw(fromCenter: NSPoint(x: x, y: y), radius: 0,
                                                                  toCenter: NSPoint(x: x, y: y), radius: r, options: [])
        }
        glow(rect.width * 0.18, rect.height * 0.85, rect.width * 0.45, NSColor(red: 0.16, green: 0.45, blue: 1, alpha: 0.35))
        glow(rect.width * 0.85, rect.height * 0.15, rect.width * 0.5, NSColor(red: 0.62, green: 0.35, blue: 1, alpha: 0.32))
        return true
    }
}

final class Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) { wallpaper(bounds.size).draw(in: bounds) }
}

let cover = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
cover.level = NSWindow.Level(rawValue: 450)          // above the menu bar and the Dock, below the notch's drop catcher (500) and the notch (1000)
cover.isOpaque = true
cover.hasShadow = false
cover.ignoresMouseEvents = true
cover.hidesOnDeactivate = false
cover.canHide = false
cover.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
cover.contentView = Backdrop(frame: NSRect(origin: .zero, size: screen.frame.size))

// MARK: Overlay: captions, the voice pill and the end card live in their own window, above the demo windows (470) and below the notch

let overlay = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
overlay.level = NSWindow.Level(rawValue: 480)
overlay.isOpaque = false
overlay.backgroundColor = .clear
overlay.hasShadow = false
overlay.ignoresMouseEvents = true
overlay.hidesOnDeactivate = false
overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
overlay.contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

// MARK: Caption

// A dark pill, so it reads over the wallpaper and over a white window alike
let captionBox = NSView(frame: NSRect(x: sw / 2 - 300, y: sh - 400, width: 600, height: 52))
captionBox.wantsLayer = true
captionBox.layer?.cornerRadius = 26
captionBox.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
captionBox.alphaValue = 0
let caption = NSTextField(labelWithString: "")
caption.font = .systemFont(ofSize: 28, weight: .semibold)
caption.textColor = NSColor.white.withAlphaComponent(0.96)
caption.alignment = .center
captionBox.addSubview(caption)
overlay.contentView!.addSubview(captionBox)

func setCaption(_ text: String) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.25
        captionBox.animator().alphaValue = 0
    }, completionHandler: {
        guard !text.isEmpty else { return }
        caption.stringValue = text
        caption.sizeToFit()
        let width = caption.frame.width + 64
        captionBox.frame = NSRect(x: sw / 2 - width / 2, y: sh - 400, width: width, height: 52)
        caption.frame = NSRect(x: 32, y: (52 - caption.frame.height) / 2, width: caption.frame.width, height: caption.frame.height)
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.35; captionBox.animator().alphaValue = 1 }
    })
}

// MARK: What you say to Notchy: a pill with a microphone that types out the sentence

let pill = NSView(frame: NSRect(x: sw / 2 - 420, y: sh * 0.22, width: 840, height: 84))
pill.wantsLayer = true
pill.layer?.cornerRadius = 42
pill.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.78).cgColor
pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
pill.layer?.borderWidth = 1
pill.alphaValue = 0
let mic = NSImageView(frame: NSRect(x: 28, y: 22, width: 40, height: 40))
mic.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 28, weight: .semibold))
mic.contentTintColor = NSColor(red: 1, green: 0.42, blue: 0.38, alpha: 1)
pill.addSubview(mic)
let said = NSTextField(labelWithString: "")
said.font = .systemFont(ofSize: 30, weight: .medium)
said.textColor = .white
said.frame = NSRect(x: 84, y: 22, width: 730, height: 40)
pill.addSubview(said)
overlay.contentView!.addSubview(pill)
var typing: Timer?

func say(_ text: String) {
    typing?.invalidate()
    if text == "hide" {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.4; pill.animator().alphaValue = 0 }
        return
    }
    said.stringValue = ""
    NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; pill.animator().alphaValue = 1 }
    var i = 0
    let chars = Array(text)
    typing = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { t in
        i += 1
        said.stringValue = String(chars.prefix(i))
        if i >= chars.count { t.invalidate() }
    }
}

// MARK: End card

let end = NSView(frame: NSRect(x: sw / 2 - 440, y: sh - 420, width: 880, height: 300))
end.alphaValue = 0
func label(_ text: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, color: NSColor) -> NSTextField {
    let t = NSTextField(labelWithString: text)
    t.font = .systemFont(ofSize: size, weight: weight); t.textColor = color; t.alignment = .center
    t.frame = NSRect(x: 0, y: y, width: 880, height: size * 1.3); return t
}
end.addSubview(label("Notcholino", size: 64, weight: .heavy, y: 190, color: .white))
end.addSubview(label("Free and open source", size: 26, weight: .medium, y: 134, color: NSColor.white.withAlphaComponent(0.85)))
end.addSubview(label("brew install --cask Peppe37/tap/notcholino", size: 21, weight: .regular, y: 82, color: NSColor.white.withAlphaComponent(0.75)))
end.addSubview(label("github.com/Peppe37/Notcholino", size: 21, weight: .semibold, y: 46, color: NSColor(red: 0.55, green: 0.78, blue: 1, alpha: 1)))
overlay.contentView!.addSubview(end)

// MARK: The screenshot thumbnail (what macOS shows after a screenshot), draggable like the real one

final class Thumb: NSView, NSDraggingSource {
    let url: URL
    let image: NSImage
    init(frame: NSRect, url: URL, image: NSImage) { self.url = url; self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 6, dy: 6)
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.5); s.shadowBlurRadius = 12; s.shadowOffset = NSSize(width: 0, height: -3); s.set()
        NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9).addClip()
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    }
    // The stage never becomes the active app, so the first click has to count
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: 0, y: 0, width: 110, height: 70), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
}

final class KeyableWindow: NSWindow { override var canBecomeKey: Bool { true } }
var thumbWindow: NSWindow?
if CommandLine.arguments.count > 1, let image = NSImage(contentsOfFile: CommandLine.arguments[1]) {
    try? FileManager.default.createDirectory(atPath: "/tmp/notcholino-demo-stage", withIntermediateDirectories: true)
    let file = URL(fileURLWithPath: "/tmp/notcholino-demo-stage/Screenshot 2026-10-15 at 10.41.07.png")
    if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { try? png.write(to: file) }
    let frame = NSRect(x: sw / 2 + 215, y: sh - 262, width: 190, height: 122)
    let w = KeyableWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: 460)
    w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    w.contentView = Thumb(frame: NSRect(origin: .zero, size: frame.size), url: file, image: image)
    w.alphaValue = 0
    thumbWindow = w
}

// MARK: Commands

var offset = 0
func poll() {
    guard let data = try? String(contentsOfFile: "/tmp/stage-cmd.txt", encoding: .utf8) else { return }
    let lines = data.split(separator: "\n").map(String.init)   // whole lines only, in order
    guard lines.count > offset else { return }
    for line in lines[offset...] {
        if line.hasPrefix("voice:") { say(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)) }
        else if line.hasPrefix("notchy:") {
            let parts = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces).split(separator: "|", maxSplits: 1).map(String.init)
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.giuseppe.Notcholino.demo"), object: nil,
                userInfo: ["think": Double(parts.first ?? "1.6") ?? 1.6, "reply": parts.count > 1 ? parts[1] : ""], deliverImmediately: true)
        }
        else if line.hasPrefix("caption:") { setCaption(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)) }
        else if line == "thumb: show" {
            thumbWindow?.ignoresMouseEvents = false
            NSApp.activate(ignoringOtherApps: true)
            thumbWindow?.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.4; thumbWindow?.animator().alphaValue = 1 }
        } else if line == "thumb: hide" {
            // Never order the window out: that would hand the focus to another app and let the Mac show through
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; thumbWindow?.animator().alphaValue = 0 }
            thumbWindow?.ignoresMouseEvents = true
        } else if line == "end: show" {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.6; end.animator().alphaValue = 1 }
        } else if line == "end: hide" {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; end.animator().alphaValue = 0 }
        } else if line == "quit" { NSApp.terminate(nil) }
    }
    offset = lines.count
}

try? "".write(toFile: "/tmp/stage-cmd.txt", atomically: true, encoding: .utf8)
let app = NSApplication.shared
app.setActivationPolicy(.regular)   // a dragging session needs a regular, active app
cover.orderFrontRegardless()
overlay.orderFrontRegardless()
Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in poll() }
app.run()
