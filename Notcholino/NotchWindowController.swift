import AppKit
import SwiftUI

class NotchWindowController: NSWindowController {
    
    init() {
        // Create a borderless, transparent window that sits above the status bar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar // or .screenSaver to be above everything
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true // Only the notch area will receive mouse events later via tracking areas
        
        super.init(window: window)
        
        // Position window at the top center of the screen
        if let screen = NSScreen.main {
            let screenRect = screen.frame
            let windowRect = window.frame
            let newOrigin = NSPoint(
                x: (screenRect.width - windowRect.width) / 2,
                y: screenRect.height - windowRect.height
            )
            window.setFrameOrigin(newOrigin)
        }
        
        // Add a SwiftUI view to the window
        let hostingView = NSHostingView(rootView: NotchView())
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct NotchView: View {
    var body: some View {
        // Placeholder for the actual notch UI
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black)
            .frame(width: 200, height: 40)
            // Ensure this aligns with the physical notch on MacBooks
            .edgesIgnoringSafeArea(.all)
    }
}
