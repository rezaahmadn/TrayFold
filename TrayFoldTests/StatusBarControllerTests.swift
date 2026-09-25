import AppKit
import Testing
@testable import TrayFold

/// Only the icon choice and the bundled glyph are unit-tested; the real menu bar item is checked by hand.
@MainActor
struct StatusBarControllerTests {
    @Test func iconShowsWarningUntilAllowed() {
        #expect(StatusBarController.icon(granted: false) == .symbol("exclamationmark.triangle"))
        #expect(StatusBarController.icon(granted: true) == .asset("MenuBarIcon"))
    }

    /// Tests run inside the app, so `NSImage(named:)` searches TrayFold's own asset catalog.
    @Test func menuBarGlyphShipsAsTemplate() throws {
        let image = try #require(NSImage(named: "MenuBarIcon"))
        #expect(image.isTemplate)
    }
}
