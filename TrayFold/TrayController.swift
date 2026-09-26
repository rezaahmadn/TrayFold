import AppKit
import SwiftUI
import os

/// Owns the tray: the popup under the chevron that lists every menu bar item the user
/// can't see right now (folded away by the divider, under the notch, or off-screen).
/// It shows the last known items at once, then rescans and updates in place.
@MainActor
final class TrayController {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Tray")

    /// Widest the grid gets before it adds another row, like the Windows tray.
    static let maxColumns = 5

    private let store: MenuBarItemStore
    private let divider: DividerController
    private let popover = NSPopover()
    /// Hosts the SwiftUI grid. Its `rootView` is replaced whenever the list changes.
    private let content = NSHostingController(rootView: TrayView(items: [], onSelect: { _ in }))
    /// Watches clicks in other apps while the popup is open; see `toggle(relativeTo:)`.
    private var clickMonitor: Any?

    init(store: MenuBarItemStore, divider: DividerController) {
        self.store = store
        self.divider = divider
        // The popup takes the grid's own size and follows it as rows come and go.
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = false
    }

    /// Opens the popup under `button` (the chevron), or closes it if it's open.
    func toggle(relativeTo button: NSView) {
        if popover.isShown { return close() }
        render()
        // TrayFold never becomes the active app (the user's app keeps focus), so
        // `.transient` doesn't hear about clicks elsewhere. A global monitor does: it sees
        // only other apps' clicks and, for mouse clicks, needs no extra permission.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // AppKit calls this on the main thread; tell Swift so.
                MainActor.assumeIsolated { self?.close() }
            }
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let clicked = NSApp.currentEvent?.timestamp {
            let milliseconds = Int(((ProcessInfo.processInfo.systemUptime - clicked) * 1000).rounded())
            Self.logger.info("Tray opened \(milliseconds, privacy: .public) ms after the click")
        }
        // Items may have moved or appeared since the last scan (~20 ms when warm).
        Task {
            await store.refresh()
            render()
        }
    }

    func close() {
        popover.performClose(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Called when the store's items change; redraws only while the popup is open.
    func itemsChanged() {
        if popover.isShown { render() }
    }

    /// Where every tray click ends up.
    func activate(_ item: MenuBarItem) {
        close()
        Self.logger.notice("Tray entry clicked: \(item.owner.bundleID ?? item.owner.name, privacy: .public)")
        // Phase 5: collapse the divider, wait until the item is on-screen, press it
        // (AXPress, off the main actor), and fold it away again once its menu closes.
    }

    /// Recomputes which items are hidden and hands them to the grid.
    private func render() {
        // Accessibility measures x from the primary display (the notched one on a MacBook).
        guard let screen = NSScreen.screens.first else { return }
        let items = Self.foldedItems(
            store.items,
            dividerMinX: divider.screenMinX,
            notchRange: MenuBarLayout.notchRange(of: screen),
            screenMinX: screen.frame.minX
        )
        content.rootView = TrayView(items: items) { [weak self] item in self?.activate(item) }
    }

    // MARK: - Pure helpers (unit-tested without a menu bar)

    /// The items the tray lists: every one that isn't `.visible` (see
    /// `MenuBarLayout.visibility`), left to right as in the menu bar.
    static func foldedItems(
        _ items: [MenuBarItem], dividerMinX: CGFloat?, notchRange: ClosedRange<CGFloat>?, screenMinX: CGFloat
    ) -> [MenuBarItem] {
        items
            .filter { MenuBarLayout.visibility(of: $0.frame, dividerMinX: dividerMinX, notchRange: notchRange, screenMinX: screenMinX) != .visible }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The short text under an entry's icon. Control Center's items share one app icon,
    /// so this is what tells them apart. First match wins: the item's own text in the
    /// menu bar ("25:00"), then what VoiceOver reads up to the first comma
    /// ("Wi‑Fi, connected, 3 bars" → "Wi‑Fi"), then the app's name.
    static func label(for item: MenuBarItem) -> String {
        if let title = item.title { return title }
        if let firstPart = item.accessibilityDescription?.split(separator: ",").first { return String(firstPart) }
        return item.owner.name
    }

    /// Shown when the pointer rests on an entry: the app's name plus the item's full
    /// text, for example "Control Center: Wi‑Fi, connected, 3 bars".
    static func tooltip(for item: MenuBarItem) -> String {
        guard let detail = item.title ?? item.accessibilityDescription, detail != item.owner.name else {
            return item.owner.name
        }
        return "\(item.owner.name): \(detail)"
    }

    /// Splits entries into rows of the grid: 3 → [3], 6 → [5, 1], 12 → [5, 5, 2].
    static func rows<Element>(_ elements: [Element], columns: Int = maxColumns) -> [[Element]] {
        stride(from: 0, to: elements.count, by: columns).map {
            Array(elements[$0 ..< min($0 + columns, elements.count)])
        }
    }
}
