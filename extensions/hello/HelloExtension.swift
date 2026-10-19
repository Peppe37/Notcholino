// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// A tiny example extension: a page with a greeting and a button that asks Notchy's AI for a one-line joke.
/// Copy this folder, rename it, and change the class. Build and install it with scripts/dev-extension.sh.
@objc(HelloExtension)
final class HelloExtension: NSObject, NotcholinoExtension {
    var apiVersion: Int { notcholinoExtensionAPIVersion }
    var extensionIdentifier: String { "hello" }
    var extensionName: String { "Hello" }
    var extensionVersion: String { "0.1.0" }
    var extensionAuthor: String { "Notcholino" }
    var extensionDescription: String { "An example extension: a page in the notch that can ask Notchy's AI for a joke." }
    var extensionSymbol: String { "hand.wave.fill" }

    private var popup: (([String: Any]) -> Void)?
    private var ask: ((String, String?, @escaping (String?, String?) -> Void) -> Void)?
    private let label = NSTextField(labelWithString: "Hello from an extension.")

    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }
    func setAskHandler(_ handler: @escaping (String, String?, @escaping (String?, String?) -> Void) -> Void) { ask = handler }

    func makePageView() -> NSView {
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        let button = NSButton(title: "Tell me a joke", target: self, action: #selector(joke))
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 28, bottom: 10, right: 28)
        return stack
    }

    func makeSettingsView() -> NSView {
        let text = NSTextField(wrappingLabelWithString: "Nothing to set up here. This is where an extension puts its options.")
        text.frame = NSRect(x: 0, y: 0, width: 360, height: 60)
        return text
    }

    @objc private func joke() {
        guard let ask else { label.stringValue = "Notchy's AI is not available."; return }
        label.stringValue = "Thinking…"
        ask("Tell me a very short, clean joke.", "Answer with the joke only.") { [weak self] answer, error in
            self?.label.stringValue = answer ?? error ?? "No answer."
        }
    }
}
