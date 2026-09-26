import Foundation
import Testing
@testable import TrayFold

/// Covers the divider's pure logic: widths, menu titles, first-launch placement and
/// the "don't hide the chevron" guard. The real status item is never created here
/// (it would put a 5,000-pt item into this Mac's menu bar); it is checked by hand.
@MainActor
struct DividerControllerTests {
    /// A throwaway defaults domain, so tests never touch TrayFold's real settings.
    final class ScratchDefaults {
        let name = "TrayFoldTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }

        func position(_ autosaveName: String) -> Double? {
            defaults.object(forKey: DividerController.preferredPositionKey(autosaveName)) as? Double
        }
        func setPosition(_ value: Double, _ autosaveName: String) {
            defaults.set(value, forKey: DividerController.preferredPositionKey(autosaveName))
        }
    }

    let chevron = StatusBarController.autosaveName
    let divider = DividerController.autosaveName

    @Test func lengthsPerState() {
        #expect(DividerController.length(isExpanded: true) == 5_000)
        #expect(DividerController.length(isExpanded: false) == 12)
    }

    @Test func menuTitleSaysWhatClickingDoes() {
        #expect(StatusBarController.dividerTitle(isExpanded: true) == "Show Hidden Icons")
        #expect(StatusBarController.dividerTitle(isExpanded: false) == "Hide Icons")
    }

    /// AppKit reads and writes this exact key; a typo would silently do nothing.
    @Test func preferredPositionKeyMatchesAppKit() {
        #expect(DividerController.preferredPositionKey("TrayFoldDivider") == "NSStatusItem Preferred Position TrayFoldDivider")
    }

    @Test func freshInstallSeedsChevronThenDivider() {
        let scratch = ScratchDefaults()
        DividerController.seedPositions(in: scratch.defaults, chevron: chevron)
        #expect(scratch.position(chevron) == 0)
        #expect(scratch.position(divider) == 1)
    }

    @Test func dividerIsSeededJustLeftOfAPlacedChevron() {
        let scratch = ScratchDefaults()
        scratch.setPosition(546, chevron)
        DividerController.seedPositions(in: scratch.defaults, chevron: chevron)
        #expect(scratch.position(chevron) == 546)
        #expect(scratch.position(divider) == 547)
    }

    @Test func userPlacedDividerIsLeftAlone() {
        let scratch = ScratchDefaults()
        scratch.setPosition(546, chevron)
        scratch.setPosition(800, divider)
        DividerController.seedPositions(in: scratch.defaults, chevron: chevron)
        #expect(scratch.position(chevron) == 546)
        #expect(scratch.position(divider) == 800)
    }

    /// Positions count from the right edge, so "left of the chevron" means a bigger number.
    @Test func expandIsRefusedWhenItWouldHideTheChevron() {
        // Nothing stored yet: nothing to compare, so allow it.
        #expect(DividerController.isSafeToExpand(dividerPosition: nil, chevronPosition: 546))
        #expect(DividerController.isSafeToExpand(dividerPosition: 547, chevronPosition: nil))
        // Divider left of the chevron.
        #expect(DividerController.isSafeToExpand(dividerPosition: 547, chevronPosition: 546))
        // Divider dragged to the chevron's right (or onto the same spot).
        #expect(!DividerController.isSafeToExpand(dividerPosition: 500, chevronPosition: 546))
        #expect(!DividerController.isSafeToExpand(dividerPosition: 546, chevronPosition: 546))
    }

    /// The author's screen: 982 pt tall, menu bar 33 pt (y 949…982, AppKit's y grows upward).
    @Test func onlyClicksBelowTheMenuBarRefold() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func below(_ y: CGFloat) -> Bool {
            DividerController.isBelowMenuBar(CGPoint(x: 700, y: y), screenFrame: screen, menuBarHeight: 33)
        }
        #expect(!below(970))    // in the bar: ⌘-dragging an icon
        #expect(!below(949))    // bar's bottom edge
        #expect(below(948))     // just under it
        #expect(below(10))      // near the Dock
        // A second display to the right, with its own menu bar.
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        #expect(!DividerController.isBelowMenuBar(CGPoint(x: 2000, y: 1070), screenFrame: second, menuBarHeight: 24))
        #expect(DividerController.isBelowMenuBar(CGPoint(x: 2000, y: 1000), screenFrame: second, menuBarHeight: 24))
    }
}
