import SwiftUI

/// Small capsule button shown in the notch where something needs a permission
struct AuthorizeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One line of the Permissions list in the settings
private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isGranted ? "checkmark.circle.fill" : (state == .unavailable ? "circle.dashed" : "exclamationmark.circle.fill"))
                .foregroundStyle(state.isGranted ? Color.green : (state == .unavailable ? Color.secondary : Color.orange))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:       Text("Allowed").foregroundStyle(.secondary)
            case .notDetermined: Button("Authorize", action: action)
            case .denied:        Button("Open Settings", action: action)
            case .unavailable:   EmptyView()
            }
        }
    }
}

/// Everything Notcholino can ask for, with a button to grant each
struct PermissionsSection: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    @ObservedObject private var spotify = SpotifyAuth.shared

    var body: some View {
        Section {
            PermissionRow(title: "Calendar", detail: "Show your events", state: permissions.calendar) {
                permissions.requestCalendar()
            }
            PermissionRow(title: "Reminders", detail: "Show the reminders due today", state: permissions.reminders) {
                permissions.requestReminders()
            }
            PermissionRow(title: "Control Spotify",
                          detail: permissions.spotify == .unavailable ? "Open Spotify to check" : "Read and control playback",
                          state: permissions.spotify) {
                permissions.requestAutomation(bundleID: PermissionsManager.spotifyID)
            }
            PermissionRow(title: "Control Music",
                          detail: permissions.music == .unavailable ? "Open Music to check" : "Read and control playback",
                          state: permissions.music) {
                permissions.requestAutomation(bundleID: PermissionsManager.musicID)
            }
            PermissionRow(title: "Accessibility", detail: "Hide the macOS volume and brightness HUD",
                          state: permissions.accessibility ? .granted : .notDetermined) {
                permissions.requestAccessibility()
            }
            HStack(spacing: 10) {
                Image(systemName: spotify.isConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(spotify.isConnected ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Spotify account")
                    Text("Like songs from the notch").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if spotify.isConnected {
                    Text("Connected").foregroundStyle(.secondary)
                } else {
                    Button("Connect") { spotify.connect() }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Notcholino only asks for what it needs. Controlling Spotify or Music can only be checked while that app is open. If a permission looks switched on in System Settings but still says Authorize here, click Authorize: after an update the old entry no longer applies, and Notcholino clears it and asks again.")
        }
        .onAppear { permissions.refresh() }
        // The window can stay open while a permission is granted in System Settings: pick it up when coming back
        // to the app, and every couple of seconds while this list is on screen
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissions.refresh()
        }
    }
}
