// Moves the mouse to the top-center of the main display (the notch) or away from it.
// Usage: swift scripts/hover.swift in|out   (or compile it with swiftc)
import CoreGraphics
import Foundation

let bounds = CGDisplayBounds(CGMainDisplayID())
let away = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "out"
let y: CGFloat = away ? bounds.height / 2 : 6
for i in 0..<6 {
    let point = CGPoint(x: bounds.midX + CGFloat(i % 2), y: y)
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
}
