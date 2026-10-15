// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreBluetooth
import IOBluetooth
import IOKit.ps
import SwiftUI

/// Small popups under the closed notch when something is connected: Bluetooth devices (AirPods, a mouse, a keyboard…),
/// the charger, a disk. Each kind can be switched off in Settings → Devices.
final class DeviceMonitor: NSObject {
    static let shared = DeviceMonitor()

    private var started = false
    private var powerSource: CFRunLoopSource?
    private var onACPower: Bool?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var launched = Date()

    private func enabled(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    private var duration: Double { UserDefaults.standard.object(forKey: "devicePopupSeconds") as? Double ?? 4 }

    func start() {
        guard !started else { return }
        started = true
        launched = Date()
        startPower()
        startDisks()
        refreshBluetooth()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshBluetooth()
        }
    }

    // MARK: Bluetooth access

    /// Where the Bluetooth permission stands, without asking
    static var bluetoothAuthorization: CBManagerAuthorization { CBCentralManager.authorization }
    private static var accessAsker: CBCentralManager?

    /// Shows the system question (or, if it was refused, tells the user where to change it)
    static func requestBluetoothAccess() {
        if bluetoothAuthorization == .notDetermined {
            // Creating a manager is what makes macOS ask; it answers later, on its own
            accessAsker = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts listening for Bluetooth connections, but only once the permission is there: IOBluetooth waits for it on the
    /// calling thread, which would freeze the app if it were asked at launch.
    func refreshBluetooth() {
        guard connectNotification == nil, enabled("devicePopupBluetooth"), Self.bluetoothAuthorization == .allowedAlways else { return }
        startBluetooth()
    }

    // MARK: Charger

    private func startPower() {
        onACPower = Self.isOnACPower()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }
        let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        powerSource = source
    }

    private func powerChanged() {
        let now = Self.isOnACPower()
        defer { onACPower = now }
        guard enabled("devicePopupPower"), let before = onACPower, before != now else { return }
        let level = Self.batteryPercent()
        if now {
            PopupCenter.shared.show(icon: "bolt.fill", title: "Charging", subtitle: level.map { "\($0)%" }, tint: .green, seconds: duration)
        } else {
            PopupCenter.shared.show(icon: "battery.100", title: "On battery", subtitle: level.map { "\($0)%" }, tint: .white, seconds: duration)
        }
    }

    private static func isOnACPower() -> Bool {
        (IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?) == kIOPSACPowerValue
    }

    private static func batteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            if let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let level = d[kIOPSCurrentCapacityKey] as? Int { return level }
        }
        return nil
    }

    // MARK: Disks

    private func startDisks() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] n in self?.disk(n, mounted: true) }
        center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] n in self?.disk(n, mounted: false) }
    }

    private func disk(_ n: Notification, mounted: Bool) {
        guard enabled("devicePopupDisks"), Date().timeIntervalSince(launched) > 5,
              let url = n.userInfo?["NSWorkspaceVolumeURLKey"] as? URL else { return }
        let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsLocalKey, .volumeNameKey])
        // Only drives you plug in: not the Mac's own volumes, disk images or network shares
        guard values?.volumeIsInternal == false, values?.volumeIsLocal == true, !url.path.hasPrefix("/System") else { return }
        let name = values?.volumeName ?? url.lastPathComponent
        PopupCenter.shared.show(icon: mounted ? "externaldrive.fill" : "eject.fill",
                                title: name, subtitle: mounted ? "Disk connected" : "Disk ejected",
                                tint: mounted ? .white : .gray, seconds: duration)
    }

    // MARK: Bluetooth

    private func startBluetooth() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    /// The last popup shown for a device and what it said, so that the same news isn't told twice in a few seconds
    private var lastNews: [String: (state: Bool, at: Date)] = [:]

    private func isNew(_ address: String, connected: Bool) -> Bool {
        if let last = lastNews[address], last.state == connected, Date().timeIntervalSince(last.at) < 6 { return false }
        lastNews[address] = (connected, Date())
        return true
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        // One disconnect notification per device: an old one still registered would tell every disconnection again
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Devices that were already connected when the app started report themselves too: only show new connections
        guard Date().timeIntervalSince(launched) > 8, enabled("devicePopupBluetooth"), isNew(address, connected: true) else { return }
        let name = device.name ?? "Bluetooth device"
        guard device.isConnected() else { return }
        PopupCenter.shared.show(icon: Self.symbol(for: device, name: name), title: name, subtitle: "Connected", tint: .white, seconds: duration)
        // The battery takes a moment to be known
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            guard let battery = Self.batteryText(forAddress: address) else { return }
            PopupCenter.shared.show(icon: Self.symbol(for: device, name: name), title: name, subtitle: "Connected · \(battery)", tint: .white, seconds: self.duration)
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = nil
        guard enabled("devicePopupBluetooth"), Date().timeIntervalSince(launched) > 8 else { return }
        // A device that drops and comes back at once (or a notification that arrives late) is not a disconnection:
        // look at the real state a moment later, and only say "Disconnected" if it still is
        let name = device.name ?? "Bluetooth device"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !device.isConnected(), self.isNew(address, connected: false) else { return }
            PopupCenter.shared.show(icon: Self.symbol(for: device, name: name), title: name, subtitle: "Disconnected", tint: .gray, seconds: self.duration)
        }
    }

    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch device.deviceClassMajor {
        case 0x04: return n.contains("speaker") ? "hifispeaker.fill" : "headphones"
        case 0x05:
            let minor = device.deviceClassMinor
            if minor & 0x40 != 0 { return "keyboard.fill" }
            if minor & 0x80 != 0 { return "computermouse.fill" }
            return "gamecontroller.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// "80%", or "L 80% · R 75%" for earbuds, from the system's Bluetooth report
    private static func batteryText(forAddress address: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPBluetoothDataType"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = list["device_connected"] as? [[String: [String: Any]]] else { return nil }
        let wanted = address.replacingOccurrences(of: "-", with: ":").uppercased()
        for entry in connected {
            for (_, info) in entry where (info["device_address"] as? String)?.uppercased() == wanted {
                let l = info["device_batteryLevelLeft"] as? String, r = info["device_batteryLevelRight"] as? String
                if let l, let r { return "L \(l) · R \(r)" }
                return (info["device_batteryLevelMain"] as? String) ?? (info["device_batteryLevel"] as? String)
            }
        }
        return nil
    }
}
