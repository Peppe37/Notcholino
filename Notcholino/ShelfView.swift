import SwiftUI

/// The shelf panel of the notch: a row of the files waiting there, to drag out whenever you like
struct ShelfNotchView: View {
    @ObservedObject private var shelf = ShelfManager.shared
    var dropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shelf")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                if !shelf.items.isEmpty {
                    Text("\(shelf.items.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear") { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { shelf.removeAll() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)

            if shelf.items.isEmpty && shelf.pending == 0 {
                dropHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in ShelfTile(item: item) }
                        if shelf.pending > 0 {
                            ProgressView().controlSize(.small).frame(width: 76, height: 76)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(height: 100)
            }
            Spacer(minLength: 0)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(dropTargeted ? 0.55 : 0), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        )
    }

    private var dropHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .regular))
            Text("Drop files here")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject private var shelf = ShelfManager.shared
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = shelf.thumbnails[item.id] {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if hovered {
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { shelf.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
            }
            Text(item.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onAppear { shelf.loadThumbnail(for: item) }
        // Dragging out gives the file itself; it also stays on the shelf
        .onDrag {
            shelf.draggingOut = true
            return NSItemProvider(contentsOf: shelf.url(for: item)) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(shelf.url(for: item)) }
        .help("Drag it where you need it. Double-click to open.")
    }
}
