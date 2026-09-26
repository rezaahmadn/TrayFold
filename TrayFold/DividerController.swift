import AppKit
import os

/// Owns the divider: a second menu bar item that sits just left of the chevron.
///
/// The trick (the same one Ice and Thaw use) is the item's width. macOS lays out
/// status items from right to left, so when the divider is made thousands of
/// points wide, every item to its left is pushed past the left edge of the screen.
/// The user chooses what to hide by ⌘-dragging icons to the left of the divider
/// while it is collapsed (a thin line), which is ordinary macOS behavior.
@MainActor
final class DividerController: NSObject {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Divider")

    /// macOS remembers where the user ⌘-dragged an item with this name.
    static let autosaveName = "TrayFoldDivider"

    /// Widths of the divider's status item, in points.
    enum Lengths {
        /// Just wide enough for the separator line.
        static let collapsed: CGFloat = 12
        /// Wider than the screen, so everything to the divider's left ends up
        /// off-screen. macOS 26 caps a status item near this width anyway (asked
        /// for 10,000 pt, its window came out 5,016 pt wide), so asking for more
        /// would change nothing.
        static let expanded: CGFloat = 5_000
    }

    /// `true` while items to the left are pushed off-screen (the default).
    private(set) var isExpanded = false

    private let statusItem: NSStatusItem
    private let chevronAutosaveName: String
    private let defaults: UserDefaults
    /// Watches clicks in other apps while collapsed; see `watchForClickOutside()`.
    private var clickMonitor: Any?

    /// Create before the chevron's status item, so `seedPositions` runs before
    /// macOS reads either item's stored position.
    init(chevronAutosaveName: String, defaults: UserDefaults = .standard) {
        self.chevronAutosaveName = chevronAutosaveName
        self.defaults = defaults
        Self.seedPositions(in: defaults, chevron: chevronAutosaveName)
        statusItem = NSStatusBar.system.statusItem(withLength: Lengths.collapsed)
        super.init()
        statusItem.autosaveName = Self.autosaveName
        // No `.removalAllowed`: macOS refuses to let the user ⌘-drag it out of the bar.
        statusItem.behavior = []
        statusItem.button?.target = self
        statusItem.button?.action = #selector(dividerClicked)
        expand()
    }

    /// The divider's left edge in screen points, or `nil` until macOS has placed the
    /// item on a screen (a fraction of a second after launch). Same x axis as
    /// Accessibility positions on the main display: while expanded, any item whose
    /// right edge is at or left of this value is off-screen.
    var screenMinX: CGFloat? {
        guard let window = statusItem.button?.window, window.screen != nil else { return nil }
        return window.frame.minX
    }

    /// Pushes everything left of the divider off-screen.
    func expand() {
        guard Self.isSafeToExpand(
            dividerPosition: storedPosition(Self.autosaveName),
            chevronPosition: storedPosition(chevronAutosaveName)
        ) else {
            // Expanding now would push the chevron off-screen too, leaving no way back.
            Self.logger.error("Not hiding icons: the divider is right of the chevron. ⌘-drag it back to the chevron's left.")
            collapse()
            // Re-folding on a click would only fail again, once per click.
            stopWatchingClicks()
            return
        }
        stopWatchingClicks()
        isExpanded = true
        statusItem.length = Self.length(isExpanded: true)
        guard let button = statusItem.button else { return }
        button.image = nil
        // While expanded, the (mostly off-screen) button also covers the empty menu
        // bar left of the chevron. A disabled cell ignores clicks there instead of
        // highlighting. `isHighlighted = false` stops a brief flash on expansion.
        button.cell?.isEnabled = false
        button.isHighlighted = false
        Self.logger.notice("Divider expanded (icons hidden)")
    }

    /// Shrinks the divider to a thin line, bringing hidden items back on-screen.
    func collapse() {
        isExpanded = false
        statusItem.length = Self.length(isExpanded: false)
        guard let button = statusItem.button else { return }
        button.cell?.isEnabled = true
        button.image = Self.separatorImage()
        // Draws the line dimmed, so it reads as a guide rather than a button.
        button.appearsDisabled = true
        Self.logger.notice("Divider collapsed (icons shown)")
        watchForClickOutside()
    }

