import AppKit
import Testing
@testable import TrayFold

/// Only the icon choice and click routing are unit-tested; the real menu bar item is
/// checked by hand.
@MainActor
struct StatusBarControllerTests {
    @Test func iconShowsWarningUntilAllowed() {
        #expect(StatusBarController.symbolName(granted: false) == "exclamationmark.triangle")
        #expect(StatusBarController.symbolName(granted: true) == "chevron.down")
    }

    @Test func leftClickOpensTheTray() {
        #expect(StatusBarController.clickAction(for: .leftMouseUp, modifiers: [], granted: true) == .tray)
        // Other modifiers don't change that.
        #expect(StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.command], granted: true) == .tray)
    }

    @Test func rightClickAndControlClickOpenTheMenu() {
        #expect(StatusBarController.clickAction(for: .rightMouseUp, modifiers: [], granted: true) == .menu)
        #expect(StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.control], granted: true) == .menu)
    }

    /// The tray would be empty without the permission; the menu has the button to allow it.
    @Test func everyClickOpensTheMenuUntilAllowed() {
        #expect(StatusBarController.clickAction(for: .leftMouseUp, modifiers: [], granted: false) == .menu)
        #expect(StatusBarController.clickAction(for: .rightMouseUp, modifiers: [], granted: false) == .menu)
    }
}
