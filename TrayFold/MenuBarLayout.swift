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

    /// The notch range of a real screen. macOS reports the areas beside the notch as
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, in the same x coordinates as items.
    @MainActor
    static func notchRange(of screen: NSScreen) -> ClosedRange<CGFloat>? {
        notchRange(leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }
}
