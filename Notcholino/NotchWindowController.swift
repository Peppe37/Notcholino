import AppKit
import SwiftUI

class NotchWindowController: NSWindowController {
    
    init() {
        guard let screen = NSScreen.main else {
            super.init(window: nil)
            return
        }
        
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height
        
        // Make the window large enough to hold the fully expanded notch.
        // It will be completely transparent, so it won't block the screen
        // except where the actual black notch is drawn.
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 150
        
        let windowRect = NSRect(
            x: (screenWidth - windowWidth) / 2,
            y: screenHeight - windowHeight,
            width: windowWidth,
            height: windowHeight
        )
        
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver // High enough to be above the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        // This is crucial: we want the window to ignore mouse events EXCEPT where our SwiftUI view actually draws pixels.
        // A simple way to do this in SwiftUI is to just let the transparent parts be ignored.
        // In AppKit, a clear window automatically ignores clicks in clear areas if ignoresMouseEvents is false.
        window.ignoresMouseEvents = false 
        
        super.init(window: window)
        
        let hostingView = NSHostingView(rootView: NotchContentView())
        // Allow the hosting view to have a clear background
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Notch UI

struct NotchContentView: View {
    @State private var isHovering = false
    @State private var isExpanded = false
    
    // Read user settings dynamically
    @AppStorage("notchWidth") private var tuningWidth: Double = 0
    @AppStorage("notchHeight") private var tuningHeight: Double = 0
    
    // Base notch dimensions for MacBooks. The physical notch is usually around 32pt high.
    // By pushing it to the very top edge with alignment: .top, it will connect perfectly.
    let baseWidth: CGFloat = 190
    let baseHeight: CGFloat = 32
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The black squircle capsule
                // We use cornerRadius only on the bottom, or just a uniform one that gets cut off by the screen edge
                RoundedRectangle(cornerRadius: isExpanded ? 24 : 12, style: .continuous)
                    .fill(Color.black)
                    .frame(
                        width: isExpanded ? 350 : baseWidth + CGFloat(tuningWidth),
                        height: isExpanded ? 100 : baseHeight + CGFloat(tuningHeight)
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
                    .shadow(color: .black.opacity(isExpanded ? 0.3 : 0), radius: 10, y: 5)
                
                // Content inside the notch
                if isExpanded {
                    HStack(spacing: 16) {
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.teal, .teal.opacity(0.3))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notcholino")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("Live Activities & More")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        
                        // Fake visual equalizer
                        HStack(spacing: 3) {
                            ForEach(0..<4) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.teal)
                                    .frame(width: 4, height: CGFloat.random(in: 10...20))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .frame(width: 350)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onHover { hovering in
                isHovering = hovering
                withAnimation {
                    isExpanded = hovering
                }
            }
            // Push it to the top
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Ensure the top edge is strictly 0 padding
        .padding(.top, 0)
    }
}
