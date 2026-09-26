import AppKit
import SwiftUI

/// What the tray popup shows: a grid of hidden menu bar items, or a short hint when
/// there are none. It only draws; `TrayController` decides what goes in it.
struct TrayView: View {
    let items: [MenuBarItem]
    /// Called with the entry the user clicked.
    let onSelect: (MenuBarItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 4) {
                    Text("Nothing folded away").font(.headline)
                    // Broken by hand: automatic wrapping split "⌘-drag" at its hyphen.
                    Text("Right-click ⌄ → Show Hidden Icons,\nthen ⌘-drag icons left of the divider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                let rows = TrayController.rows(items)
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row]) { item in
                                TrayCell(item: item) { onSelect(item) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

/// One entry: the owning app's icon with the item's short label under it.
private struct TrayCell: View {
    let item: MenuBarItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text(TrayController.label(for: item))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 64)
            .padding(4)
            // Hover highlight, so the grid reads as clickable.
            .background(isHovered ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 6))
            // Makes the whole cell clickable, not only the icon and text.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(TrayController.tooltip(for: item))
        .onHover { isHovered = $0 }
    }

    /// The app's own icon (live menu bar images would need Screen Recording).
    private var icon: NSImage {
        NSRunningApplication(processIdentifier: item.owner.pid)?.icon
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}
