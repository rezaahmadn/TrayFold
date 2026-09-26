import CoreGraphics
import Testing
@testable import TrayFold

/// Checks what the tray lists and how it labels and lays out entries, with made-up items
/// placed like the author's bar: 1512-pt screen, notch at x 665…850, divider at x -4068
/// while expanded. The popover itself is checked by hand (see the phase 4 report).
@MainActor
struct TrayControllerTests {
    static func item(
        _ name: String, x: CGFloat, width: CGFloat = 34,
        title: String? = nil, description: String? = nil
    ) -> MenuBarItem {
        MenuBarItem(
            id: "1/\(name)",
            owner: MenuBarItem.Owner(pid: 1, bundleID: "test.\(name)", name: name),
            title: title,
            accessibilityDescription: description,
            identifier: nil,
            frame: CGRect(x: x, y: 0, width: width, height: 24),
            // Nothing is asked until it's read, so a made-up pid is fine.
            element: AXElement.application(pid: 1)
        )
    }

    func folded(_ items: [MenuBarItem], divider: CGFloat? = -4068) -> [String] {
        TrayController.foldedItems(items, dividerMinX: divider, notchRange: 665...850, screenMinX: 0)
            .map(\.owner.name)
    }

    @Test func listsEverythingNotVisibleLeftToRight() {
        let items = [
            Self.item("Clock", x: 1344, width: 162),         // visible
            Self.item("Docker", x: 971, width: 47),          // visible
            Self.item("Notched", x: 700),                    // under the notch
            Self.item("1Password", x: -4108),                // left of the divider
            Self.item("WPS", x: -4174, width: 36),           // left of the divider
        ]
        #expect(folded(items) == ["WPS", "1Password", "Notched"])
    }

    @Test func nothingFoldedAwayIsEmpty() {
        #expect(folded([Self.item("Docker", x: 971), Self.item("Clock", x: 1344)]).isEmpty)
    }

    @Test func beforeTheDividerIsPlacedOnlyNotchAndOffScreenCount() {
        let items = [Self.item("Off", x: -300), Self.item("Notched", x: 700), Self.item("Docker", x: 971)]
        #expect(folded(items, divider: nil) == ["Off", "Notched"])
    }

    @Test func labelPrefersTheItemsOwnText() {
        #expect(TrayController.label(for: Self.item("Slice", x: 0, title: "25:00", description: "Timer")) == "25:00")
    }

    @Test func labelUsesTheDescriptionUpToTheFirstComma() {
        let wifi = Self.item("Control Center", x: 0, description: "Wi‑Fi, connected, 3 bars")
        #expect(TrayController.label(for: wifi) == "Wi‑Fi")
        #expect(TrayController.label(for: Self.item("Control Center", x: 0, description: "Sound")) == "Sound")
    }

    /// Icon-only third-party items have neither (an empty title arrives as nil).
    @Test func labelFallsBackToTheAppName() {
        #expect(TrayController.label(for: Self.item("Docker Desktop", x: 0)) == "Docker Desktop")
    }

    @Test func tooltipAddsTheFullTextToTheAppName() {
        let wifi = Self.item("Control Center", x: 0, description: "Wi‑Fi, connected, 3 bars")
        #expect(TrayController.tooltip(for: wifi) == "Control Center: Wi‑Fi, connected, 3 bars")
        #expect(TrayController.tooltip(for: Self.item("Slice", x: 0, title: "25:00")) == "Slice: 25:00")
        #expect(TrayController.tooltip(for: Self.item("Docker Desktop", x: 0)) == "Docker Desktop")
        // Control Center's own item is described with the app's name: don't repeat it.
        #expect(TrayController.tooltip(for: Self.item("Control Center", x: 0, description: "Control Center")) == "Control Center")
    }

    /// The grid starts small and adds rows of at most 5, like the Windows tray.
    @Test func gridGrowsByRowsOfFive() {
        func shape(_ count: Int) -> [Int] { TrayController.rows(Array(0 ..< count)).map(\.count) }
        #expect(shape(0) == [])
        #expect(shape(1) == [1])
        #expect(shape(5) == [5])
        #expect(shape(6) == [5, 1])
        #expect(shape(12) == [5, 5, 2])
        #expect(TrayController.rows(Array(0 ..< 7)) == [[0, 1, 2, 3, 4], [5, 6]])
    }
}
