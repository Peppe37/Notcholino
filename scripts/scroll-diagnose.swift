// Shows how your scroll events look to macOS and which ones Scrolly would reverse.
// Nothing is changed: it only listens. Needs the Accessibility permission of the app you run it from (Terminal, an IDE).
//
//   swiftc -O -o /tmp/scrolldiag scripts/scroll-diagnose.swift && /tmp/scrolldiag 25
//
// During the 25 seconds scroll with the mouse wheel for about ten seconds, then with the trackpad for ten.
import CoreGraphics
import Foundation

setbuf(stdout, nil)
struct Kind: Hashable { let continuous: Bool; let phase: Int64; let momentum: Int64; let fromApp: Bool }
var counts: [Kind: Int] = [:]

let callback: CGEventTapCallBack = { _, type, e, _ in
    guard type == .scrollWheel else { return Unmanaged.passUnretained(e) }
    let k = Kind(continuous: e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                 phase: e.getIntegerValueField(.scrollWheelEventScrollPhase),
                 momentum: e.getIntegerValueField(.scrollWheelEventMomentumPhase),
                 fromApp: e.getIntegerValueField(.eventSourceUnixProcessID) != 0)
    counts[k, default: 0] += 1
    return Unmanaged.passUnretained(e)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                  eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue, callback: callback, userInfo: nil) else {
    print("Could not listen: allow this app in System Settings > Privacy & Security > Accessibility"); exit(1)
}
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "25") ?? 25
print("Listening for \(Int(seconds)) s: scroll with the mouse wheel, then with the trackpad…")
RunLoop.main.run(until: Date().addingTimeInterval(seconds))

print("\nScroll events seen (Scrolly reverses those with no gesture phase and no momentum):")
for (k, n) in counts.sorted(by: { $0.value > $1.value }) {
    let reverses = k.phase == 0 && k.momentum == 0
    print(String(format: "%5d x  continuous=%@  phase=%lld  momentum=%lld  posted by an app=%@   -> %@",
                 n, k.continuous ? "yes" : "no ", k.phase, k.momentum, k.fromApp ? "yes" : "no ",
                 reverses ? "REVERSED (looks like a mouse)" : "left alone (looks like a trackpad)"))
}
if counts.isEmpty { print("(none: nothing was scrolled)") }
