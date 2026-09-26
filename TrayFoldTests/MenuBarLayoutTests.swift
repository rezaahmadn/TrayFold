import CoreGraphics
import Testing
@testable import TrayFold

/// Checks the pure layout rules with numbers from the author's 14" MacBook Pro:
/// a 1512-pt-wide screen whose notch covers x 665…850. `notchRange(of:)` on a real
/// `NSScreen` is checked by hand (CI machines have no notch).
struct MenuBarLayoutTests {
    let notch: ClosedRange<CGFloat> = 665...850

    /// An item 24 pt tall at `x`, like the ones Accessibility reports.
    func item(x: CGFloat, width: CGFloat = 36) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 24)
    }

    func visibility(_ frame: CGRect, divider: CGFloat? = nil, notch: ClosedRange<CGFloat>? = nil) -> MenuBarLayout.Visibility {
        MenuBarLayout.visibility(of: frame, dividerMinX: divider, notchRange: notch ?? self.notch, screenMinX: 0)
    }

    @Test func itemRightOfTheNotchAndDividerIsVisible() {
        #expect(visibility(item(x: 967, width: 47), divider: 930) == .visible)
    }

    @Test func itemPushedFarLeftByAnExpandedDividerIsHidden() {
        // Seen on the author's Mac: divider at x = -4075 (5002 pt wide), items beyond it.
        #expect(visibility(item(x: -4315, width: 234), divider: -4075) == .hiddenByDivider)
    }

    @Test func itemLeftOfACollapsedDividerCountsAsHidden() {
        // On screen right now, but the user placed it in the tray.
        #expect(visibility(item(x: 890), divider: 930) == .hiddenByDivider)
    }

    @Test func itemOffTheLeftEdgeWithoutADividerIsOffScreen() {
        #expect(visibility(item(x: -300)) == .offScreen)
    }

    @Test func itemPartlyUnderTheNotchIsUnderTheNotch() {
        #expect(visibility(item(x: 830, width: 40)) == .underNotch)
        #expect(visibility(item(x: 640, width: 40)) == .underNotch)
        #expect(visibility(item(x: 700)) == .underNotch)
    }

    @Test func itemTouchingTheNotchEdgeIsVisible() {
        #expect(visibility(item(x: 850)) == .visible)
        #expect(visibility(item(x: 629)) == .visible)   // ends exactly at 665
    }

    @Test func withoutANotchNothingIsUnderIt() {
        let frame = item(x: 700)
        #expect(MenuBarLayout.visibility(of: frame, dividerMinX: nil, notchRange: nil, screenMinX: 0) == .visible)
    }

    @Test func dividerWinsOverOffScreen() {
        #expect(visibility(item(x: -5016), divider: -4075) == .hiddenByDivider)
    }

    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func revealLength(x: CGFloat, target: CGFloat = 850) -> CGFloat? {
        MenuBarLayout.revealLength(itemFrame: item(x: x, width: 34), currentLength: 5_000, targetMinX: target, minimum: 12, screenFrame: screen)
    }

    /// Measured: shrinking the divider by d moves the items left of it right by exactly d.
    @Test func revealShrinksTheDividerJustEnough() {
        #expect(revealLength(x: -4101) == 49)          // 1Password lands at x 850
    }

    @Test func revealNeverGoesBelowTheCollapsedLength() {
        #expect(revealLength(x: -4167) == 12)          // WPS can't get that far right
        #expect(revealLength(x: -4101, target: .infinity) == 12)   // no notch: full collapse
    }

    @Test func noRevealForAnItemAlreadyOnScreen() {
        #expect(revealLength(x: 900) == nil)
        #expect(revealLength(x: 821) == nil)           // under the notch
    }

    @Test func onScreenMeansTheWholeItemIsInside() {
        #expect(!MenuBarLayout.isOnScreen(item(x: -30), screenFrame: screen))
        #expect(MenuBarLayout.isOnScreen(item(x: 0, width: 34), screenFrame: screen))
        #expect(MenuBarLayout.isOnScreen(item(x: 1478, width: 34), screenFrame: screen))
        #expect(!MenuBarLayout.isOnScreen(item(x: 1490, width: 34), screenFrame: screen))
    }

    @Test func notchRangeIsTheGapBetweenTheAreas() {
        let left = CGRect(x: 0, y: 950, width: 665, height: 32)
        let right = CGRect(x: 850, y: 950, width: 662, height: 32)
        #expect(MenuBarLayout.notchRange(leftArea: left, rightArea: right) == 665...850)
    }

    @Test func noNotchRangeWithoutBothAreasOrAGap() {
        let left = CGRect(x: 0, y: 950, width: 665, height: 32)
        let right = CGRect(x: 850, y: 950, width: 662, height: 32)
        #expect(MenuBarLayout.notchRange(leftArea: nil, rightArea: right) == nil)
        #expect(MenuBarLayout.notchRange(leftArea: left, rightArea: nil) == nil)
        #expect(MenuBarLayout.notchRange(leftArea: .zero, rightArea: .zero) == nil)
        #expect(MenuBarLayout.notchRange(leftArea: right, rightArea: left) == nil)
    }
}
