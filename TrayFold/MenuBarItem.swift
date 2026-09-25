import CoreGraphics

/// One icon or label in the right-hand part of the menu bar (a "menu bar extra"),
/// such as Docker's whale or Control Center's clock. A snapshot: `frame` is where the
/// item was during the scan that found it.
struct MenuBarItem: Identifiable, Equatable, Sendable {
    /// The running app that put the item in the menu bar.
    struct Owner: Equatable, Sendable {
        /// Process id; changes every time the app is relaunched.
        let pid: pid_t
        /// For example "com.docker.docker"; nil for the rare app without one.
        let bundleID: String?
        /// The name Finder shows, for example "Docker Desktop".
        let name: String
    }

    /// Stays the same across scans while the app keeps running: the process id plus the
    /// item's Accessibility identifier, or its position among the app's items if it has none.
    let id: String
    let owner: Owner
    /// Text shown in the menu bar, for example "25:00" for a timer; nil for icon-only items.
    let title: String?
    /// What VoiceOver reads, for example "Wi‑Fi, connected, 3 bars". Often nil for
    /// third-party icons. (Not named `description`, which Swift uses for printing values.)
    let accessibilityDescription: String?
    /// Apple's own items have one, for example "com.apple.menuextra.clock"; most others don't.
    let identifier: String?
    /// Position and size in screen points. x grows to the right; a negative x means the item
    /// was pushed past the left edge of the screen (for example by TrayFold's divider).
    let frame: CGRect
    /// The live Accessibility handle, used later to press the item.
    let element: AXElement
}
