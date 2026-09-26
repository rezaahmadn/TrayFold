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
    private let reveal: RevealController
    private let liveIcons: LiveIcons
    private let popover = NSPopover()
    /// Hosts the SwiftUI grid. Its `rootView` is replaced whenever the list changes.
    private let content = NSHostingController(rootView: TrayView(items: [], onSelect: { _ in }))
    /// Watches clicks in other apps while the popup is open; see `toggle(relativeTo:)`.
    private let outsideClicks = OutsideClickMonitor()

    init(store: MenuBarItemStore, divider: DividerController, reveal: RevealController, liveIcons: LiveIcons) {
        self.store = store
        self.divider = divider
        self.reveal = reveal
        self.liveIcons = liveIcons
        // The popup takes the grid's own size and follows it as rows come and go.
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = false
    }

    /// Opens the popup under `button` (the chevron), or closes it if it's open.
    func toggle(relativeTo button: NSView) {
        if popover.isShown { return close() }
        // Live images are drawn for the menu bar, whose light or dark look follows the
        // wallpaper, not the system setting; the chevron has the bar's look. Matching it
        // keeps black glyphs off a dark popup. Otherwise the popup follows the system.
        popover.appearance = liveIcons.isActive ? button.effectiveAppearance : nil
        render()
        // TrayFold never becomes the active app (the user's app keeps focus), so
        // `.transient` doesn't hear about clicks elsewhere. A global monitor does.
        outsideClicks.start([.leftMouseDown, .rightMouseDown]) { [weak self] in self?.close() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let clicked = NSApp.currentEvent?.timestamp {
            let milliseconds = Int(((ProcessInfo.processInfo.systemUptime - clicked) * 1000).rounded())
            Self.logger.info("Tray opened \(milliseconds, privacy: .public) ms after the click")
        }
        // Items may have moved or appeared since the last scan (~20 ms when warm).
        Task {
            await store.refresh()
            liveIcons.forgetAll(except: store.items)
            // The user may have closed the popup meanwhile: then there's nothing to redraw
            // or capture for.
            guard popover.isShown, let screen = NSScreen.screens.first else { return }
            let items = render()
            // Only items that are on-screen right now (under the notch, or all icons shown);
            // usually none, and then nothing is captured.
            if await liveIcons.capture(items, screen: screen.frame), popover.isShown { render() }
        }
    }

    func close() {
        popover.performClose(nil)
        outsideClicks.stop()
    }

    /// Called when the store's items change; redraws only while the popup is open.
    func itemsChanged() {
        if popover.isShown { render() }
    }

    /// Where every tray click ends up: opens the item's own menu.
    func activate(_ item: MenuBarItem) {
        close()
        Self.logger.notice("Tray entry clicked: \(item.owner.bundleID ?? item.owner.name, privacy: .public)")
        // The click inside the popup made TrayFold the active app (measured). Hiding it
        // hands focus back to the app the user was in, so typing goes where it went before.
        // The switch takes ~30 ms; the item needs ~110 ms to reach the screen, so it's done
        // before the item's menu opens.
        if NSApp.isActive { NSApp.hide(nil) }
        guard let screen = NSScreen.screens.first else { return }
        reveal.open(item, screen: screen.frame, notch: MenuBarLayout.notchRange(of: screen))
    }

    /// Recomputes which items are hidden and hands them to the grid.
    /// Returns the items it listed.
    @discardableResult
    private func render() -> [MenuBarItem] {
        // Accessibility measures x from the primary display (the notched one on a MacBook).
        guard let screen = NSScreen.screens.first else { return [] }
        let items = Self.foldedItems(
            store.items,
            dividerMinX: divider.screenMinX,
            notchRange: MenuBarLayout.notchRange(of: screen),
            screenMinX: screen.frame.minX
        )
        content.rootView = TrayView(items: items, liveImages: liveIcons.images) { [weak self] item in self?.activate(item) }
        return items
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
