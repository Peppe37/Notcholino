import Foundation

/// Version of the plugin API implemented by this build of Notcholino.
/// A plugin whose `apiVersion` differs from this is not loaded.
public let notcholinoPluginAPIVersion = 1

/// Protocol that compiled plugins (.bundle) must implement and export as their principal class.
///
/// This file is compiled into both the app and every plugin, so it must stay Foundation-only
/// and Objective-C compatible: values cross the bundle boundary as plain Foundation types.
///
/// Menu items returned by `menuItems()` are dictionaries with these keys:
/// - `"id"`          (String)  identifier passed back to `performMenuAction(_:)`
/// - `"title"`       (String)  text of the option
/// - `"checked"`     (Bool)    optional, highlights the option as the current choice
/// - `"destructive"` (Bool)    optional, draws the option in red (e.g. "Turn off")
/// - `"header"`      (String)  alternatively, a non-clickable section title (no `"id"`)
@objc(NotcholinoPlugin)
public protocol NotcholinoPlugin: NSObjectProtocol {
    /// Must equal `notcholinoPluginAPIVersion`
    var apiVersion: Int { get }
    /// Stable, lowercase identifier (e.g. "caffeinate"), also used as the install folder name
    var pluginIdentifier: String { get }
    var pluginName: String { get }
    var pluginVersion: String { get }
    var pluginAuthor: String { get }
    var pluginDescription: String { get }

    /// Name of an SF Symbol for the Control Center button. May change with the plugin state.
    var controlCenterIcon: String { get }
    /// Whether the plugin is currently doing something; the button is highlighted when true
    var isActive: Bool { get }
    /// Short text shown under the button name (e.g. "1h 20m"), or an empty string
    var statusText: String { get }

    /// Options shown when the button is clicked
    func menuItems() -> [[String: Any]]
    /// Called when the user picks an option
    func performMenuAction(_ id: String)

    /// Called before the plugin is removed: release resources here
    @objc optional func pluginWillUnload()
}
