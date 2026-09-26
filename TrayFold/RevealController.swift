import AppKit
import ApplicationServices
import os

/// Opens a folded menu bar item's real menu, then folds the bar back. One "reveal
/// session" per tray click:
/// 1. **revealing**: shrink the divider just enough that the item comes on-screen, and wait
///    until Accessibility reports it there (a menu opens under its item, so an off-screen
///    item's menu would open off-screen too);
/// 2. press the item (`AXPress`) on a background thread;
/// 3. **menuOpen**: check a few times a second until its menu, panel or popover closes;
/// 4. **refolding**: expand the divider again, back to **idle**.
/// Every failure (never on-screen, press error, the app quit, Accessibility revoked,
/// nothing opened) skips ahead to step 4, so the bar never stays unfolded.
///
/// The divider (hiding) and Accessibility (finding, pressing) come in as closures in
/// `System`: tests replace them, and macOS 27 may need a different way to hide items.
@MainActor
final class RevealController {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Reveal")

    enum State: Equatable, Sendable {
        case idle, revealing, menuOpen, refolding
    }

    /// How often and how long to check. The only polling in TrayFold, and only while a
    /// session runs: Accessibility sends no reliable "menu closed" signal for every kind of
    /// item (see the phase 5 plan), and each check costs about 1–30 ms of another app's time.
    enum Timing {
        /// Between checks that the item has reached the screen, for at most `revealAttempts`.
        static let revealInterval: Duration = .milliseconds(20)
        static let revealAttempts = 50
        /// Between checks that the menu is still open.
        static let openInterval: Duration = .milliseconds(200)
        /// Checks before giving up on anything opening (≈ 1.6 s): some items don't open a
        /// menu at all (Bitwarden shows its main window).
        static let graceAttempts = 8
        /// Checks before folding back even though something still looks open (≈ 5 minutes).
        static let maxOpenAttempts = 1_500
        /// How long macOS may still be moving items after a fold-back (measured: ~110 ms).
        static let settle: Duration = .milliseconds(250)
    }

    /// Everything a session does to the world outside this class.
    struct System {
        /// Shrinks the divider to a length, in points (the hiding layer).
        var shrinkDivider: @MainActor (CGFloat) -> Void
        /// Expands the divider again.
        var refold: @MainActor () -> Void
        // Accessibility. These block while the other app answers, so they run on a
        // background thread (`@Sendable`).
        /// Where the item is right now.
        var frame: @Sendable (MenuBarItem) -> CGRect?
        var press: @Sendable (MenuBarItem) -> AXError
        /// How many popup windows (panels, popovers) the item's app shows.
        var popupWindows: @Sendable (MenuBarItem) -> Int
        /// Whether the item's menu, panel or popover is showing, given the popup window
        /// count from before the press.
        var isShowingMenu: @Sendable (MenuBarItem, Int) -> Bool
        var sleep: @Sendable (Duration) async -> Void
    }

    private(set) var state = State.idle {
        didSet { onStateChange?(state) }
    }
    /// Called on every state change (used by the tests).
    var onStateChange: ((State) -> Void)?

    private let system: System
    /// The running session, if any.
    private var session: Task<Void, Never>?
    /// When the last session folded back; see `reveal(_:screen:targetMinX:)`.
    private var refoldedAt: ContinuousClock.Instant?

    init(system: System) {
        self.system = system
    }

