// SPDX-License-Identifier: GPL-3.0-only
// Moves the mouse like a hand would, for the demo video: smooth, with easing.
//
//   mouse move X Y [seconds]              glide to a point (screen points, origin top left)
//   mouse click                           click where the pointer is
//   mouse drag X1 Y1 X2 Y2 [seconds] [hold]   press at the first point, drag to the second, wait `hold` seconds, release
//   mouse scroll DY                       scroll wheel by DY lines
import CoreGraphics
import Foundation

let a = CommandLine.arguments
func num(_ i: Int, _ d: Double) -> Double { a.count > i ? (Double(a[i]) ?? d) : d }
func here() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func glide(to target: CGPoint, seconds: Double, type: CGEventType) {
    let start = here(), steps = max(2, Int(seconds * 120))
    for i in 1...steps {
        let t = ease(Double(i) / Double(steps))
        post(type, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
        usleep(UInt32(1_000_000.0 / 120.0))
    }
}

switch a.count > 1 ? a[1] : "" {
case "move": glide(to: CGPoint(x: num(2, 0), y: num(3, 0)), seconds: num(4, 0.8), type: .mouseMoved)
case "click":
    post(.leftMouseDown, here()); usleep(70_000); post(.leftMouseUp, here())
case "drag":
    glide(to: CGPoint(x: num(2, 0), y: num(3, 0)), seconds: 0.5, type: .mouseMoved)
    usleep(250_000)
    post(.leftMouseDown, here()); usleep(150_000)
    glide(to: CGPoint(x: num(4, 0), y: num(5, 0)), seconds: num(6, 1.2), type: .leftMouseDragged)
    // a little jitter while holding, like a real hand: the system picks the window under a drag at each movement
    let hold = num(7, 1.0), end = here(); var t = 0.0, k = 0.0
    while t < hold { post(.leftMouseDragged, CGPoint(x: end.x + sin(k) * 2, y: end.y + cos(k) * 1.5)); k += 0.7; usleep(50_000); t += 0.05 }
    post(.leftMouseUp, here())
case "scroll":
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(num(2, -3)), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
default:
    print("usage: mouse move X Y [s] | click | drag X1 Y1 X2 Y2 [s] [hold] | scroll DY")
}
