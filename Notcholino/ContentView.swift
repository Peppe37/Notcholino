// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import EventKit

// MARK: - Sidebar Items
enum SidebarItem: String, Hashable, CaseIterable {
    case general     = "General"
    case display     = "Display"
    case sound       = "Sound"
    case devices     = "Devices"
    case shelf       = "Shelf"
    case nowPlaying  = "Now Playing"
    case calendar    = "Calendar"
    case controlCenter = "Control Center"
    case pluginStore = "Plugin Store"
    case notchy      = "Notchy"
    case license     = "License"
    case about       = "About"

    var icon: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .display:      return "sun.max.fill"
        case .sound:        return "speaker.wave.3.fill"
        case .devices:      return "airpodspro"
        case .shelf:        return "tray.full.fill"
        case .nowPlaying:   return "music.note"
        case .calendar:     return "calendar"
        case .controlCenter: return "square.grid.2x2.fill"
        case .pluginStore:  return "bag.fill"
        case .notchy:       return "face.smiling.inverse"
        case .license:      return "checkmark.seal.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return Color(NSColor.secondaryLabelColor)
        case .display:      return .yellow
        case .sound:        return .pink
        case .devices:      return .green
        case .shelf:        return .blue
        case .nowPlaying:   return .red
        case .calendar:     return .red
        case .controlCenter: return .purple
        case .pluginStore:  return .blue
        case .notchy:       return .indigo
        case .license:      return .teal
        case .about:        return Color(NSColor.secondaryLabelColor)
        }
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @State private var selection: SidebarItem? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // Top-level item (no section header)
                NavigationLink(value: SidebarItem.general) {
                    SidebarLabel(item: .general)
                }

                Section("Notifications") {
                    ForEach([SidebarItem.display, .sound, .devices], id: \.self) { item in
                        NavigationLink(value: item) { SidebarLabel(item: item) }
                    }
                }

                Section("Live Activities") {
                    ForEach([SidebarItem.controlCenter, .pluginStore, .notchy, .shelf, .nowPlaying, .calendar], id: \.self) { item in
                        NavigationLink(value: item) { SidebarLabel(item: item) }
                    }
                }

                Section("Notcholino") {
                    ForEach([SidebarItem.license, .about], id: \.self) { item in
                        NavigationLink(value: item) { SidebarLabel(item: item) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 250)
        } detail: {
            // Native macOS Settings look: no custom header, just Form
            detailView(for: selection)
        }
        .frame(minWidth: 680, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .openPluginStore)) { _ in selection = .pluginStore }
        .onReceive(NotificationCenter.default.publisher(for: .openNotchySettings)) { _ in selection = .notchy }
        // Native window title
        .navigationTitle("Notcholino")
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem?) -> some View {
        switch item {
        case .general:      GeneralSettingsView()
        case .display:      DisplaySettingsView()
        case .sound:        SoundSettingsView()
        case .devices:      DevicesSettingsView()
        case .shelf:        ShelfSettingsView()
        case .nowPlaying:   NowPlayingSettingsView()
        case .calendar:     CalendarSettingsView()
        case .controlCenter: ControlCenterSettingsView()
        case .pluginStore:  PluginStoreView()
        case .notchy:       NotchySettingsView()
        case .license:      LicenseView()
        case .about:        AboutView()
        case nil:           EmptyView()
        }
    }
}

// MARK: - Sidebar Label (with colored icon like System Settings)

