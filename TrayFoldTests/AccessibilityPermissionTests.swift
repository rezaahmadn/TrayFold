import Testing
@testable import TrayFold

/// Drives `AccessibilityPermission` with a fake trust check, so tests never depend
/// on this Mac's real Accessibility settings. The system prompt, the Settings link
/// and the distributed notification are checked by hand.
@MainActor
struct AccessibilityPermissionTests {
    /// Mutable stand-in for the system's answer.
    final class FakeTrust { var value = false }

    @Test func startsWithTheSystemAnswer() {
        let trust = FakeTrust(); trust.value = true
        #expect(AccessibilityPermission(isTrusted: { trust.value }).isGranted)
    }

    @Test func refreshPicksUpAGrant() {
        let trust = FakeTrust()
        let permission = AccessibilityPermission(isTrusted: { trust.value })
        #expect(!permission.isGranted)
        trust.value = true
        permission.refresh()
        #expect(permission.isGranted)
    }

    @Test func onChangeFiresOnlyWhenTheAnswerFlips() {
        let trust = FakeTrust()
        let permission = AccessibilityPermission(isTrusted: { trust.value })
        var calls: [Bool] = []
        permission.onChange = { calls.append($0) }
        permission.refresh()            // still false → no call
        trust.value = true
        permission.refresh()            // flips → call
        permission.refresh()            // unchanged → no call
        trust.value = false
        permission.refresh()            // revoked → call
        #expect(calls == [true, false])
    }

    @Test func statusTitles() {
        #expect(AccessibilityPermission.statusTitle(granted: true) == "Accessibility: Allowed")
        #expect(AccessibilityPermission.statusTitle(granted: false) == "Accessibility: Not allowed")
    }
}
