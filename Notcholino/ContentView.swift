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
                    }
                    NavigationLink(value: SidebarItem.connectivity) {
                        Label("Connectivity", systemImage: "headphones")
                    }
                    NavigationLink(value: SidebarItem.focus) {
                        Label("Focus", systemImage: "moon.fill")
                    }
                    NavigationLink(value: SidebarItem.display) {
                        Label("Display", systemImage: "sun.max.fill")
                    }
                    NavigationLink(value: SidebarItem.sound) {
                        Label("Sound", systemImage: "speaker.wave.3.fill")
                    }
                }
                
                Section("Live Activities") {
                    NavigationLink(value: SidebarItem.nowPlaying) {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    NavigationLink(value: SidebarItem.calendar) {
                        Label("Calendar", systemImage: "calendar")
                    }
                    NavigationLink(value: SidebarItem.lockScreen) {
                        Label("Lock Screen", systemImage: "lock.fill")
                    }
                }
                
                Section("Notcholino") {
                    NavigationLink(value: SidebarItem.license) {
                        Label("License", systemImage: "checkmark.seal.fill")
                    }
                    NavigationLink(value: SidebarItem.about) {
                        Label("About", systemImage: "info.circle.fill")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            switch selection {
            case .general:
                Text("General Settings")
                    .font(.largeTitle)
            case .battery:
                Text("Battery Settings")
                    .font(.largeTitle)
            case .nowPlaying:
                Text("Now Playing Settings")
                    .font(.largeTitle)
            default:
                Text("Select an option")
                    .font(.largeTitle)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
