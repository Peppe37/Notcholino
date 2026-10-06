import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .general

    enum SidebarItem: Hashable {
        case general
        case battery
        case connectivity
        case focus
        case display
        case sound
        case nowPlaying
        case calendar
        case lockScreen
        case license
        case about
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: SidebarItem.general) {
                        Label("General", systemImage: "gearshape.fill")
                    }
                }

                Section("Notifications") {
                    NavigationLink(value: SidebarItem.battery) {
                        Label("Battery", systemImage: "bolt.fill")
                            .foregroundStyle(.orange)
                    }
                    NavigationLink(value: SidebarItem.connectivity) {
                        Label("Connectivity", systemImage: "headphones")
                            .foregroundStyle(.green)
                    }
                    NavigationLink(value: SidebarItem.focus) {
                        Label("Focus", systemImage: "moon.fill")
                            .foregroundStyle(.indigo)
                    }
                    NavigationLink(value: SidebarItem.display) {
                        Label("Display", systemImage: "sun.max.fill")
                            .foregroundStyle(.purple)
                    }
                    NavigationLink(value: SidebarItem.sound) {
                        Label("Sound", systemImage: "speaker.wave.3.fill")
                            .foregroundStyle(.pink)
                    }
                }

                Section("Live Activities") {
                    NavigationLink(value: SidebarItem.nowPlaying) {
                        Label("Now Playing", systemImage: "play.circle.fill")
                            .foregroundStyle(.red)
                    }
                    NavigationLink(value: SidebarItem.calendar) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.red)
                    }
                    NavigationLink(value: SidebarItem.lockScreen) {
                        Label("Lock Screen", systemImage: "lock.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Notcholino") {
                    NavigationLink(value: SidebarItem.license) {
                        Label("License", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.teal)
                    }
                    NavigationLink(value: SidebarItem.about) {
                        Label("About", systemImage: "info.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            ScrollView {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .battery:
                    BatterySettingsView()
                case .connectivity:
                    ConnectivitySettingsView()
                case .nowPlaying:
                    NowPlayingSettingsView()
                case .calendar:
                    CalendarSettingsView()
                default:
                    Text("Select an option")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .padding(.top, 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("hideInFullscreen") private var hideInFullscreen = true
    @AppStorage("hideInMissionControl") private var hideInMissionControl = true
    @AppStorage("hideWhileGaming") private var hideWhileGaming = false
    @AppStorage("forceSimulatedNotch") private var forceSimulatedNotch = false

    @AppStorage("notchWidth") private var notchWidth: Double = 0
    @AppStorage("notchHeight") private var notchHeight: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "General", icon: "gearshape.fill", color: .gray)

            Form {
                Section {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                    Toggle("Hide in fullscreen", isOn: $hideInFullscreen)
                    Toggle("Hide in mission control", isOn: $hideInMissionControl)
                    Toggle("Hide while gaming", isOn: $hideWhileGaming)
                    Toggle("Force simulated notch", isOn: $forceSimulatedNotch)
                }

                Section("Tuning") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Notch width")
                            Spacer()
                            Text("\(Int(notchWidth)) px").foregroundStyle(.secondary)
                        }
                        Slider(value: $notchWidth, in: -50...50)
                            .tint(.teal)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Notch height")
                            Spacer()
                            Text("\(Int(notchHeight)) px").foregroundStyle(.secondary)
                        }
                        Slider(value: $notchHeight, in: -20...20)
                            .tint(.teal)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Battery Settings
struct BatterySettingsView: View {
    @AppStorage("batteryEnabled") private var batteryEnabled = true
    @AppStorage("batteryDuration") private var batteryDuration: Double = 5.0
    @AppStorage("lowBatteryWarning") private var lowBatteryWarning = true
    @AppStorage("lowBatteryThreshold") private var lowBatteryThreshold: Double = 10.0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Battery", icon: "bolt.fill", color: .orange)

            Form {
                Section {
                    Toggle(isOn: $batteryEnabled) {
                        Label("Battery", systemImage: "bolt.fill")
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(String(format: "%.1f s", batteryDuration)).foregroundStyle(.secondary)
                        }
                        Slider(value: $batteryDuration, in: 1...10)
                            .tint(.teal)
                    }
                }

                Section {
                    Toggle("Warn on low battery", isOn: $lowBatteryWarning)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Low battery threshold")
                            Spacer()
                            Text("\(Int(lowBatteryThreshold))%").foregroundStyle(.secondary)
                        }
                        Slider(value: $lowBatteryThreshold, in: 1...30)
                            .tint(.teal)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Connectivity Settings
struct ConnectivitySettingsView: View {
    @AppStorage("connectivityEnabled") private var connectivityEnabled = true
    @AppStorage("connDuration") private var connDuration: Double = 5.0
    @AppStorage("connStyle") private var connStyle = 1 // 0: 3D, 1: Symbols

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Connectivity", icon: "headphones", color: .green)

            Form {
                Section {
                    Toggle(isOn: $connectivityEnabled) {
                        Label("Connectivity", systemImage: "headphones")
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(String(format: "%.1f s", connDuration)).foregroundStyle(.secondary)
                        }
                        Slider(value: $connDuration, in: 1...10)
                            .tint(.teal)
                    }
                }

                Section {
                    Picker("Style", selection: $connStyle) {
                        Text("3D models").tag(0)
                        Text("Symbols").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Now Playing Settings
struct NowPlayingSettingsView: View {
    @AppStorage("nowPlayingEnabled") private var nowPlayingEnabled = true
    @AppStorage("npIdleDuration") private var npIdleDuration: Double = 3.0
    @AppStorage("npColorStyle") private var npColorStyle = 2 // 0: Mono, 1: Colored, 2: Gradient
    @AppStorage("npLiveWaveform") private var npLiveWaveform = true
    @AppStorage("npPlayer") private var npPlayer = 0 // 0: Auto, 1: Spotify, 2: Apple Music, 3: YouTube Music
    @AppStorage("npShowShuffle") private var npShowShuffle = false
    @AppStorage("npShowRepeat") private var npShowRepeat = false
    @AppStorage("npShowFavorites") private var npShowFavorites = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Now Playing", icon: "play.circle.fill", color: .red)

            Form {
                Section {
                    Toggle(isOn: $nowPlayingEnabled) {
                        Label("Now Playing", systemImage: "play.fill")
                            .foregroundStyle(.teal)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Idle duration")
                            Spacer()
                            Text(String(format: "%.1f s", npIdleDuration)).foregroundStyle(.secondary)
                        }
                        Slider(value: $npIdleDuration, in: 1...10)
                            .tint(.teal)
                    }
                }

                Section("Music Player") {
                    Picker("Default Player", selection: $npPlayer) {
                        Text("Auto").tag(0)
                        Text("Apple Music").tag(1)
                        Text("Spotify").tag(2)
                        Text("YouTube Music").tag(3)
                    }
                    .pickerStyle(.menu)
                }

                Section("Controls") {
                    Toggle("Show Shuffle Button", isOn: $npShowShuffle)
                    Toggle("Show Repeat Button", isOn: $npShowRepeat)
                    Toggle("Show Favorites Button", isOn: $npShowFavorites)
                }

                Section("Appearance") {
                    Picker("Color Style", selection: $npColorStyle) {
                        Text("Monochrome").tag(0)
                        Text("Colored").tag(1)
                        Text("Gradient").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)

                    Toggle("Use live waveform", isOn: $npLiveWaveform)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Calendar Settings
struct CalendarSettingsView: View {
    @AppStorage("calendarEnabled") private var calendarEnabled = true
    @AppStorage("calDisplayMode") private var calDisplayMode = 0 // 0: Full Month, 1: Today Only

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Calendar", icon: "calendar", color: .red)

            Form {
                Section {
                    Toggle(isOn: $calendarEnabled) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.red)
                    }
                }

                Section("Display Options") {
                    Picker("Display Mode", selection: $calDisplayMode) {
                        Text("Full Month Grid").tag(0)
                        Text("Today's Events Only").tag(1)
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
        }
    }
}


// MARK: - Components
struct HeaderView: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .padding(6)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.title2.bold())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}
