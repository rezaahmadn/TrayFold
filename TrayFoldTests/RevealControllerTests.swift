import ApplicationServices
import CoreGraphics
import Dispatch
import Synchronization
import Testing
@testable import TrayFold

/// Drives `RevealController` with a fake divider and fake Accessibility, so no real menu
/// bar item moves or opens. Numbers from the author's Mac: 1512-pt screen, notch at
/// x 665…850, 1Password at x -4101 behind a 5,000-pt divider. The real bar is checked by
/// hand (see the phase 5 report).
@MainActor
struct RevealControllerTests {
    /// A pretend menu bar. `Sendable` with a lock inside, because the controller asks the
    /// Accessibility closures from background threads.
    final class FakeBar: Sendable {
        struct Values {
            /// The divider's length; items move right by exactly what it shrinks.
            var length: CGFloat = DividerController.Lengths.expanded
            /// Only lengths at or below this bring the item on-screen (nil: any length
            /// works as the arithmetic says). Simulates macOS reordering a crowded bar.
            var worksAtOrBelow: CGFloat?
            /// The app is gone (or Accessibility is off): every question fails.
            var gone = false
            var pressResult = AXError.cannotComplete
            /// How many "is it still open?" checks answer yes (`Int.max`: stays open).
            var openChecks = 2
            // What happened, in order.
            var events: [String] = []
            var sleeps: [Duration] = []
            /// When set, the check just before the press stops at `gate` until the test
            /// lets it go, holding the session between "revealed" and "pressed".
            var holdBeforePress = false
            var isHeld = false
        }
        let values = Mutex(Values())
        let gate = DispatchSemaphore(value: 0)

        func update(_ change: (inout Values) -> Void) { values.withLock { change(&$0) } }
        var events: [String] { values.withLock { $0.events } }

        func system() -> RevealController.System {
            RevealController.System(
                shrinkDivider: { length in
                    self.update { $0.length = length; $0.events.append("shrink \(Int(length))") }
                },
                refold: {
                    self.update { $0.length = DividerController.Lengths.expanded; $0.events.append("refold") }
                },
                frame: { item in
                    self.values.withLock { values in
                        guard !values.gone else { return nil }
                        let x = item.frame.minX
                        let shrunk = DividerController.Lengths.expanded - values.length
                        let moves = values.worksAtOrBelow.map { values.length <= $0 } ?? true
                        return CGRect(x: moves ? x + shrunk : x, y: 4.5, width: item.frame.width, height: 24)
                    }
                },
                press: { item in
                    self.values.withLock { $0.events.append("press \(item.owner.name)"); return $0.pressResult }
                },
                popupWindows: { _ in
                    // Runs on a background thread, so blocking here doesn't stall the test.
                    if self.values.withLock({ $0.isHeld = $0.holdBeforePress; return $0.isHeld }) {
                        self.gate.wait()
                    }
                    return 0
                },
                isShowingMenu: { _, _ in
                    self.values.withLock { values in
                        guard values.openChecks > 0 else { return false }
                        if values.openChecks != .max { values.openChecks -= 1 }
                        return true
                    }
                },
                sleep: { duration in
                    self.update { $0.sleeps.append(duration) }
                    await Task.yield()
                }
            )
        }
    }

    static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    static func item(_ name: String = "1Password", x: CGFloat = -4101) -> MenuBarItem {
        MenuBarItem(
            id: "1/\(name)",
            owner: MenuBarItem.Owner(pid: 1, bundleID: "test.\(name)", name: name),
            title: nil, accessibilityDescription: nil, identifier: nil,
            frame: CGRect(x: x, y: 4.5, width: 34, height: 24),
            element: AXElement.application(pid: 1)
        )
    }

    /// Runs one session to the end and returns the states it went through.
    func run(_ bar: FakeBar, _ item: MenuBarItem = item()) async -> [RevealController.State] {
        let controller = RevealController(system: bar.system())
        var states: [RevealController.State] = []
        controller.onStateChange = { states.append($0) }
        await controller.open(item, screen: Self.screen, notch: 665...850).value
        return states
    }

    @Test func revealsJustEnoughPressesAndFoldsBackWhenTheMenuCloses() async {
        let bar = FakeBar()
        let states = await run(bar)
        // 5000 - (850 - -4101) = 49: 1Password lands exactly at the notch's right edge.
        #expect(bar.events == ["shrink 49", "press 1Password", "refold"])
        #expect(states == [.revealing, .menuOpen, .refolding, .idle])
    }

    @Test func itemAlreadyOnScreenIsPressedInPlace() async {
        let bar = FakeBar()
        _ = await run(bar, Self.item(x: 821))  // under the notch: its menu still shows
        #expect(bar.events == ["press 1Password", "refold"])
    }

