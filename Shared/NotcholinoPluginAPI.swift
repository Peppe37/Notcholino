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
/// - `"info"`        (String)  alternatively, a read-only row: this is the label, with `"value"` (String) on the right
/// - `"stepper"`     (String)  alternatively, a number the user can change: this is the label. Needs `"id"` and `"value"` (Int),
///                   optional `"unit"` (String), `"min"`, `"max"` and `"step"` (Int, default 1). Minus and plus buttons repeat
///                   while held. Each change calls `performMenuAction("<id>=<new value>")`. (Notcholino 0.10.0 and later.)
/// - `"graph"`       ([Double]) alternatively, a small line graph of these values, drawn across the panel.
///                   Optional with it: `"caption"` (String, shown under the graph) and `"color"` (String, "#RRGGBB").
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
    /// Short state text (e.g. "1h 20m left"). It is shown in the plugin's options, not under the button:
    /// every button in the Control Center has the same size and a single label, its name.
    var statusText: String { get }

    /// Options shown when the button is clicked
    func menuItems() -> [[String: Any]]
    /// Called when the user picks an option
    func performMenuAction(_ id: String)

    /// Called before the plugin is removed: release resources here
    @objc optional func pluginWillUnload()

    // MARK: Optional: a richer Control Center button (added in Notcholino 0.8.0; older apps ignore these)

    /// A short text (like "42°") drawn in the button instead of the SF Symbol
    @objc optional var controlCenterLabel: String { get }
    /// Color of the button as "#RRGGBB". Without it the button is orange while active, grey otherwise.
    @objc optional var controlCenterTintColor: String { get }
    /// Implement this to make the button a simple switch: tapping it calls this instead of opening the options
    @objc optional func controlCenterButtonTapped()
}