    /// Reveals and presses `item`. A session already running is cancelled first and has
    /// folded back before this one starts (the user clicked another tray entry).
    /// - Parameters:
    ///   - screen: Frame of the screen with the menu bar.
    ///   - notch: The notch's x range; the item is moved just right of it if it can be.
    @discardableResult
    func open(_ item: MenuBarItem, screen: CGRect, notch: ClosedRange<CGFloat>?) -> Task<Void, Never> {
        let previous = session
        previous?.cancel()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await run(item, screen: screen, targetMinX: notch?.upperBound ?? .infinity)
        }
        session = task
        return task
    }

    /// Ends any session at once and folds back (TrayFold is quitting).
    func stop() {
        session?.cancel()
        refold(because: "TrayFold is quitting")
    }

    private func run(_ item: MenuBarItem, screen: CGRect, targetMinX: CGFloat) async {
        let started = ContinuousClock.now
        let name = item.owner.bundleID ?? item.owner.name
        state = .revealing
        guard await reveal(item, screen: screen, targetMinX: targetMinX) else {
            return refold(because: "\(name) never reached the screen")
        }
        // Superseded (another tray click, quitting) while revealing: never press an item
        // the user no longer asked for. A Control Center item would toggle something.
        guard !Task.isCancelled else { return refold(because: "cancelled") }
        let popupWindows = system.popupWindows
        let press = system.press
        let windowsBefore = await background { popupWindows(item) }
        guard !Task.isCancelled else { return refold(because: "cancelled") }
        // Its menu shows ~15–30 ms after this (measured), so this is the click-to-menu time.
        let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
        Self.logger.notice("Pressing \(name, privacy: .public) \(milliseconds, privacy: .public) ms after the click")
        let result = await background { press(item) }
        // `.cannotComplete`: the app is showing a menu and only answers once it closes.
        guard result == .success || result == .cannotComplete else {
            return refold(because: "pressing \(name) failed (\(result.rawValue))")
        }
        state = .menuOpen
        refold(because: await waitUntilClosed(item, windowsBefore: windowsBefore))
    }

    /// Brings the item on-screen; false if it never got there. An item that is on-screen
    /// already (under the notch, or all icons shown) is pressed in place. Otherwise tries a
    /// partial collapse, then a full one: once the bar overflows, macOS reorders items
    /// (measured), so the item may not land where the arithmetic says.
    private func reveal(_ item: MenuBarItem, screen: CGRect, targetMinX: CGFloat) async -> Bool {
        // A previous session may have just folded back: macOS takes ~110 ms to move the
        // items (measured), and until then Accessibility still reports the old places.
        if let refoldedAt {
            let wait = Timing.settle - (ContinuousClock.now - refoldedAt)
            if wait > .zero { await system.sleep(wait) }
        }
        // Where it is now, not where the tray last saw it (that may be out of date).
        let frame = system.frame
        guard let start = await background({ frame(item) }) else { return false }
        if MenuBarLayout.isOnScreen(start, screenFrame: screen) { return true }
        let collapsed = DividerController.Lengths.collapsed
        var lengths = [collapsed]
        if let partial = MenuBarLayout.revealLength(
            itemFrame: start, currentLength: DividerController.Lengths.expanded,
            targetMinX: targetMinX, minimum: collapsed, screenFrame: screen
        ), partial > collapsed {
            lengths.insert(partial, at: 0)
        }
        for length in lengths where !Task.isCancelled {
            system.shrinkDivider(length)
            if await waitUntilOnScreen(item, screen: screen) { return true }
        }
        return false
    }

    private func waitUntilOnScreen(_ item: MenuBarItem, screen: CGRect) async -> Bool {
        let frame = system.frame
        for attempt in 0 ..< Timing.revealAttempts {
            if Task.isCancelled { return false }
            if attempt > 0 { await system.sleep(Timing.revealInterval) }
            if let now = await background({ frame(item) }), MenuBarLayout.isOnScreen(now, screenFrame: screen) {
                return true
            }
        }
        return false
    }

    /// Waits while the item's menu is showing. Returns why it stopped waiting, for the log.
    private func waitUntilClosed(_ item: MenuBarItem, windowsBefore: Int) async -> String {
        let isShowingMenu = system.isShowingMenu
        var hasOpened = false
        for attempt in 0 ..< Timing.maxOpenAttempts {
            await system.sleep(Timing.openInterval)
            if Task.isCancelled { return "cancelled" }
            if await background({ isShowingMenu(item, windowsBefore) }) {
                hasOpened = true
            } else if hasOpened {
                return "its menu closed"
            } else if attempt + 1 >= Timing.graceAttempts {
                return "no menu opened"
            }
        }
        return "its menu stayed open too long"
    }

    /// Expands the divider again, once per session.
    private func refold(because reason: String) {
        guard state != .idle else { return }
        state = .refolding
        system.refold()
        refoldedAt = .now
        state = .idle
        Self.logger.notice("Reveal ended: \(reason, privacy: .public)")
    }

    /// Runs blocking Accessibility work off the main actor. `Task.detached` matters: a
    /// plain `Task` would inherit the main actor and freeze the menu bar while it waits.
    private func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}

// MARK: - The real system

extension RevealController.System {
    /// The real divider and Accessibility calls.
    @MainActor static func live(divider: DividerController) -> Self {
        Self(
            shrinkDivider: { divider.reveal(length: $0) },
            refold: { divider.endReveal() },
            frame: { $0.element.frame },
            press: { $0.element.press() },
            popupWindows: popupWindowCount,
            isShowingMenu: isShowingMenu,
            sleep: { try? await Task.sleep(for: $0) }
        )
    }

    /// The app's windows that aren't ordinary document windows: popovers and panels
    /// (measured: Slice and Control Center "AXSystemDialog", WPS "AXDialog"). Bitwarden's
    /// main window is an "AXStandardWindow" and doesn't count.
    static func popupWindowCount(_ item: MenuBarItem) -> Int {
        AXElement.application(pid: item.owner.pid).elements("AXWindows")
            .filter { $0.string("AXSubrole") != "AXStandardWindow" }
            .count
    }

    /// Whether the item's menu, panel or popover is showing. Three signals, because none
    /// was reliable alone when measured: an open menu marks its item selected and gives
    /// the item's menu child a size (it's 0 × 0 while closed); a panel or popover is a new
    /// window of the app.
    static func isShowingMenu(_ item: MenuBarItem, windowsBefore: Int) -> Bool {
        item.element.bool("AXSelected")
            || item.element.children.contains { $0.string("AXRole") == "AXMenu" && ($0.frame?.height ?? 0) > 0 }
            || popupWindowCount(item) > windowsBefore
    }
}
