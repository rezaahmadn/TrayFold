import ApplicationServices
import Foundation
import Testing
@testable import TrayFold

/// Scans this Mac's real menu bar. Needs the Accessibility permission, which only a
/// locally signed build has (see Scripts/setup-signing.sh); on CI the test is skipped.
@MainActor
struct MenuBarItemScannerTests {
    @Test(.enabled(if: AXIsProcessTrusted(), "Needs the Accessibility permission (not available on CI)"))
    func findsControlCenterItems() async {
        let owners = MenuBarItemScanner.candidateApps()
        let items = await Task.detached { MenuBarItemScanner.scan(owners) }.value
        // Every Mac shows at least the clock, which belongs to Control Center.
        #expect(items.contains { $0.owner.bundleID == "com.apple.controlcenter" })
        #expect(items.allSatisfy { $0.frame.width > 0 })
        #expect(!items.contains { $0.owner.pid == ProcessInfo.processInfo.processIdentifier })
        #expect(Set(items.map(\.id)).count == items.count)
    }

    /// Also covers a second running copy of TrayFold (for example a development build).
    @Test func candidatesExcludeTrayFoldItself() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        #expect(!MenuBarItemScanner.candidateApps().contains {
            $0.pid == ownPID || $0.bundleID == Bundle.main.bundleIdentifier
        })
    }
}
