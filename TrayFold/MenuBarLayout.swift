import AppKit

/// Where menu bar items sit relative to the screen edge, the notch and TrayFold's
/// divider. Pure functions of x positions, so tests can check them without a menu bar.
/// Only x matters: AppKit and Accessibility share the same x axis (they differ in y).
enum MenuBarLayout {
    /// Whether the user can see (and click) a menu bar item right now.
    enum Visibility: Equatable, Sendable {
        /// On screen, clear of the notch.
        case visible
        /// Left of TrayFold's divider, which means "in the tray", whether or not the
        /// divider is currently expanded and pushing it off-screen.
        case hiddenByDivider
        /// Overlapping the camera notch, where macOS doesn't draw it.
        case underNotch
        /// Past the left edge of the screen, with no divider involved.
        case offScreen
    }

    /// Classifies an item. Rules, first match wins:
    /// 1. its centre is left of `dividerMinX` → `.hiddenByDivider`;
    /// 2. its centre is left of `screenMinX` → `.offScreen`;
    /// 3. any part of it is inside `notchRange` → `.underNotch`;
    /// 4. otherwise → `.visible`.
    /// - Parameters:
    ///   - frame: The item's frame (`MenuBarItem.frame`).
    ///   - dividerMinX: Left edge of TrayFold's divider item; nil when there is no divider.
    ///   - notchRange: The notch's x range, from `notchRange(of:)`; nil without a notch.
    ///   - screenMinX: Left edge of the screen the menu bar is on.
    static func visibility(
        of frame: CGRect,
        dividerMinX: CGFloat?,
        notchRange: ClosedRange<CGFloat>?,
        screenMinX: CGFloat
    ) -> Visibility {
        if let dividerMinX, frame.midX < dividerMinX { return .hiddenByDivider }
        if frame.midX < screenMinX { return .offScreen }
        // Strict comparisons: an item that only touches the notch's edge is still visible.
        if let notchRange, frame.maxX > notchRange.lowerBound, frame.minX < notchRange.upperBound {
            return .underNotch
        }
        return .visible
    }

    /// The x range hidden by the notch: the gap between the two unobscured areas beside
    /// it, for example 665...850 on a 14" MacBook Pro. nil when either area is missing or
    /// empty (a screen without a notch), or when they don't leave a gap.
    static func notchRange(leftArea: CGRect?, rightArea: CGRect?) -> ClosedRange<CGFloat>? {
        guard let leftArea, let rightArea, !leftArea.isEmpty, !rightArea.isEmpty,
              leftArea.maxX < rightArea.minX else { return nil }
        return leftArea.maxX...rightArea.minX
    }

    /// How long the divider should be so the item at `itemFrame` comes on-screen for a
    /// press, or nil when no shrinking is needed (the item is already on-screen).
    ///
    /// Shrinking the divider by d points moves every item to its left right by exactly d
    /// (measured). The item is moved until its left edge reaches `targetMinX` (the notch's
    /// right edge), but never shorter than `minimum` (the collapsed divider): an item that
    /// can't get that far stays wherever a collapsed divider leaves it, which is still
    /// on-screen, under or left of the notch, where its menu opens just as well.
    /// - Parameters:
    ///   - itemFrame: The item's frame, measured while the divider is `currentLength` long.
    ///   - screenFrame: The screen the menu bar is on.
    static func revealLength(
        itemFrame: CGRect, currentLength: CGFloat, targetMinX: CGFloat, minimum: CGFloat, screenFrame: CGRect
    ) -> CGFloat? {
        guard !isOnScreen(itemFrame, screenFrame: screenFrame) else { return nil }
        let shrink = targetMinX - itemFrame.minX
        return min(currentLength, max(minimum, currentLength - shrink))
    }

    /// Whether all of `frame` is within the screen's x range. A pressed item's menu opens
    /// right under it, and that is visible even when macOS doesn't draw the item itself
    /// (under the notch, or crowded out): measured with 1Password at x 599, 855 and 915.
    static func isOnScreen(_ frame: CGRect, screenFrame: CGRect) -> Bool {
        frame.minX >= screenFrame.minX && frame.maxX <= screenFrame.maxX
    }

    /// The notch range of a real screen. macOS reports the areas beside the notch as
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, in the same x coordinates as items.
    @MainActor
    static func notchRange(of screen: NSScreen) -> ClosedRange<CGFloat>? {
        notchRange(leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }
}
