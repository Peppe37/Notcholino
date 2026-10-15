// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Vision

/// Reader copies the text out of any part of your screen: click the button, drag over the text, and it lands in the
/// clipboard (images, videos, PDFs, a window that doesn't let you select, anything you can see).
///
/// It takes the picture with the system's own screenshot tool, so macOS asks for Screen Recording the first time, and reads
/// it on your Mac with the built-in text recognition. The picture is deleted right away and nothing is sent anywhere.
@objc(ReaderPlugin)
final class ReaderPlugin: NSObject, NotcholinoPlugin {

    // MARK: Plugin info

    var apiVersion: Int { notcholinoPluginAPIVersion }
    var pluginIdentifier: String { "reader" }
    var pluginName: String { "Reader" }
    var pluginVersion: String {
        Bundle(for: ReaderPlugin.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    var pluginAuthor: String { "Giuseppe" }
    var pluginDescription: String { "Copy the text out of any part of your screen: drag over it and it is in your clipboard." }

    // MARK: State

    private var working = false
    private var popup: (([String: Any]) -> Void)?

    func setPopupHandler(_ handler: @escaping ([String: Any]) -> Void) { popup = handler }

    // MARK: Control Center

    var isActive: Bool { working }
    var controlCenterIcon: String { "text.viewfinder" }
    var statusText: String { working ? "Drag over the text" : "" }
    func menuItems() -> [[String: Any]] { [] }
    func performMenuAction(_ id: String) {}

    /// The button is a switch: one click starts the selection
    func controlCenterButtonTapped() {
        guard !working else { return }
        working = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notcholino-reader-\(UUID().uuidString).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: you choose the area (Esc cancels), -x: no shutter sound
        capture.arguments = ["-i", "-x", file.path]
        capture.terminationHandler = { [weak self] _ in
            defer { try? FileManager.default.removeItem(at: file) }
            guard FileManager.default.fileExists(atPath: file.path) else {
                DispatchQueue.main.async { self?.working = false }   // cancelled
                return
            }
            let text = Self.recognizeText(in: file)
            DispatchQueue.main.async {
                self?.working = false
                self?.finish(with: text)
            }
        }
        do { try capture.run() } catch {
            working = false
            popup?(["title": "Could not start", "subtitle": "The screenshot tool did not open", "icon": "exclamationmark.triangle.fill", "color": "#FF9F0A"])
        }
    }

    private func finish(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            popup?(["title": "No text found", "subtitle": "Try a closer area", "icon": "text.viewfinder", "color": "#FF9F0A"])
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        let words = trimmed.split { $0.isWhitespace }.count
        popup?(["title": "Text copied", "subtitle": "\(words) word\(words == 1 ? "" : "s")", "icon": "doc.on.clipboard", "color": "#30D158"])
    }

    // MARK: Reading the picture

    private static func recognizeText(in file: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(url: file, options: [:])
        guard (try? handler.perform([request])) != nil, let results = request.results else { return "" }
        return results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
