import AppKit

let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")!
let config = NSWorkspace.OpenConfiguration()
config.activates = true
NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
    if let error = error { print("Error:", error) }
    print("Done")
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
