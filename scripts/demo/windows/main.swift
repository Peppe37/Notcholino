// SPDX-License-Identifier: GPL-3.0-only
// Two plain windows for the demo video's Snap scene, shown above the stage (which covers the screen) and below the notch.
//
//   swiftc -o /tmp/demowin scripts/demo/windows/main.swift && /tmp/demowin
//
// It writes the windows' frames to /tmp/demowin-frames.txt twice a second, so the script can check where Snap put them.
import AppKit

let screen = NSScreen.screens[0]
let sh = screen.frame.height

final class Page: NSView {
    let tint: NSColor, title: String, lines: [String]
    init(frame: NSRect, tint: NSColor, title: String, lines: [String]) { self.tint = tint; self.title = title; self.lines = lines; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.97, alpha: 1).setFill(); bounds.fill()
        tint.withAlphaComponent(0.18).setFill()
        NSRect(x: 0, y: bounds.height - 96, width: bounds.width, height: 96).fill()
        let t = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor(white: 0.12, alpha: 1)])
        t.draw(at: NSPoint(x: 28, y: bounds.height - 66))
        for (i, line) in lines.enumerated() {
            let y = bounds.height - 140 - CGFloat(i) * 38
            tint.setFill(); NSBezierPath(ovalIn: NSRect(x: 30, y: y + 7, width: 9, height: 9)).fill()
            NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor(white: 0.22, alpha: 1)]).draw(at: NSPoint(x: 52, y: y))
        }
    }
}

func makeWindow(_ title: String, _ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat, _ tint: NSColor, _ lines: [String]) -> NSWindow {
    let win = NSWindow(contentRect: NSRect(x: x, y: sh - yTop - h, width: w, height: h), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    win.title = title
    win.level = NSWindow.Level(rawValue: 470)         // above the stage (450), below the notch's drop catcher and the notch
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    win.contentView = Page(frame: NSRect(x: 0, y: 0, width: w, height: h), tint: tint, title: title, lines: lines)
    win.hidesOnDeactivate = false
    win.orderFrontRegardless()
    return win
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let a = makeWindow("Notes", 210, 470, 560, 380, NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1),
                   ["Ship the new preview video", "Reply to Anna about the demo", "Book the train to Milan", "Try Snap on a real project"])
let b = makeWindow("Mockups", 780, 500, 560, 380, NSColor(red: 0.2, green: 0.5, blue: 1, alpha: 1),
                   ["Home screen: final colors", "Settings: simpler tabs", "Icon set for the store", "Dark mode pass"])
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let text = [a, b].map { "\($0.title) \(Int($0.frame.origin.x)) \(Int(sh - $0.frame.maxY)) \(Int($0.frame.width)) \(Int($0.frame.height))" }.joined(separator: "\n")
    try? text.write(toFile: "/tmp/demowin-frames.txt", atomically: true, encoding: .utf8)
}
app.run()
