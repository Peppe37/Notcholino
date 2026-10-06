import AppKit
import SwiftUI

class NotchWindowController: NSWindowController {
    
    init() {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        // Standard notch size for 14"/16" MacBook Pros
        let notchWidth: CGFloat = 200
        let notchHeight: CGFloat = 32
        
        let window = NSWindow(
            contentRect: NSRect(x: (screenWidth - notchWidth) / 2, y: (NSScreen.main?.frame.height ?? 900) - notchHeight, width: notchWidth, height: notchHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar // Float above the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false // We will handle mouse hover to expand the notch
        
        super.init(window: window)
        
        // Add a SwiftUI view to the window to render the dynamic notch capsule
        let hostingView = NSHostingView(rootView: NotchContentView())
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
    
    // Base notch dimensions
    let baseWidth: CGFloat = 190
    let baseHeight: CGFloat = 32
    
    var body: some View {
        ZStack {
            // The black squircle capsule
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 12, style: .continuous)
                .fill(Color.black)
                .frame(
                    width: isExpanded ? 350 : baseWidth + CGFloat(tuningWidth),
                    height: isExpanded ? 100 : baseHeight + CGFloat(tuningHeight)
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isExpanded)
            
            // Content inside the notch
            if isExpanded {
                HStack(spacing: 20) {
                    Image(systemName: "play.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.teal)
                    
                    VStack(alignment: .leading) {
                        Text("Notcholino")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Live Activities & More")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .frame(width: 350, height: 100)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .edgesIgnoringSafeArea(.all)
        .onHover { hovering in
            isHovering = hovering
            withAnimation {
                isExpanded = hovering
            }
        }
    }
}
