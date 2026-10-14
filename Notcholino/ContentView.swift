import SwiftUI
import EventKit

// MARK: - Sidebar Items
enum SidebarItem: String, Hashable, CaseIterable {
    case general     = "General"
    case display     = "Display"
    case sound       = "Sound"
    case nowPlaying  = "Now Playing"
    case calendar    = "Calendar"
    case controlCenter = "Control Center"
    case license     = "License"
    case about       = "About"

    var icon: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .display:      return "sun.max.fill"
        case .sound:        return "speaker.wave.3.fill"
        case .nowPlaying:   return "music.note"
        case .calendar:     return "calendar"
        case .controlCenter: return "square.grid.2x2.fill"
        case .license:      return "checkmark.seal.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return Color(NSColor.secondaryLabelColor)
        case .display:      return .yellow
        case .sound:        return .pink
        case .nowPlaying:   return .red
        case .calendar:     return .red
        case .controlCenter: return .purple
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
                    ForEach([SidebarItem.display, .sound], id: \.self) { item in
                        NavigationLink(value: item) { SidebarLabel(item: item) }
                    }
                }

                Section("Live Activities") {
                    ForEach([SidebarItem.controlCenter, .nowPlaying, .calendar], id: \.self) { item in
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
        // Native window title
        .navigationTitle("Notcholino")
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem?) -> some View {
        switch item {
        case .general:      GeneralSettingsView()
        case .display:      DisplaySettingsView()
        case .sound:        SoundSettingsView()
        case .nowPlaying:   NowPlayingSettingsView()
        case .calendar:     CalendarSettingsView()
        case .controlCenter: ControlCenterSettingsView()
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

            Section("Notch Size Tuning") {
                LabeledSlider(label: "Width",  value: $notchWidth,  range: -50...50,  unit: "px", format: "%.0f")
                LabeledSlider(label: "Height", value: $notchHeight, range: -20...20, unit: "px", format: "%.0f")
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

            Section("Installed Plugins") {
                if pluginManager.loadedPlugins.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pluginManager.loadedPlugins, id: \.pluginIdentifier) { plugin in
                        HStack(spacing: 12) {
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
            }

            Section {
                if store.isLoading && store.available.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
                }
                ForEach(store.available) { plugin in
                    storeRow(plugin)
                }
                if let message = store.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Refresh") { Task { await store.refresh() } }
                        .disabled(store.isLoading)
                }
            } header: {
                Text("Plugin Store")
            } footer: {
                Text("Plugins are downloaded from the Notcholino releases on GitHub, always at their latest version.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Control Center")
        .task { await store.refresh() }
    }

    @ViewBuilder
    private func storeRow(_ plugin: RemotePlugin) -> some View {
        let installed = store.installedVersion(of: plugin.id)
        HStack(spacing: 12) {
            Image(systemName: plugin.icon)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).font(.headline)
                Text("v\(plugin.version) by \(plugin.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(plugin.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.busyID == plugin.id {
                ProgressView().controlSize(.small)
            } else if !plugin.isCompatible {
                Text("Needs Notcholino \(plugin.minAppVersion ?? "")+").font(.caption).foregroundStyle(.secondary)
            } else if installed == nil {
                Button("Install") { Task { await store.install(plugin) } }
            } else if installed != plugin.version {
                Button("Update") { Task { await store.install(plugin) } }
            } else {
                Text("Installed").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - License

struct LicenseView: View {
    var body: some View {
        Form {
            Section {
                Text("Notcholino is released under the **PolyForm Noncommercial 1.0.0** license.\n\nYou are free to use, share, and modify this software for personal, non-commercial purposes. Commercial use requires a separate agreement.")
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
                LabeledContent("License", value: "PolyForm Noncommercial 1.0.0")
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