struct SidebarLabel: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.rawValue)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .padding(5)
                .background(item.iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject private var launchMgr = LaunchAtLoginManager.shared
    @AppStorage("displayScreens")       private var displayScreens = 0

    @AppStorage("invertScroll")         private var invertScroll = false
    @AppStorage("hoverArea")            private var hoverArea = 0
    @AppStorage("notchWidth")           private var notchWidth: Double = 0
    @AppStorage("notchHeight")          private var notchHeight: Double = 0

    /// While the sliders move, a strip hangs under the notch: it shows how wide and tall the notch is drawn
    private func showSizeSample() {
        PopupCenter.shared.show(icon: "arrow.left.and.right", title: "Notch size", subtitle: "Match the real notch", seconds: 3)
    }

    var body: some View {
        Form {
            PermissionsSection()

            Section {
                Toggle("Launch at login",            isOn: $launchMgr.isEnabled)
            }
            
            Section {
                Picker("Open the notch", selection: $hoverArea) {
                    Text("At the top edge (small)").tag(0)
                    Text("Anywhere on the notch (normal)").tag(1)
                }
            } header: {
                Text("Opening")
            } footer: {
                Text("The small area is a thin strip along the top of the screen, so passing over a browser's tab bar doesn't open the notch by accident. Once open, the whole notch keeps it open.")
            }

            Section {
                Toggle("Invert swipe direction", isOn: $invertScroll)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Reverses the two-finger swipe (and the mouse wheel) that moves between Control Center, Now Playing and Calendar. Click and drag is not affected.")
            }

            Section("Monitors") {
                Picker("Show notch on", selection: $displayScreens) {
                    Text("Main screen only").tag(0)
                    Text("All screens").tag(1)
                }
            }

            Section {
                LabeledSlider(label: "Width",  value: $notchWidth,  range: -50...50,  unit: "px", format: "%.0f")
                    .onChange(of: notchWidth) { _ in showSizeSample() }
                LabeledSlider(label: "Height", value: $notchHeight, range: -20...20, unit: "px", format: "%.0f")
                    .onChange(of: notchHeight) { _ in showSizeSample() }
                Button("Reset") { notchWidth = 0; notchHeight = 0 }
                    .disabled(notchWidth == 0 && notchHeight == 0)
            } header: {
                Text("Notch Size Tuning")
            } footer: {
                Text("Notcholino draws its notch as wide as the one of your MacBook. If the black you see on the real notch is a bit wider or narrower than the one it draws, move the sliders: a sample strip appears under the notch so you can match them. 0 is the measured size.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}



// MARK: - System HUD access

/// Explains and fixes the Accessibility permission needed to hide the macOS volume/brightness HUD
struct SystemHUDAccessSection: View {
    @ObservedObject private var keys = MediaKeyInterceptor.shared

    var body: some View {
        Section {
            if keys.isActive {
                Label("The macOS volume and brightness HUD is hidden", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("The macOS HUD may still show next to Notcholino's", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Authorize") { PermissionsManager.shared.requestAccessibility() }
                    Button("Open Settings") { PermissionsManager.shared.openSettings(.accessibility) }
                }
            }
        } footer: {
            Text("To hide the system HUD, Notcholino handles the volume and brightness keys itself, which needs access in System Settings → Privacy & Security → Accessibility. Without it, the keys keep working as usual. If it looks switched on there but this still says it isn't, click Authorize: Notcholino clears the old entry left by a previous version and asks again.")
        }
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @AppStorage("displayEnabled")  private var enabled = true
    @AppStorage("displayTheme")    private var theme = 1
    @AppStorage("displayShowText") private var showText = true

    var body: some View {
        Form {
            Section {
                Toggle("Show display brightness changes", isOn: $enabled)
                    .onChange(of: enabled) { _ in updateOSDSuppression() }
            }
            SystemHUDAccessSection()
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Monochrome").tag(0)
                    Text("Yellow").tag(1)
                }
                Toggle("Show percentage text", isOn: $showText)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
    }
}

// MARK: - Sound Settings

struct SoundSettingsView: View {
    @AppStorage("soundEnabled")   private var enabled = true
    @AppStorage("soundTheme")     private var theme = 1
    @AppStorage("soundShowText")  private var showText = true

    var body: some View {
        Form {
            Section {
                Toggle("Show volume changes", isOn: $enabled)
                    .onChange(of: enabled) { _ in updateOSDSuppression() }
            }
            SystemHUDAccessSection()
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Monochrome").tag(0)
                    Text("Decibel").tag(1)
                }
                Toggle("Show volume text", isOn: $showText)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sound")
    }
}

// MARK: - Devices Settings

struct DevicesSettingsView: View {
    @AppStorage("devicePopupBluetooth") private var bluetooth = true
    @AppStorage("devicePopupPower")     private var power = true
    @AppStorage("devicePopupDisks")     private var disks = true
    @AppStorage("devicePopupSeconds")   private var seconds: Double = 4
    @AppStorage("focusMoonEnabled")     private var focusMoon = true
    @ObservedObject private var focus = FocusMonitor.shared
    @State private var btAuth = DeviceMonitor.bluetoothAuthorization

    var body: some View {
        Form {
            Section {
                Toggle("Bluetooth devices (AirPods, mouse, keyboard…)", isOn: $bluetooth)
                    .onChange(of: bluetooth) { _ in DeviceMonitor.shared.refreshBluetooth() }
                if bluetooth && btAuth != .allowedAlways {
                    HStack {
                        Label(btAuth == .notDetermined ? "Notcholino needs your permission to see Bluetooth connections" : "Bluetooth access is not allowed",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(btAuth == .notDetermined ? "Authorize" : "Open Settings") { DeviceMonitor.requestBluetoothAccess() }
                    }
                }
                Toggle("Charger plugged in or removed", isOn: $power)
                Toggle("Disks and USB drives", isOn: $disks)
                LabeledSlider(label: "Show for", value: $seconds, range: 2...8, unit: "s", format: "%.0f")
            } header: {
                Text("Popups")
            } footer: {
                Text("A small message hangs under the closed notch when one of these connects. For earbuds it adds the battery when macOS reports it. Bluetooth connections need your permission: click Authorize above.")
            }

            Section {
                Toggle("Show a moon beside the notch", isOn: $focusMoon)
                    .onChange(of: focusMoon) { _ in focus.refresh() }
                if focus.authorization == .authorized && focus.notShared {
                    Label("Allowed, but macOS isn't sharing the Focus status yet. Open System Settings → Focus and allow Notcholino to see it.", systemImage: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                if focus.authorization != .authorized {
                    HStack {
                        Label(focus.authorization == .notDetermined ? "Notcholino needs your permission to see if a Focus is on" : "Focus status is not allowed",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(focus.authorization == .notDetermined ? "Authorize" : "Open Settings") { focus.requestAccess() }
                    }
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                Text("macOS only tells apps whether a Focus is on, not which one. The moon shows for any of them.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Devices")
        .onAppear { focus.refresh(); btAuth = DeviceMonitor.bluetoothAuthorization }
        // A permission granted in the system dialog or in System Settings: pick it up, and start listening
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            btAuth = DeviceMonitor.bluetoothAuthorization
            DeviceMonitor.shared.refreshBluetooth()
        }
    }
}

// MARK: - Shelf Settings

struct ShelfSettingsView: View {
    @AppStorage("shelfEnabled")   private var enabled = true
    @AppStorage("shelfRetention") private var retention = 0
    @ObservedObject private var shelf = ShelfManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show the Shelf", isOn: $enabled)
            } footer: {
                Text("Drag a screenshot, a recording or any file toward the notch: it opens on the Shelf and keeps the file there, without saving it on your Desktop. Drag it out again whenever you like. The page between Control Center and Now Playing only appears while the Shelf holds something.")
            }

            Section {
                Picker("Keep files", selection: $retention) {
                    Text("Until I remove them").tag(0)
                    Text("For 24 hours").tag(1)
                    Text("Until restart").tag(2)
                }
                .onChange(of: retention) { _ in shelf.prune() }
            } footer: {
                Text("\"Until restart\" empties the Shelf when Notcholino starts again, which also happens after restarting the Mac.")
            }

            Section {
                LabeledContent("On the Shelf", value: shelf.items.isEmpty ? "Nothing" : "\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s"), \(shelf.totalSizeText)")
                Button("Empty the Shelf", role: .destructive) { shelf.removeAll() }
                    .disabled(shelf.items.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shelf")
    }
}

// MARK: - Now Playing Settings

struct NowPlayingSettingsView: View {
    @AppStorage("nowPlayingEnabled")   private var enabled = true
    @AppStorage("npPlayer")            private var player = 0
    @AppStorage("npSystemDetect")      private var systemDetect = true
    @AppStorage("npLeftAccessory")     private var leftAccessory = "shuffle"
    @AppStorage("npRightAccessory")    private var rightAccessory = "repeat"
    @AppStorage("npColorStyle")        private var colorStyle = 2
    @AppStorage("npLiveWaveform")      private var liveWaveform = true
    @AppStorage("spotifyClientID")     private var spotifyClientID = ""
    @ObservedObject private var spotify = SpotifyAuth.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Now Playing", isOn: $enabled)
            }

            Section {
                Toggle("Detect any app", isOn: $systemDetect)
                    .onChange(of: systemDetect) { _ in SystemNowPlayingMonitor.shared.apply() }
            } footer: {
                Text("Besides Spotify and Apple Music, show whatever macOS reports as playing: YouTube, Netflix or Prime Video in a browser, Amazon Music, Podcasts and more. Shuffle, repeat and like are only available for Spotify and Apple Music.")
            }

            Section("Music Player") {
                Picker("Default player", selection: $player) {
                    Text("Auto-detect").tag(0)
                    Text("Apple Music").tag(1)
                    Text("Spotify").tag(2)
                }
            }

            Section("Playback Controls") {
                Picker("Left accessory", selection: $leftAccessory) {
                    Text("None").tag("none")
                    Text("Shuffle").tag("shuffle")
                    Text("Repeat").tag("repeat")
                    Text("Like").tag("like")
                    Text("Devices").tag("devices")
                }
                Picker("Right accessory", selection: $rightAccessory) {
                    Text("None").tag("none")
                    Text("Shuffle").tag("shuffle")
                    Text("Repeat").tag("repeat")
                    Text("Like").tag("like")
                    Text("Devices").tag("devices")
                }
            }

            Section {
                HStack {
                    Text(spotify.isConnected ? "Connected" : "Not connected")
                        .foregroundStyle(spotify.isConnected ? .green : .secondary)
                    Spacer()
                    if spotify.isConnected {
                        Button("Disconnect") { spotify.disconnect() }
                    } else {
                        Button("Connect") { spotify.connect() }
                    }
                }
                if let err = spotify.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                DisclosureGroup("Advanced") {
                    TextField("Custom Client ID", text: $spotifyClientID)
                    Text("Only needed to use your own Spotify app. Redirect URI: \(SpotifyAuth.redirectURI)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Spotify Likes")
            } footer: {
                Text("Connect your Spotify account once to see and toggle liked songs.")
            }

            Section("Appearance") {
                Picker("Color style", selection: $colorStyle) {
                    Text("Monochrome").tag(0)
                    Text("Colored").tag(1)
                    Text("Gradient").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Animate waveform", isOn: $liveWaveform)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Now Playing")
    }
}

// MARK: - Calendar Settings

struct CalendarSettingsView: View {
    @AppStorage("calendarEnabled") private var enabled = true
    @AppStorage("calDisplayMode")  private var displayMode = 0
    @AppStorage("calendarShowReminders") private var showReminders = true
    @ObservedObject private var calMgr = CalendarManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Calendar", isOn: $enabled)
                Toggle("Show reminders due today", isOn: $showReminders)
                    .onChange(of: showReminders) { _ in calMgr.fetchReminders() }
            }
            Section("Display Mode") {
                Picker("View", selection: $displayMode) {
                    Text("Full month grid").tag(0)
                    Text("Today only").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if calMgr.hasAccess && !calMgr.availableCalendars.isEmpty {
                Section("Visible Calendars") {
                    ForEach(calMgr.availableCalendars, id: \.calendarIdentifier) { cal in
                        Toggle(isOn: Binding(
                            get: { calMgr.selectedCalendarIDs.contains(cal.calendarIdentifier) },
                            set: { isSelected in
                                if isSelected {
                                    calMgr.selectedCalendarIDs.insert(cal.calendarIdentifier)
                                } else {
                                    calMgr.selectedCalendarIDs.remove(cal.calendarIdentifier)
                                }
                            }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(nsColor: NSColor(cgColor: cal.cgColor) ?? .red))
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
    }
}


// MARK: - Plugins
struct ControlCenterSettingsView: View {
    @AppStorage("controlCenterEnabled") private var enabled = true
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var store = PluginStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Control Center", isOn: $enabled)
            } footer: {
                Text("The Control Center is the notch panel that holds your plugin buttons. Turn it off if you don't use plugins and you won't see it in the notch.")
            }

            Section {
                if pluginManager.loadedPlugins.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pluginManager.loadedPlugins, id: \.pluginIdentifier) { plugin in
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Button { pluginManager.move(identifier: plugin.pluginIdentifier, by: -1) } label: {
                                    Image(systemName: "chevron.up").frame(width: 20, height: 14)
                                }
                                .disabled(plugin.pluginIdentifier == pluginManager.loadedPlugins.first?.pluginIdentifier)
                                Button { pluginManager.move(identifier: plugin.pluginIdentifier, by: 1) } label: {
                                    Image(systemName: "chevron.down").frame(width: 20, height: 14)
                                }
                                .disabled(plugin.pluginIdentifier == pluginManager.loadedPlugins.last?.pluginIdentifier)
                            }
                            .buttonStyle(.borderless)
                            .help("Move this button in the Control Center")
                            Image(systemName: plugin.controlCenterIcon)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.pluginName).font(.headline)
                                Text("v\(plugin.pluginVersion) by \(plugin.pluginAuthor)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(plugin.pluginDescription)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) { store.remove(identifier: plugin.pluginIdentifier) }
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(pluginManager.loadErrors, id: \.self) { error in
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Installed Plugins")
            } footer: {
                Text("The arrows set the order of the buttons in the notch: left to right, row by row.")
            }

            Section {
                Button {
                    NotificationCenter.default.post(name: .openPluginStore, object: nil)
                } label: {
                    Label("Browse the Plugin Store", systemImage: "bag.fill")
                }
            } footer: {
                Text("Find, install and update plugins in the Plugin Store.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Control Center")
    }

}

// MARK: - License

struct LicenseView: View {
    var body: some View {
        Form {
            Section {
                Text("Notcholino is free software, released under the **GNU General Public License v3.0**.\n\nYou are free to use, study, modify and share it. If you share a modified version, it has to be released under the same license, with its source.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Section {
                Link("Read full license on GitHub",
                     destination: URL(string: "https://github.com/Peppe37/Notcholino/blob/main/LICENSE")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("License")
    }
}

// MARK: - About

struct AboutView: View {
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var installer = AppUpdater.shared
    @AppStorage("updateCheckEnabled") private var checkForUpdates = true

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Self.versionString)
                LabeledContent("Author",  value: "Giuseppe")
                LabeledContent("License", value: "GPL-3.0")
            }
            Section {
                if let release = updates.available {
                    LabeledContent("Update") {
                        HStack {
                            Link("Version \(release.version) is available", destination: release.url)
                            Button(installer.status ?? "Update and restart") { installer.install(release) }
                                .disabled(installer.isWorking)
                        }
                    }
                    if let failure = installer.failure {
                        Text(failure).font(.caption).foregroundStyle(.orange)
                    }
                } else if checkForUpdates {
                    LabeledContent("Update", value: updates.lastChecked == nil ? "Not checked yet" : "You have the latest version")
                }
                Toggle("Check for new versions", isOn: $checkForUpdates)
                Button(updates.isChecking ? "Checking…" : "Check now") { Task { await updates.check() } }
                    .disabled(updates.isChecking)
            } footer: {
                Text("Once a day, Notcholino asks GitHub for the list of releases (a single small request) and tells you when there is a newer one. It never downloads or installs anything by itself: Update and restart does it when you press it, keeping your permissions.")
            }
            Section {
                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/Peppe37/Notcholino")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About Notcholino")
    }
}

// MARK: - Shared Components

/// A slider row that matches the native macOS System Settings style.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var format: String = "%.1f"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value) + " \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }
}

func updateOSDSuppression() {
    let soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    let displayEnabled = UserDefaults.standard.object(forKey: "displayEnabled") as? Bool ?? true
    if soundEnabled || displayEnabled {
        OSDManager.shared.startSuppressing()
    } else {
        OSDManager.shared.stopSuppressing()
    }
}

// MARK: - Launch at Login Manager
import ServiceManagement

final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled != oldValue {
                toggleRegistration(enabled: isEnabled)
            }
        }
    }
    
    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func toggleRegistration(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to toggle Launch at Login: \(error)")
            // Revert state if it failed
            DispatchQueue.main.async {
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}


// MARK: - Plugin store: button and detail page

/// Install, Update or Installed, the same everywhere in the store
struct StoreButton: View {
    let plugin: RemotePlugin
    let installed: String?
    @ObservedObject private var store = PluginStore.shared

    var body: some View {
        if store.busyID == plugin.id {
            ProgressView().controlSize(.small)
        } else if !plugin.isCompatible {
            Text("Needs Notcholino \(plugin.minAppVersion ?? "")+").font(.caption).foregroundStyle(.secondary)
        } else if installed == nil {
            Button("Get") { Task { await store.install(plugin) } }.buttonStyle(.borderedProminent).controlSize(.small)
        } else if installed != plugin.version {
            Button("Update") { Task { await store.install(plugin) } }.buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            Text("Installed").font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// One plugin's page: what it is, screenshots, features, what it needs and what changed
struct PluginDetailView: View {
    let plugin: RemotePlugin
    let close: () -> Void
    @ObservedObject private var store = PluginStore.shared

    var body: some View {
        let installed = store.installedVersion(of: plugin.id)
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 28))
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(plugin.name).font(.title.bold())
                    Text("by \(plugin.author) · v\(plugin.version)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                StoreButton(plugin: plugin, installed: installed)
                Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let shots = plugin.screenshots, !shots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(shots, id: \.self) { url in
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
                                            .overlay(ProgressView().controlSize(.small))
                                    }
                                    .frame(height: 210)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.2)))
                                }
                            }
                        }
                    }
                    if let video = plugin.video {
                        Link(destination: video) { Label("Watch the video", systemImage: "play.circle.fill") }
                    }

                    if let warning = plugin.warning {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Known problem", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                            Text(warning).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.14)))
                    }

                    Text(plugin.details ?? plugin.description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let features = plugin.features, !features.isEmpty {
                        section("What it does") {
                            ForEach(features, id: \.self) { f in
                                Label(f, systemImage: "checkmark.circle.fill").foregroundStyle(.primary, .green)
                            }
                        }
                    }
                    if let permissions = plugin.permissions, !permissions.isEmpty {
                        section("What it needs") { Text(permissions).foregroundStyle(.secondary) }
                    }
                    if let news = plugin.whatsNew, !news.isEmpty {
                        section("What's new in \(plugin.version)") {
                            ForEach(news, id: \.self) { n in Text("• \(n)").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    if let message = store.message {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                    HStack(spacing: 14) {
                        Text("Needs Notcholino \(plugin.minAppVersion ?? "any version")").font(.caption).foregroundStyle(.secondary)
                        Link("Source on GitHub", destination: URL(string: "https://github.com/Peppe37/Notcholino/tree/main/plugins/\(plugin.id)")!).font(.caption)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 560)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}


extension Notification.Name {
    static let openPluginStore = Notification.Name("openPluginStore")
    static let openNotchySettings = Notification.Name("openNotchySettings")
}

// MARK: - Plugin Store (a grid, with search)

struct PluginStoreView: View {
    @ObservedObject private var store = PluginStore.shared
    @State private var query = ""
    @State private var category = "All"
    @State private var detail: RemotePlugin?

    private var categories: [String] {
        ["All"] + Array(Set(store.available.compactMap(\.category))).sorted()
    }

    private var shown: [RemotePlugin] {
        store.available.filter { (category == "All" || $0.category == category) && $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !store.updates.isEmpty {
                    HStack {
                        Label("\(store.updates.count) update\(store.updates.count == 1 ? "" : "s") available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Button("Update all") { Task { await store.updateAll() } }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(store.busyID != nil)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
                }

                ExtensionsShelf()

                Text("Plugins").font(.title3.weight(.semibold)).padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c) { category = c }
                                .buttonStyle(.plain)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(category == c ? Color.accentColor : Color.secondary.opacity(0.15)))
                                .foregroundStyle(category == c ? Color.white : Color.primary)
                        }
                    }
                }

                if store.isLoading && store.available.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
                } else if shown.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text(query.isEmpty ? "No plugins here yet." : "No plugin matches \"\(query)\".").foregroundStyle(.secondary)
                        Text("Search looks at names, descriptions, what a plugin does and its keywords.").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)], spacing: 14) {
                        ForEach(shown) { plugin in
                            PluginCard(plugin: plugin) { detail = plugin }
                        }
                    }
                }

                if let message = store.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Text("Plugins are downloaded from the Notcholino releases on GitHub, always at their latest version, after a checksum check.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search plugins, features, keywords")
        .navigationTitle("Plugin Store")
        .task { await store.refresh() }
        .toolbar {
            ToolbarItem { Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading).help("Refresh the list") }
        }
        .sheet(item: $detail) { plugin in
            PluginDetailView(plugin: plugin) { detail = nil }
        }
    }
}

/// A plugin in the grid: a big icon, its name, a line about it and the button
private struct PluginCard: View {
    let plugin: RemotePlugin
    let open: () -> Void
    @ObservedObject private var store = PluginStore.shared

    var body: some View {
        let installed = store.installedVersion(of: plugin.id)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: plugin.icon)
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name).font(.headline)
                Text(plugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                if plugin.warning != nil {
                    Label("Known problem", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                } else if let category = plugin.category { Text(category).font(.caption2).foregroundStyle(.tertiary) }
                Spacer()
                StoreButton(plugin: plugin, installed: installed)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.secondary.opacity(0.14)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: open)
    }
}

// MARK: - Extensions

/// Extensions are bigger than plugins: where a plugin is a button in Control Center, an extension has its own page in the notch,
/// its own settings, and can use AI. They are part of the app and switched on here. (More will follow.)
struct NotcholinoExtension: Identifiable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let color: Color
    let isEnabled: () -> Bool
    let setEnabled: (Bool) -> Void
    let openSettings: () -> Void

    static let all: [NotcholinoExtension] = [
        NotcholinoExtension(id: "notchy", name: "Notchy",
                            summary: "A small glass cube that lives in the notch: summaries of files and text, your day planned from your calendars, a look at the screen, email alerts and voice. You bring your own AI key.",
                            symbol: "face.smiling.inverse", color: .indigo,
                            isEnabled: { NotchySettings.shared.enabled },
                            setEnabled: { NotchySettings.shared.enabled = $0 },
                            openSettings: { NotificationCenter.default.post(name: .openNotchySettings, object: nil) }),
    ]
}

struct ExtensionsShelf: View {
    @ObservedObject private var notchy = NotchySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Extensions").font(.title3.weight(.semibold))
            ForEach(NotcholinoExtension.all) { ext in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: ext.symbol).font(.title2).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ext.color.gradient))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(ext.name).font(.headline)
                            Text("Extension").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        }
                        Text(ext.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Settings") { ext.openSettings() }.controlSize(.small)
                        }.padding(.top, 2)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { notchy.enabled }, set: { ext.setEnabled($0) })).labelsHidden()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.1)))
            }
            Text("Plugins are simple buttons in Control Center. Extensions are bigger: they have their own page in the notch and their own settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
