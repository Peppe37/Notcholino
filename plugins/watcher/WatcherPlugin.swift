import AppKit
import CoreAudio
import CoreMediaIO
import Foundation

/// Watcher tells you when the microphone or the camera is in use: an icon beside the closed notch while it lasts, and a
/// small popup when it starts (with the apps recording, when macOS says which).
///
/// It has no button in the Control Center: it only shows icons and popups. It never records or reads anything from either.
@objc(WatcherPlugin)
final class WatcherPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "watcher" }
    var pluginName: String { "Watcher" }
    var pluginVersion: String {
        Bundle(for: WatcherPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "An icon beside the notch while the microphone or the camera is in use, and a popup when it starts." }

    // MARK: No button

    var controlCenterHidden: Bool { true }
    var controlCenterIcon: String { "eye" }
    var isActive: Bool { micOn || cameraOn }
    var statusText: String { "" }
    func menuItems() -> [[String: Any]] { [] }
    func performMenuAction(_ id: String) {}

    // MARK: State

    private var popup: (([String: Any]) -> Void)?
    private var micOn = false
    private var cameraOn = false
    private var primed = false

    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }

    /// The app reads this once a second, which is also when a change is noticed
    var notchSideIcon: String {
        update()
        if cameraOn { return "video.fill" }
        return micOn ? "mic.fill" : ""
    }

    var notchSideIconColor: String { cameraOn ? "#30D158" : "#FF9F0A" }

    private func update() {
        let mic = Self.microphoneIsRunning()
        let camera = Self.cameraIsRunning()
        defer { micOn = mic; cameraOn = camera; primed = true }
        // The first reading only sets the starting point
        guard primed else { return }
        if camera && !cameraOn {
            popup?(["title": "Camera in use", "icon": "video.fill", "color": "#30D158", "seconds": 4.0])
        }
        if mic && !micOn {
            let apps = Self.appsRecording()
            popup?(["title": "Microphone in use", "subtitle": apps.isEmpty ? "" : apps.joined(separator: ", "),
                    "icon": "mic.fill", "color": "#FF9F0A", "seconds": 4.0])
        }
    }

    // MARK: Microphone

    private static func microphoneIsRunning() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    /// Names of the apps that are recording (macOS 14.2 and later list them)
    private static func appsRecording() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return [] }
        var names: [String] = []
        for object in objects {
            var input: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &a, 0, nil, &s, &input) == noErr, input != 0 else { continue }
            var pid: pid_t = 0
            s = UInt32(MemoryLayout<pid_t>.size)
            a.mSelector = kAudioProcessPropertyPID
            guard AudioObjectGetPropertyData(object, &a, 0, nil, &s, &pid) == noErr,
                  let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    // MARK: Camera

    private static func cameraIsRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }
        for device in devices {
            var running: UInt32 = 0
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == noErr, running != 0 { return true }
        }
        return false
    }
}
