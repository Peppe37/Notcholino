// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Version of the extension API implemented by this build of Notcholino.
/// An extension whose `apiVersion` differs from this is not loaded.
public let notcholinoExtensionAPIVersion = 1

/// What an extension is: bigger than a plugin. A plugin is a button in the Control Center; an extension has its own page in the
/// notch, its own settings, and may ask Notchy's AI for help. Extensions are compiled bundles (.bundle) that export a principal
/// class implementing this protocol, and they run inside Notcholino, so they are only loaded in **developer mode**, from
/// `~/Library/Application Support/Notcholino/Extensions`. See extensions/GUIDE.md.
///
/// This file is compiled into the app and into every extension, so it must stay Objective-C compatible.
@objc(NotcholinoExtension)
public protocol NotcholinoExtension: NSObjectProtocol {
    /// Must equal `notcholinoExtensionAPIVersion`
    var apiVersion: Int { get }
    /// Stable, lowercase identifier (for example "weather")
    var extensionIdentifier: String { get }
    var extensionName: String { get }
    var extensionVersion: String { get }
    var extensionAuthor: String { get }
    var extensionDescription: String { get }
    /// Name of an SF Symbol for the extension's icon
    var extensionSymbol: String { get }

    /// The extension's page in the notch. It is given about 640 × 150 points; Auto Layout or a fixed frame both work.
    /// Called when the page is shown; return a new view each time or keep one.
    func makePageView() -> NSView

    /// Optional: the extension's settings, shown from Settings → Plugin Store → Extensions
    @objc optional func makeSettingsView() -> NSView

    /// Called before the extension is switched off or Notcholino quits
    @objc optional func extensionWillUnload()

    /// Called once, right after loading. Call `handler` on the main thread to show a small popup under the closed notch, with
    /// the same keys as a plugin popup: `"title"`, `"subtitle"`, `"icon"`, `"color"`, `"seconds"`.
    @objc optional func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void)

    /// Called once, right after loading. Call `handler(prompt, system, completion)` to ask the AI the user chose for text in
    /// Settings → Notchy. `completion` receives the answer, or an error message. It only works if the user switched on
    /// "Allow this extension to use Notchy's AI" for it, and the user's keys never reach the extension.
    @objc optional func setAskHandler(_ handler: @escaping (_ prompt: String, _ system: String?, _ completion: @escaping (String?, String?) -> Void) -> Void)

    // MARK: Optional: fuller integration (added with Notchy, which is itself an extension)

    /// Called once, right after loading, with what the app offers an extension. Keep it.
    @objc optional func setHost(_ host: NotcholinoHost)

    /// A small view drawn beside the closed notch (about 20 × 20 points) while the extension says so with
    /// `host.setWingVisible(true)`. Return it once; it should update itself.
    @objc optional func makeWingView() -> NSView

    /// The user switched the extension on (right after loading it, or from the store). Start whatever it does on its own here.
    @objc optional func extensionDidEnable()

    /// Text the user sent to the extension (right-click → Services → Send to Notchy). Only the extension that declares itself the
    /// assistant, see `isAssistant`, receives it.
    @objc optional func receiveText(_ text: String)
    /// Files the user sent to it from Finder
    @objc optional func receiveFiles(_ urls: [URL])
    /// Whether the extension wants its page in the notch right now (default true). Call `host.pagesChanged()` when it changes.
    @objc optional var pageVisible: Bool { get }

    /// True for an extension that wants what the user sends from the right-click menu, and that answers other extensions' AI
    /// requests (`askAI`).
    @objc optional var isAssistant: Bool { get }
    /// Answer a request another extension made through the host (an assistant that holds the user's AI keys does this: the
    /// requesting extension never sees a key).
    @objc optional func askAI(_ prompt: String, system: String?, completion: @escaping (String?, String?) -> Void)

    /// Something happened in the app: `"plugin"` when a plugin showed a popup (`info["title"]`).
    @objc optional func hostEvent(_ name: String, info: [String: Any])
}

/// What the app offers an extension, handed over in `setHost(_:)`
@objc(NotcholinoHost)
public protocol NotcholinoHost: NSObjectProtocol {
    /// Show a small popup under the closed notch (same keys as `setPopupHandler`). Add `"opensPage": true` and moving the pointer
    /// to the notch opens this extension's page.
    func showPopup(_ info: [String: Any])
    /// Show or hide the extension's wing view (`makeWingView`) beside the closed notch
    func setWingVisible(_ visible: Bool)
    /// Open the notch on this extension's page (on the display the pointer is on) and keep it open until called with `false`, for
    /// something that happens while the user is busy elsewhere, like dragging a window. The page is shown even if
    /// `pageVisible` is false.
    func setNotchOpen(_ open: Bool)
    /// Hide a popup this extension is showing
    func dismissPopup()
    /// True if the user allowed Notcholino to read Calendar or Reminders
    func hasCalendarAccess() -> Bool
    /// Tell the app the extension's page was switched on or off (see `pageVisible`)
    func pagesChanged()
    /// What is left of today, from the calendars the user ticked in Notcholino's Calendar settings and the reminders the notch
    /// shows. One line each; titles and times only.
    func agendaLines() -> [String]
    /// The calendar and the reminders over a span of days (from the start of `from`'s day to the end of `to`'s day), as the agenda
    /// lines above. For "what do I have tomorrow?". The completion is called on the main thread. (Notcholino 0.28.0 and later.)
    func agenda(from: Date, to: Date, completion: @escaping ([String]) -> Void)
    /// The next event today, like "Meeting at 15:00", or nil
    func nextEventLine() -> String?
    func isMusicPlaying() -> Bool
    /// Identifiers of the plugins that are doing something right now (a Tomato timer, Espresso keeping the Mac awake)
    func activePluginIDs() -> [String]
    /// Open the Notcholino settings on this extension's page
    func openSettings()
}