    @Test func fallsBackToAFullCollapseWhenMacOSMovesTheItemElsewhere() async {
        let bar = FakeBar()
        bar.update { $0.worksAtOrBelow = DividerController.Lengths.collapsed }
        _ = await run(bar)
        #expect(bar.events == ["shrink 49", "shrink 12", "press 1Password", "refold"])
    }

    @Test func itemThatNeverReachesTheScreenIsNotPressed() async {
        let bar = FakeBar()
        bar.update { $0.worksAtOrBelow = 0 }   // never moves
        let states = await run(bar)
        #expect(bar.events == ["shrink 49", "shrink 12", "refold"])
        #expect(states == [.revealing, .refolding, .idle])
    }

    /// The app quit, or Accessibility was switched off: every question fails.
    @Test func vanishedItemFoldsBackWithoutPressing() async {
        let bar = FakeBar()
        bar.update { $0.gone = true }
        _ = await run(bar)
        #expect(bar.events == ["refold"])
    }

    @Test func pressErrorFoldsBack() async {
        let bar = FakeBar()
        bar.update { $0.pressResult = .invalidUIElement }
        let states = await run(bar)
        #expect(bar.events == ["shrink 49", "press 1Password", "refold"])
        #expect(!states.contains(.menuOpen))
    }

    /// Apps showing a panel (Control Center, WPS) answer at once.
    @Test func successCountsAsPressedToo() async {
        let bar = FakeBar()
        bar.update { $0.pressResult = .success }
        #expect(await run(bar).contains(.menuOpen))
    }

    /// Bitwarden shows its main window instead of a menu.
    @Test func foldsBackAfterAGraceTimeWhenNothingOpens() async {
        let bar = FakeBar()
        bar.update { $0.openChecks = 0 }
        _ = await run(bar)
        let openChecks = bar.values.withLock { $0.sleeps.filter { $0 == RevealController.Timing.openInterval }.count }
        #expect(openChecks == RevealController.Timing.graceAttempts)
        #expect(bar.events.last == "refold")
    }

    @Test func anotherEntryFoldsTheFirstBackBeforeRevealingAgain() async {
        let bar = FakeBar()
        bar.update { $0.openChecks = .max }     // the first menu stays open
        let controller = RevealController(system: bar.system())
        let first = controller.open(Self.item("1Password"), screen: Self.screen, notch: 665...850)
        while controller.state != .menuOpen { await Task.yield() }
        let second = controller.open(Self.item("Docker", x: 978), screen: Self.screen, notch: 665...850)
        await first.value
        await second.value
        #expect(bar.events == ["shrink 49", "press 1Password", "refold", "press Docker", "refold"])
        // The second session waited for macOS to move the items back first.
        let settle = RevealController.Timing.settle
        #expect(bar.values.withLock { $0.sleeps.contains { $0 > settle - .milliseconds(50) && $0 <= settle } })
    }

    @Test func stopFoldsBackOnce() async {
        let bar = FakeBar()
        bar.update { $0.openChecks = .max }
        let controller = RevealController(system: bar.system())
        let session = controller.open(Self.item(), screen: Self.screen, notch: 665...850)
        while controller.state != .menuOpen { await Task.yield() }
        controller.stop()
        #expect(controller.state == .idle)
        await session.value
        #expect(bar.events == ["shrink 49", "press 1Password", "refold"])
    }

    /// Waits until a session is held between reveal and press (see `holdBeforePress`).
    func waitUntilHeld(_ bar: FakeBar) async {
        while !bar.values.withLock({ $0.isHeld }) { await Task.yield() }
    }

    /// A second tray click lands while the first item is revealed but not yet pressed:
    /// the first item must never be pressed (a Control Center item would toggle).
    @Test func supersededItemIsNeverPressed() async {
        let bar = FakeBar()
        bar.update { $0.holdBeforePress = true }
        let controller = RevealController(system: bar.system())
        let first = controller.open(Self.item("Wi-Fi", x: 1226), screen: Self.screen, notch: 665...850)
        await waitUntilHeld(bar)
        bar.update { $0.holdBeforePress = false }
        let second = controller.open(Self.item("Sound", x: 1264), screen: Self.screen, notch: 665...850)
        bar.gate.signal()
        await first.value
        await second.value
        #expect(bar.events == ["refold", "press Sound", "refold"])
    }

    /// Quitting while an item is revealed but not yet pressed.
    @Test func stopBeforeThePressMeansNoPress() async {
        let bar = FakeBar()
        bar.update { $0.holdBeforePress = true }
        let controller = RevealController(system: bar.system())
        let session = controller.open(Self.item(), screen: Self.screen, notch: 665...850)
        await waitUntilHeld(bar)
        controller.stop()
        bar.gate.signal()
        await session.value
        #expect(bar.events == ["shrink 49", "refold"])
        #expect(controller.state == .idle)
    }
}
