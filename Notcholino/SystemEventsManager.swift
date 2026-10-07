import Foundation
import AppKit
import SwiftUI
import CoreAudio
import AudioToolbox



// MARK: - Notch Display Mode

enum NotchMode: Equatable {
    case music
    case calendar
    case volume(Float)
    case brightness(Float)
    case mediaKey(MediaKeyKind)
    case micMute(Bool)

    enum MediaKeyKind: Equatable { case play, pause, next, previous }
}

// MARK: - System Events Manager

final class SystemEventsManager: ObservableObject {

    @Published var currentMode:  NotchMode = .music
    @Published var systemVolume: Float     = 0.5
    @Published var brightness:   Float     = 0.5
    @Published var micMuted:     Bool      = false

    private var globalMonitor: Any?
    private var hudTimer:      Timer?

    init() {
        systemVolume = readVolume()
        brightness = readBrightness()
        setupGlobalMonitor()
        
        // Suppress native OSD if our HUDs are enabled
        let soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        let displayEnabled = UserDefaults.standard.object(forKey: "displayEnabled") as? Bool ?? true
        if soundEnabled || displayEnabled {
            OSDManager.shared.startSuppressing()
        }
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        hudTimer?.invalidate()
    }

    // MARK: - Global key monitor

    private func setupGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self, event.subtype.rawValue == 8 else { return }
            let data     = Int(event.data1)
            let keyCode  = (data & 0xFFFF0000) >> 16
            let keyFlags = data & 0x0000FFFF
            let keyDown  = ((keyFlags & 0xFF00) >> 8) == 0x0A
            guard keyDown else { return }

            DispatchQueue.main.async {
                switch keyCode {
                case 0, 1, 7: // volume up, down, mute
                    let soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
                    if soundEnabled {
                        self.showHUD(.volume(self.systemVolume)) // show immediately for responsiveness
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let vol = self.readVolume()
                        self.systemVolume = vol
                        if soundEnabled { self.currentMode = .volume(vol) }
                    }
                    
                case 2, 3: // brightness up, down
                    let displayEnabled = UserDefaults.standard.object(forKey: "displayEnabled") as? Bool ?? true
                    if displayEnabled {
                        self.showHUD(.brightness(self.brightness))
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let br = self.readBrightness()
                        self.brightness = br
                        if displayEnabled { self.currentMode = .brightness(br) }
                    }
                default: break
                }
            }
        }
    }

    // MARK: - HUD management

    func showHUD(_ mode: NotchMode) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.currentMode = mode
            }
            self.hudTimer?.invalidate()
            self.hudTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self?.currentMode = .music
                }
            }
        }
    }

    // MARK: - Volume reading (CoreAudio)

    func readVolume() -> Float {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID)

        var vol: Float32 = 0
        propSize = UInt32(MemoryLayout<Float32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &propSize, &vol)
        return status == noErr ? vol : 0.5
    }

    // MARK: - Brightness reading (DisplayServices)

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        return dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    }()
    
    private static let getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesGetLinearBrightness") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    }()

    func readBrightness() -> Float {
        var b: Float = 0.5
        if let f = Self.getBrightnessFunc {
            f(CGMainDisplayID(), &b)
        }
        return b
    }
}
