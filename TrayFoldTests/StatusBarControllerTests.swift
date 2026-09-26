import Testing
@testable import TrayFold

/// Only the icon choice is unit-tested; the real menu bar item is checked by hand.
@MainActor
struct StatusBarControllerTests {
    @Test func iconShowsWarningUntilAllowed() {
        #expect(StatusBarController.symbolName(granted: false) == "exclamationmark.triangle")
        #expect(StatusBarController.symbolName(granted: true) == "chevron.down")
    }
}
