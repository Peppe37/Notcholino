import SwiftUI

// MARK: - Sidebar Items
enum SidebarItem: String, Hashable, CaseIterable {
    case general     = "General"
    case battery     = "Battery"
    case connectivity = "Connectivity"
    case focus       = "Focus"
    case display     = "Display"
    case sound       = "Sound"
    case nowPlaying  = "Now Playing"
    case calendar    = "Calendar"
    case lockScreen  = "Lock Screen"
    case license     = "License"
    case about       = "About"

    var icon: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .battery:      return "bolt.fill"
        case .connectivity: return "headphones"
        case .focus:        return "moon.fill"
        case .display:      return "sun.max.fill"
        case .sound:        return "speaker.wave.3.fill"
        case .nowPlaying:   return "music.note"
        case .calendar:     return "calendar"
        case .lockScreen:   return "lock.fill"
        case .license:      return "checkmark.seal.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return Color(NSColor.secondaryLabelColor)
        case .battery:      return .orange
        case .connectivity: return .green
        case .focus:        return .indigo
        case .display:      return .yellow
        case .sound:        return .pink
        case .nowPlaying:   return .red
        case .calendar:     return .red
        case .lockScreen:   return Color(NSColor.labelColor)
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
                    ForEach([SidebarItem.battery, .connectivity, .focus, .display, .sound], id: \.self) { item in
                        NavigationLink(value: item) { SidebarLabel(item: item) }
                    }
                }

                Section("Live Activities") {
                    ForEach([SidebarItem.nowPlaying, .calendar, .lockScreen], id: \.self) { item in
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
        case .battery:      BatterySettingsView()
        case .connectivity: ConnectivitySettingsView()
        case .focus:        FocusSettingsView()
        case .display:      DisplaySettingsView()
        case .sound:        SoundSettingsView()
        case .nowPlaying:   NowPlayingSettingsView()
        case .calendar:     CalendarSettingsView()
        case .lockScreen:   LockScreenSettingsView()
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
    @AppStorage("launchAtLogin")        private var launchAtLogin = true
    @AppStorage("hideInFullscreen")     private var hideInFullscreen = true
    @AppStorage("hideInMissionControl") private var hideInMissionControl = true
    @AppStorage("hideWhileGaming")      private var hideWhileGaming = false
    @AppStorage("notchWidth")           private var notchWidth: Double = 0
    @AppStorage("notchHeight")          private var notchHeight: Double = 0

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login",            isOn: $launchAtLogin)
                Toggle("Hide in fullscreen apps",    isOn: $hideInFullscreen)
                Toggle("Hide in Mission Control",    isOn: $hideInMissionControl)
                Toggle("Hide while gaming",          isOn: $hideWhileGaming)
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

// MARK: - Battery Settings

struct BatterySettingsView: View {
    @AppStorage("batteryEnabled")        private var enabled = true
    @AppStorage("batteryDuration")       private var duration: Double = 5.0
    @AppStorage("lowBatteryWarning")     private var lowWarning = true
    @AppStorage("lowBatteryThreshold")   private var threshold: Double = 10.0

    var body: some View {
        Form {
            Section {
                Toggle("Show battery notifications", isOn: $enabled)
                LabeledSlider(label: "Display duration", value: $duration, range: 1...15, unit: "s")
            }
            Section("Low Battery Warning") {
                Toggle("Warn when battery is low", isOn: $lowWarning)
                LabeledSlider(label: "Threshold", value: $threshold, range: 5...30, unit: "%", format: "%.0f")
                    .disabled(!lowWarning)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery")
    }
}

// MARK: - Connectivity Settings

struct ConnectivitySettingsView: View {
    @AppStorage("connectivityEnabled") private var enabled = true
    @AppStorage("connDuration")        private var duration: Double = 5.0
    @AppStorage("connStyle")           private var style = 1

    var body: some View {
        Form {
            Section {
                Toggle("Show connectivity notifications", isOn: $enabled)
                LabeledSlider(label: "Display duration", value: $duration, range: 1...15, unit: "s")
            }
            Section("Style") {
                Picker("Icon style", selection: $style) {
                    Text("3D Models").tag(0)
                    Text("SF Symbols").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connectivity")
    }
}

// MARK: - Focus Settings (placeholder)

struct FocusSettingsView: View {
    @AppStorage("focusEnabled") private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show Focus mode changes", isOn: $enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Focus")
    }
}

// MARK: - Display Settings (placeholder)

struct DisplaySettingsView: View {
    @AppStorage("displayEnabled") private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show display brightness changes", isOn: $enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
    }
}

// MARK: - Sound Settings (placeholder)

struct SoundSettingsView: View {
    @AppStorage("soundEnabled") private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show volume changes", isOn: $enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sound")
    }
}

// MARK: - Now Playing Settings

struct NowPlayingSettingsView: View {
    @AppStorage("nowPlayingEnabled")   private var enabled = true
    @AppStorage("npIdleDuration")      private var idleDuration: Double = 3.0
    @AppStorage("npPlayer")            private var player = 0
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
                LabeledSlider(label: "Idle timeout", value: $idleDuration, range: 1...15, unit: "s")
            }

            Section("Music Player") {
                Picker("Default player", selection: $player) {
                    Text("Auto-detect").tag(0)
                    Text("Apple Music").tag(1)
                    Text("Spotify").tag(2)
                    Text("YouTube Music").tag(3)
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

    var body: some View {
        Form {
            Section {
                Toggle("Show Calendar", isOn: $enabled)
            }
            Section("Display Mode") {
                Picker("View", selection: $displayMode) {
                    Text("Full month grid").tag(0)
                    Text("Today only").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
    }
}

// MARK: - Lock Screen Settings (placeholder)

struct LockScreenSettingsView: View {
    @AppStorage("lockScreenEnabled") private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show lock/unlock animations", isOn: $enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lock Screen")
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
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: "0.1.0 (beta)")
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
