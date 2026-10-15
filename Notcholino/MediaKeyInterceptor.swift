// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import CoreAudio

extension Notification.Name {
    /// Posted after a volume key press was handled by Notcholino. `object` is the level (0 when muted).
    static let mediaKeyVolume = Notification.Name("notcholinoMediaKeyVolume")
    /// Posted after a brightness key press was handled by Notcholino. `object` is the level.
    static let mediaKeyBrightness = Notification.Name("notcholinoMediaKeyBrightness")
}

/// Takes over the volume and brightness keys so macOS never shows its own HUD.
///
/// On macOS 26 that HUD is a Control Center window, which can't be stopped without freezing the menu bar,
/// so the only way to hide it is to handle the keys ourselves: we change the volume or brightness and show it in the notch.
/// This needs the Accessibility permission. Whenever a key can't be handled (no permission, an output device
/// without software volume, no built-in display...) it is passed to the system untouched.
final class MediaKeyInterceptor: ObservableObject {
    static let shared = MediaKeyInterceptor()

    /// True while the keys are being intercepted
    @Published private(set) var isActive = false
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var didPrompt = false
    private let step: Float = 1.0 / 16.0

    /// Starts intercepting, asking for the Accessibility permission if needed and waiting for it to be granted
    func start() {
        guard tap == nil, retryTimer == nil else { return }
        if installTap() { return }
        if !didPrompt {
            didPrompt = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.installTap() {
                timer.invalidate()
                self.retryTimer = nil
            }
        }
    }

    /// Asks the system for the Accessibility permission now (the dialog with the "Open System Settings" button),
    /// and keeps checking until it is granted
    func askForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        start()
    }

    private func installTap() -> Bool {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else { return false }
        let systemDefined: CGEventMask = 1 << 14   // NX_SYSDEFINED: media keys
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined, callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isActive = true
        // Nothing left for the older "suspend the system HUD helper" trick to do
        OSDManager.shared.stopSuppressing()
        return true
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return passThrough
        }
        let data = Int(nsEvent.data1)
        let keyCode = (data & 0xFFFF0000) >> 16
        let isDown = (((data & 0xFFFF) & 0xFF00) >> 8) == 0x0A
        // Shift + Option gives quarter steps, like macOS
        let stepSize = nsEvent.modifierFlags.isSuperset(of: [.shift, .option]) ? step / 4 : step
        let defaults = UserDefaults.standard

        switch keyCode {
        case 0, 1, 7:   // volume up, volume down, mute
            guard defaults.object(forKey: "soundEnabled") as? Bool ?? true,
                  let audio = AudioOutput.current(), audio.isControllable else { return passThrough }
            if isDown { changeVolume(keyCode: keyCode, audio: audio, stepSize: stepSize) }
            return nil
        case 2, 3:      // brightness up, brightness down
            guard defaults.object(forKey: "displayEnabled") as? Bool ?? true,
                  BuiltInDisplay.isAvailable else { return passThrough }
            if isDown { changeBrightness(up: keyCode == 2, stepSize: stepSize) }
            return nil
        default:
            return passThrough
        }
    }

    private func changeVolume(keyCode: Int, audio: AudioOutput, stepSize: Float) {
        if keyCode == 7 {
            audio.setMuted(!audio.isMuted)
        } else {
            if audio.isMuted { audio.setMuted(false) }   // the volume keys also unmute
            let delta = keyCode == 0 ? stepSize : -stepSize
            audio.setVolume(min(1, max(0, audio.volume + delta)))
        }
        NotificationCenter.default.post(name: .mediaKeyVolume, object: audio.isMuted ? Float(0) : audio.volume)
    }

    private func changeBrightness(up: Bool, stepSize: Float) {
        guard let current = BuiltInDisplay.level else { return }
        BuiltInDisplay.setLevel(min(1, max(0, current + (up ? stepSize : -stepSize))))
        NotificationCenter.default.post(name: .mediaKeyBrightness, object: BuiltInDisplay.level ?? current)
    }
}

private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handle(type: type, event: event)
}

// MARK: - Output volume (CoreAudio)

private struct AudioOutput {
    let device: AudioDeviceID

    static func current() -> AudioOutput? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return AudioOutput(device: id)
    }

    private func address(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    /// The main volume control if the device has one, otherwise its left and right channels
    private var volumeElements: [AudioObjectPropertyElement] {
        var main = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { element in
            var a = address(kAudioDevicePropertyVolumeScalar, element)
            return AudioObjectHasProperty(device, &a)
        }
    }

    /// False for outputs without software volume (some HDMI/DisplayPort audio): the system keeps the key then
    var isControllable: Bool {
        let elements = volumeElements
        guard !elements.isEmpty else { return false }
        return elements.allSatisfy { element in
            var a = address(kAudioDevicePropertyVolumeScalar, element)
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
        }
    }

    var volume: Float {
        let values: [Float] = volumeElements.compactMap { element in
            var a = address(kAudioDevicePropertyVolumeScalar, element)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    func setVolume(_ value: Float) {
        for element in volumeElements {
            var a = address(kAudioDevicePropertyVolumeScalar, element)
            var v = Float32(value)
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    var isMuted: Bool {
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &muted) == noErr && muted != 0
    }

    func setMuted(_ muted: Bool) {
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &a) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// MARK: - Built-in display brightness (DisplayServices, private framework)

private enum BuiltInDisplay {
    private typealias GetFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFunc: GetFunc? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFunc.self) }
    private static let setFunc: SetFunc? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFunc.self) }

    private static var displayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool { getFunc != nil && setFunc != nil && displayID != nil }

    static var level: Float? {
        guard let id = displayID, let getFunc else { return nil }
        var value: Float = 0
        return getFunc(id, &value) == 0 ? value : nil
    }

    static func setLevel(_ value: Float) {
        guard let id = displayID, let setFunc else { return }
        _ = setFunc(id, value)
    }
}
