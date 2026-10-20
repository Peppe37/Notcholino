// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import Foundation

/// For the demo video only, and only in a debug build (never in what is released): the video's script (scripts/demo) posts a
/// notification and Notchy plays a made-up answer, so the video shows Notchy's real interface without anyone's key, voice or data.
///   "com.giuseppe.Notcholino.demo" with userInfo ["think": seconds, "reply": "text"]
enum NotchyDemo {
    private static var observer: NSObjectProtocol?

    static func listen() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.giuseppe.Notcholino.demo"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            NotchyAssistant.shared.demoReply(thinking: (info["think"] as? NSNumber)?.doubleValue ?? 1.6, text: info["reply"] as? String ?? "")
        }
    }
}
#endif
