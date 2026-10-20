// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// The drawing in the notch: a small rectangle (the screen) with an arrow at the middle of each side and a dot in the centre.
/// The nine cells are not drawn: they are just where the pointer is. The one under it grows a little, and a soft preview shows
/// where the window will go.
struct SnapPage: View {
    @ObservedObject private var state = SnapState.shared
    static let size = CGSize(width: 280, height: 118)

    var body: some View {
        ZStack {
            screen
            if !state.dragging {
                Text(AXIsProcessTrusted() ? "Grab a window and bring it here" : "Allow Accessibility for Notcholino to use Snap")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .offset(y: 0)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var screen: some View {
        let w = Self.size.width, h = Self.size.height
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1)
            // Where the window will go
            if let zone = state.zone {
                let f = zone.fractions
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: f.width * (w - 12), height: f.height * (h - 12))
                    .position(x: 6 + (f.minX + f.width / 2) * (w - 12), y: 6 + (f.minY + f.height / 2) * (h - 12))
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: zone)
            }
            ForEach(SnapZone.allCases, id: \.self) { zone in
                symbol(zone)
                    .position(x: (CGFloat(zone.cell.col) + 0.5) / 3 * w, y: (CGFloat(zone.cell.row) + 0.5) / 3 * h)
            }
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func symbol(_ zone: SnapZone) -> some View {
        let active = state.zone == zone
        Group {
            switch zone {
            case .left: Image(systemName: "arrow.left")
            case .right: Image(systemName: "arrow.right")
            case .top: Image(systemName: "arrow.up")
            case .bottom: Image(systemName: "arrow.down")
            case .center: Circle().frame(width: 9, height: 9)
            default: Corner(zone: zone).stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 12, height: 12)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white.opacity(active ? 1 : 0.5))
        .scaleEffect(active ? 1.5 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: active)
    }
}

/// A small corner mark, for the four corner zones
struct Corner: Shape {
    let zone: SnapZone
    func path(in r: CGRect) -> Path {
        var p = Path()
        let left = zone == .topLeft || zone == .bottomLeft, top = zone == .topLeft || zone == .topRight
        let x = left ? r.minX : r.maxX, y = top ? r.minY : r.maxY
        p.move(to: CGPoint(x: x, y: top ? r.maxY : r.minY))
        p.addLine(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: left ? r.maxX : r.minX, y: y))
        return p
    }
}

/// Hosts the page and knows where its rectangle is on the screen, so the pointer can be turned into a zone
final class SnapHostingView: NSHostingView<SnapPage> {
    override func layout() {
        super.layout()
        SnapState.shared.register(self)
    }

    var rectOnScreen: CGRect? {
        guard let window else { return nil }
        let size = SnapPage.size
        let local = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        return window.convertToScreen(convert(local, to: nil))
    }
}

struct SnapSettingsView: View {
    @AppStorage("snapCenterAction") private var center = "fill"
    @AppStorage("snapGap") private var gap = 0.0
    @AppStorage("snapOpenMode") private var openMode = "shake"
    @AppStorage("snapHint") private var hint = true

    var body: some View {
        Form {
            Section {
                Text("Grab a window by its title bar and shake it from side to side: the notch opens. Bring the pointer to the rectangle: an arrow at the left or right puts the window on that half of the screen, up or down on the top or bottom half, a corner on that quarter, and the dot in the middle makes it fill the screen. Let go to place it.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("How it works") }
            Section {
                Picker("The notch opens", selection: $openMode) {
                    Text("When I shake the window").tag("shake")
                    Text("Every time I drag a window").tag("always")
                }
                .onChange(of: openMode) { SnapEngine.shared.shakeToOpen = $0 == "shake" }
                if openMode == "shake" {
                    Toggle("Show “Shake it!” when I pick up a window", isOn: $hint)
                        .onChange(of: hint) { SnapEngine.shared.showHint = $0 }
                }
                Picker("The dot in the middle", selection: $center) {
                    Text("Fills the screen").tag("fill")
                    Text("Centres the window").tag("center")
                }
                .onChange(of: center) { SnapEngine.shared.centerAction = SnapCenterAction(rawValue: $0) ?? .fill }
                LabeledContent("Space between windows") {
                    HStack {
                        Slider(value: $gap, in: 0...24, step: 2).frame(width: 160)
                        Text("\(Int(gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .onChange(of: gap) { SnapEngine.shared.gap = CGFloat($0) }
            } header: { Text("Options") }
            Section {
                if AXIsProcessTrusted() {
                    Label("Accessibility is allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Snap needs Accessibility to move windows", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Allow Accessibility") {
                        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                    }
                }
            } header: { Text("Permission") }
        }
        .formStyle(.grouped)
    }
}
