import AppKit
import ScreenCaptureKit
import os

/// The optional "Show Live Icons" setting: tray entries show an item's real menu bar image
/// (Docker's whale in its current state, a timer's digits) instead of its app's icon.
///
/// Off by default, because it needs macOS's Screen Recording permission. While it's off,
/// nothing here checks, asks for or uses that permission: every system call sits behind
/// `isEnabled`. This is the only file that uses ScreenCaptureKit.
///
/// macOS can only capture an item while it's on the screen, and folded items are thousands
/// of points to the left of it. So an item is captured when TrayFold has it on-screen anyway
/// (while its menu is open from the tray, or when the tray opens while it's visible) and the
/// image is kept for later. Until then, and whenever a capture fails, the app icon shows.
@MainActor
final class LiveIcons {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "LiveIcons")

    /// Where the setting is stored in `UserDefaults`. Missing means off.
    static let defaultsKey = "ShowLiveIcons"
    /// Opens System Settings on the Screen & System Audio Recording list.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Everything that talks to macOS, injectable so tests can prove none of it runs while off.
    struct System {
        /// Whether Screen Recording is allowed (never prompts).
        var isAllowed: () -> Bool
        /// Shows macOS's Screen Recording prompt (macOS shows it at most once per app).
        var requestAccess: () -> Void
        /// Where an item is right now. Blocks while its app answers, so it runs in the background.
        var frame: @Sendable (MenuBarItem) -> CGRect?
        /// One image per frame (screen points), nil for each that couldn't be captured.
        var capture: @Sendable ([CGRect]) async -> [CGImage?]
    }

    private let defaults: UserDefaults
    private let system: System
    /// The last image of each item, by `MenuBarItem.id`.
    private var cache: [String: NSImage] = [:]
    /// Goes up on every switch on or off, so a capture that was running across a switch
    /// can tell that its images are out of date.
    private var generation = 0

    init(defaults: UserDefaults = .standard, system: System = .live) {
        self.defaults = defaults
        self.system = system
    }

    /// The user's choice in the menu.
    var isEnabled: Bool { defaults.bool(forKey: Self.defaultsKey) }

    /// On, and allowed by macOS. `&&` stops early: while off, the permission isn't even checked.
    var isActive: Bool { isEnabled && system.isAllowed() }

    /// Images to show, by item id; empty while not active, so the tray falls back to app icons.
    var images: [String: NSImage] { isActive ? cache : [:] }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.defaultsKey)
        generation += 1
        Self.logger.notice("Live icons turned \(enabled ? "on" : "off", privacy: .public)")
        if !enabled {
            cache = [:]
        } else if !system.isAllowed() {
            system.requestAccess()
        }
    }

    /// Captures those of `items` that are inside `screen` right now. Returns whether any new
    /// image arrived. Items elsewhere are skipped before any capture is tried: a failed
    /// capture still makes macOS show its recording indicator.
    func capture(_ items: [MenuBarItem], screen: CGRect) async -> Bool {
        guard isActive else { return false }
        let frame = system.frame
        // `Task.detached`: reading positions blocks, and must not freeze the menu bar.
        let found = await Task.detached(priority: .userInitiated) {
            items.compactMap { item in frame(item).map { (id: item.id, frame: $0) } }
        }.value
        let onScreen = found.filter { MenuBarLayout.isOnScreen($0.frame, screenFrame: screen) }
        guard !onScreen.isEmpty else { return false }
        let started = ContinuousClock.now
        let generation = self.generation
        let images = await system.capture(onScreen.map(\.frame))
        // Switched off (or off and on) while capturing: these images must not come back.
        guard generation == self.generation else { return false }
        for (item, image) in zip(onScreen, images) {
            if let image { cache[item.id] = NSImage(cgImage: image, size: .zero) }
        }
        Self.logger.info("Captured \(images.compactMap { $0 }.count, privacy: .public) of \(onScreen.count, privacy: .public) in \(ContinuousClock.now - started, privacy: .public)")
        return images.contains { $0 != nil }
    }

    /// Forgets images of items that are gone. An item's id contains its app's process id,
    /// so after an app quits or relaunches its old images would otherwise stay forever.
    func forgetAll(except items: [MenuBarItem]) {
        let ids = Set(items.map(\.id))
        cache = cache.filter { ids.contains($0.key) }
    }

    // MARK: - Pure helpers (unit-tested without capturing anything)

    /// The smaller text under "Show Live Icons" in the menu.
    nonisolated static func subtitle(enabled: Bool, allowed: Bool) -> String {
        if !enabled { return "Real menu bar images; needs Screen Recording" }
        return allowed ? "Captured while an icon is on-screen" : "Allow Screen Recording, then reopen TrayFold"
    }

    /// Which of `windows` shows the item at `item`: the narrowest one containing the item's
    /// centre. On macOS 26 every menu bar item's window belongs to Control Center, not to the
    /// item's app, so position is the only link (measured: a window is its item's frame
    /// inset by 1 pt, or for Control Center's own items widened by 8 pt each side).
    nonisolated static func statusWindow(containing item: CGRect, among windows: [CGRect]) -> Int? {
        let centre = CGPoint(x: item.midX, y: item.midY)
        return windows.indices
            .filter { windows[$0].contains(centre) }
            .min { windows[$0].width < windows[$1].width }
    }
}

// MARK: - The real system

extension LiveIcons.System {
    @MainActor static let live = Self(
        isAllowed: { CGPreflightScreenCaptureAccess() },
        requestAccess: { _ = CGRequestScreenCaptureAccess() },
        frame: { $0.element.frame },
        capture: LiveIcons.captureMenuBar
    )
}

extension LiveIcons {
    /// Captures the menu bar item windows at `frames` with ScreenCaptureKit, one screenshot
    /// each (measured: ~50 ms to list windows, then 30–40 ms per item). `nonisolated`: runs
    /// off the main actor.
    nonisolated static func captureMenuBar(_ frames: [CGRect]) async -> [CGImage?] {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let windows = content?.windows.filter { $0.windowLayer == Int(CGWindowLevelForKey(.statusWindow)) } ?? []
        var images: [CGImage?] = []
        for frame in frames {
            let index = statusWindow(containing: frame, among: windows.map(\.frame))
            images.append(await capture(index.map { windows[$0] }))
        }
        return images
    }

    /// One screenshot of one window, at full Retina resolution; nil on any error.
    private nonisolated static func capture(_ window: SCWindow?) async -> CGImage? {
        guard let window else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        // Size in pixels, not points.
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
