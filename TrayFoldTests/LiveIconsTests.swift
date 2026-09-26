import AppKit
import Synchronization
import Testing
@testable import TrayFold

/// Drives `LiveIcons` with a fake macOS, so no test checks, asks for or uses the real Screen
/// Recording permission. Screen and positions from the author's Mac: 1512-pt screen,
/// folded items at x ≈ -4100. The real capture is checked by hand (see the phase 6 report).
@MainActor
struct LiveIconsTests {
    static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    /// Counts every call into the pretend system. `Sendable` with a lock inside, because
    /// `frame` and `capture` run on background threads.
    final class FakeSystem: Sendable {
        struct Values {
            var allowed = true
            /// What each capture returns; nil means it failed.
            var image: CGImage? = LiveIconsTests.image()
            var allowedChecks = 0
            var requests = 0
            var frameReads = 0
            /// The frames passed to each capture call.
            var captures: [[CGRect]] = []
        }
        let values = Mutex(Values())
        func update(_ change: (inout Values) -> Void) { values.withLock { change(&$0) } }
        var snapshot: Values { values.withLock { $0 } }

        func system() -> LiveIcons.System {
            LiveIcons.System(
                isAllowed: { self.values.withLock { $0.allowedChecks += 1; return $0.allowed } },
                requestAccess: { self.update { $0.requests += 1 } },
                frame: { item in self.values.withLock { $0.frameReads += 1 }; return item.frame },
                capture: { frames in
                    self.values.withLock { values in
                        values.captures.append(frames)
                        return frames.map { _ in values.image }
                    }
                }
            )
        }
    }

    /// A 2 × 2 transparent picture, standing in for a capture.
    nonisolated static func image() -> CGImage? {
        CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    /// A fresh, empty settings store per test, so the real TrayFold settings are never read.
    func makeLiveIcons(_ fake: FakeSystem, enabled: Bool? = nil) -> LiveIcons {
        let defaults = UserDefaults(suiteName: "LiveIconsTests.\(UUID().uuidString)")!
        if let enabled { defaults.set(enabled, forKey: LiveIcons.defaultsKey) }
        return LiveIcons(defaults: defaults, system: fake.system())
    }

    let docker = TrayControllerTests.item("Docker", x: 974, width: 47)
    let folded = TrayControllerTests.item("1Password", x: -4105)

    @Test func offByDefault() {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake)
        #expect(!live.isEnabled)
        #expect(!live.isActive)
        #expect(live.images.isEmpty)
    }

    /// The core promise: while off, nothing touches Screen Recording, not even a check.
    @Test func whileOffNothingIsCheckedAskedOrCaptured() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake)
        #expect(await live.capture([docker], screen: Self.screen) == false)
        _ = live.images
        _ = live.isActive
        let calls = fake.snapshot
        #expect(calls.allowedChecks == 0)
        #expect(calls.requests == 0)
        #expect(calls.frameReads == 0)
        #expect(calls.captures.isEmpty)
    }

    @Test func turningOnAsksForScreenRecordingOnlyIfNeeded() async {
        let fake = FakeSystem()
        fake.update { $0.allowed = false }
        let live = makeLiveIcons(fake)
        live.setEnabled(true)
        #expect(live.isEnabled)
        #expect(fake.snapshot.requests == 1)
        // Not allowed (yet): app icons, and no capture is tried.
        #expect(!live.isActive)
        #expect(await live.capture([docker], screen: Self.screen) == false)
        #expect(fake.snapshot.captures.isEmpty)

        let allowed = FakeSystem()
        makeLiveIcons(allowed).setEnabled(true)
        #expect(allowed.snapshot.requests == 0)
    }

    @Test func capturesOnlyItemsOnTheScreen() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake, enabled: true)
        #expect(await live.capture([folded, docker], screen: Self.screen))
        #expect(fake.snapshot.captures == [[docker.frame]])
        #expect(Set(live.images.keys) == [docker.id])
    }

    /// A capture that fails still shows macOS's recording indicator, so folded items
    /// (which can't be captured) must not even be tried.
    @Test func nothingOnScreenMeansNoCapture() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake, enabled: true)
        #expect(await live.capture([folded], screen: Self.screen) == false)
        #expect(fake.snapshot.captures.isEmpty)
    }

    @Test func aFailedCaptureKeepsTheLastImage() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake, enabled: true)
        fake.update { $0.image = nil }
        #expect(await live.capture([docker], screen: Self.screen) == false)
        #expect(live.images.isEmpty)       // → app icon

        fake.update { $0.image = Self.image() }
        _ = await live.capture([docker], screen: Self.screen)
        let first = live.images[docker.id]
        fake.update { $0.image = nil }
        _ = await live.capture([docker], screen: Self.screen)
        #expect(live.images[docker.id] === first)
    }

    @Test func revokingThePermissionFallsBackToAppIcons() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake, enabled: true)
        _ = await live.capture([docker], screen: Self.screen)
        fake.update { $0.allowed = false }
        #expect(live.images.isEmpty)
    }

    @Test func turningOffForgetsTheImages() async {
        let fake = FakeSystem()
        let live = makeLiveIcons(fake, enabled: true)
        _ = await live.capture([docker], screen: Self.screen)
        live.setEnabled(false)
        #expect(live.images.isEmpty)
        live.setEnabled(true)
        #expect(live.images.isEmpty)
    }

    /// Window frames measured on the author's Mac (all owned by Control Center).
    @Test func findsTheItemsWindowByPosition() {
        let windows = [
            CGRect(x: -4072, y: 0, width: 5016, height: 33),  // TrayFold's expanded divider
            CGRect(x: 975, y: 0, width: 45, height: 33),      // Docker
            CGRect(x: 1218, y: 0, width: 38, height: 33),     // Wi-Fi
            CGRect(x: -4104, y: 0, width: 32, height: 33),    // 1Password, folded
        ]
        let dockerItem = CGRect(x: 974, y: 4.5, width: 47, height: 24)
        let wifiItem = CGRect(x: 1226, y: 5.5, width: 22, height: 22)
        #expect(LiveIcons.statusWindow(containing: dockerItem, among: windows) == 1)
        #expect(LiveIcons.statusWindow(containing: wifiItem, among: windows) == 2)
        #expect(LiveIcons.statusWindow(containing: CGRect(x: -4105, y: 4.5, width: 34, height: 24), among: windows) == 3)
        // Nothing there (say, on macOS 27, which has one window for the whole bar).
        #expect(LiveIcons.statusWindow(containing: CGRect(x: 1400, y: 4.5, width: 20, height: 24), among: windows) == nil)
        #expect(LiveIcons.statusWindow(containing: dockerItem, among: []) == nil)
    }

    /// The narrowest match wins: a wide window that happens to cover the item isn't it.
    @Test func prefersTheNarrowestWindow() {
        let windows = [CGRect(x: 900, y: 0, width: 400, height: 33), CGRect(x: 975, y: 0, width: 45, height: 33)]
        #expect(LiveIcons.statusWindow(containing: CGRect(x: 974, y: 4.5, width: 47, height: 24), among: windows) == 1)
    }

    @Test func menuSubtitles() {
        #expect(LiveIcons.subtitle(enabled: false, allowed: false) == "Real menu bar images; needs Screen Recording")
        #expect(LiveIcons.subtitle(enabled: true, allowed: false) == "Allow Screen Recording, then reopen TrayFold")
        #expect(LiveIcons.subtitle(enabled: true, allowed: true) == "Captured while an icon is on-screen")
    }
}
