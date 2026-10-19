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
}
