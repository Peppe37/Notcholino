// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import Vision

/// Notchy looking at the screen, only when asked. The text on the screen is read on the Mac first (Vision), and when there is
/// enough of it only that text goes to the AI, which costs far less than a picture. A picture is sent only when there is
/// little text, to the provider chosen for images.
enum NotchyScreen {
    struct Look { let text: String; let png: Data? }

    static func capture() async throws -> Look {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw NotchyAIError(message: "Allow Screen Recording for Notcholino in System Settings → Privacy & Security, then ask again.")
        }
        let content = try await SCShareableContent.current
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
            throw NotchyAIError(message: "No screen to look at.")
        }
        let config = SCStreamConfiguration()
        let scale = min(1, 2000 / CGFloat(max(display.width, display.height)))
        config.width = Int(CGFloat(display.width) * scale) * 2 / 2
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)

        let text = await recognise(image)
        let rep = NSBitmapImageRep(cgImage: image)
        let png = text.count >= 120 ? nil : rep.representation(using: .png, properties: [:])
        return Look(text: text, png: png)
    }

    private static func recognise(_ image: CGImage) async -> String {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                c.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