    /// Safety net for a crowded bar: with every icon shown, macOS may drop TrayFold's own
    /// chevron and divider out of sight, leaving no button to fold them back. So the
    /// first click below the menu bar (the user is done ⌘-dragging) folds everything away.
    /// A global monitor sees only other apps' clicks (never TrayFold's menu or popup) and,
    /// for mouse clicks, needs no extra permission. Mouse-*up*, so a ⌘-drag that ends in
    /// the bar doesn't count. It exists only while collapsed.
    private func watchForClickOutside() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            // AppKit calls this on the main thread; tell Swift so.
            MainActor.assumeIsolated {
                let point = NSEvent.mouseLocation
                // No screen contains the very top edge of the menu bar: count it as the bar.
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
                // The space macOS keeps free for the bar (33 pt with a notch); the nominal
                // thickness is only a floor, for a bar set to hide automatically.
                let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
                if Self.isBelowMenuBar(point, screenFrame: screen.frame, menuBarHeight: barHeight) {
                    Self.logger.notice("Clicked outside the menu bar while collapsed: folding icons away")
                    self?.expand()
                }
            }
        }
    }

    private func stopWatchingClicks() {
        guard let clickMonitor else { return }
        NSEvent.removeMonitor(clickMonitor)
        self.clickMonitor = nil
    }

    /// Switches between `expand()` and `collapse()`.
    func toggle() {
        isExpanded ? collapse() : expand()
    }

    /// Clicking the collapsed line folds the icons away again. (While expanded the
    /// cell is disabled, so this never fires then.)
    @objc private func dividerClicked() {
        expand()
    }

    /// Where macOS last stored an item's place, if it has one.
    private func storedPosition(_ autosaveName: String) -> Double? {
        defaults.object(forKey: Self.preferredPositionKey(autosaveName)) as? Double
    }

    // MARK: - Pure helpers (unit-tested without a menu bar)

    /// The status item width for each state.
    static func length(isExpanded: Bool) -> CGFloat {
        isExpanded ? Lengths.expanded : Lengths.collapsed
    }

    /// The `UserDefaults` key where macOS stores an item's place in the menu bar.
    /// macOS writes it itself whenever the user ⌘-drags the item. The value is the
    /// distance from the screen's right edge: bigger means further left.
    /// `nonisolated`: plain string work, callable from any thread.
    nonisolated static func preferredPositionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// Makes a first launch put the divider immediately left of the chevron.
    ///
    /// macOS places a status item it has never seen at the far left of the icons,
    /// which on a crowded, notched bar can be under the notch. Writing a starting
    /// position before the item is created avoids that (Ice and Thaw do the same).
    /// Runs only while the divider has no stored position, so it never undoes a
    /// place the user chose by ⌘-dragging.
    static func seedPositions(in defaults: UserDefaults, chevron: String) {
        let dividerKey = preferredPositionKey(autosaveName)
        let chevronKey = preferredPositionKey(chevron)
        guard defaults.object(forKey: dividerKey) == nil else { return }
        if defaults.object(forKey: chevronKey) == nil {
            // Fresh install: the rightmost slot next to Apple's own items is always visible.
            defaults.set(0.0, forKey: chevronKey)
        }
        let dividerPosition = defaults.double(forKey: chevronKey) + 1
        defaults.set(dividerPosition, forKey: dividerKey)
        logger.notice("Seeded divider position \(dividerPosition, privacy: .public)")
    }

    /// Whether expanding keeps the chevron on-screen: the divider must be left of
    /// it, which means a bigger stored position. If either position is unknown,
    /// there is nothing to compare, so it counts as safe.
    static func isSafeToExpand(dividerPosition: Double?, chevronPosition: Double?) -> Bool {
        guard let dividerPosition, let chevronPosition else { return true }
        return dividerPosition > chevronPosition
    }

    /// Whether a click at `point` (AppKit screen coordinates: y grows upward) landed
    /// below the menu bar at the top of `screenFrame`.
    static func isBelowMenuBar(_ point: CGPoint, screenFrame: CGRect, menuBarHeight: CGFloat) -> Bool {
        point.y < screenFrame.maxY - menuBarHeight
    }

    /// A thin vertical line, drawn as a template image so macOS tints it to match
    /// a light or dark menu bar.
    private static func separatorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        // VoiceOver reads this instead of describing the picture.
        image.accessibilityDescription = "TrayFold divider"
        return image
    }
}
