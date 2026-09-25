import AppKit
import ApplicationServices
import os

/// The current list of menu bar items, kept up to date without polling. It rescans an
/// app when it launches, drops its items when it quits, rescans everything when the
/// Accessibility permission changes, and whenever `refresh()` is called (the tray popup
/// will call it each time it opens). While Accessibility isn't allowed, the list is empty.
/// Scans run in the background: asking ~50 apps takes ~20 ms, but ~0.25–0.5 s the
/// first time, while macOS sets up a connection to each app.
@MainActor
final class MenuBarItemStore {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Discovery")

    /// How long to wait after macOS reports a launch before looking for the app's items:
    /// apps usually add their menu bar item a moment after they start.
    static let launchSettleTime: Duration = .seconds(2)

    /// Latest known items, sorted left to right. Changes only through the methods below.
    private(set) var items: [MenuBarItem] = []

    /// Called every time `items` changes (not on scans that find the same items).
    var onChange: (([MenuBarItem]) -> Void)?

    // The real system calls, injectable so tests don't depend on this Mac's apps and settings.
    private let isTrusted: () -> Bool
    private let candidateApps: @MainActor () -> [MenuBarItem.Owner]
    /// `@Sendable` because it runs on a background thread.
    private let scan: @Sendable ([MenuBarItem.Owner]) -> [MenuBarItem]

    // Kept so the observations stay active; dropping them would stop the updates.
    private var appsObservation: NSKeyValueObservation?
    private var permissionObserver: (any NSObjectProtocol)?
    /// The most recently queued update; see `enqueue(_:)`.
    private var lastUpdate: Task<Void, Never>?

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        candidateApps: @escaping @MainActor () -> [MenuBarItem.Owner] = MenuBarItemScanner.candidateApps,
        scan: @escaping @Sendable ([MenuBarItem.Owner]) -> [MenuBarItem] = MenuBarItemScanner.scan
    ) {
        self.isTrusted = isTrusted
        self.candidateApps = candidateApps
        self.scan = scan
    }

    /// Starts listening for app launches and quits and for permission changes, then
    /// runs the first scan.
    func start() {
        // Watches the list of running apps itself ("key-value observing"), not NSWorkspace's
        // launch/quit notifications: macOS doesn't post those for menu-bar-only apps
        // (`LSUIElement`), which are most of the apps TrayFold cares about.
        // `@Sendable`: the closure only passes values on to the main actor.
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { @Sendable [weak self] _, change in
            let launched = (change.newValue ?? []).filter(MenuBarItemScanner.isCandidate).map(MenuBarItemScanner.owner(of:))
            let quit = (change.oldValue ?? []).map(\.processIdentifier)
            Task { @MainActor in
                for pid in quit { await self?.forget(pid: pid) }
                guard !launched.isEmpty else { return }
                try? await Task.sleep(for: Self.launchSettleTime)
                for owner in launched { await self?.rescan(owner) }
            }
        }
        // The same system broadcast `AccessibilityPermission` listens to. Its `onChange`
        // already belongs to the status bar, so the store listens on its own: rescan once
        // the permission is granted, empty the list once it's revoked.
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The new value can lag the broadcast slightly; check again shortly after.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Rescans every app. Returns once `items` is up to date.
    func refresh() async {
        await enqueue { [self] in
            guard isTrusted() else { return apply([]) }
            apply(await scanInBackground(candidateApps()))
        }
    }

    /// Rescans one app (after it launched) and replaces only its items.
    func rescan(_ owner: MenuBarItem.Owner) async {
        await enqueue { [self] in
            guard isTrusted() else { return apply([]) }
            let found = await scanInBackground([owner])
            apply(items.filter { $0.owner.pid != owner.pid } + found)
        }
    }

    /// Drops the items of an app that quit. Needs no Accessibility call.
    func forget(pid: pid_t) async {
        await enqueue { [self] in
            apply(items.filter { $0.owner.pid != pid })
        }
    }

    /// One line for the log, for example "3 (com.docker.docker, com.apple.controlcenter, …)".
    /// Bundle ids only: item titles can be personal (a timer, a VPN name).
    static func summary(_ items: [MenuBarItem]) -> String {
        "\(items.count) (\(items.map { $0.owner.bundleID ?? $0.owner.name }.joined(separator: ", ")))"
    }

    /// Runs `update` once every update queued before it has finished. Updates pause while
    /// a scan runs in the background; without this queue, a slow full scan could finish
    /// after a newer one-app update and overwrite it with older data.
    private func enqueue(_ update: @escaping @MainActor () async -> Void) async {
        let previous = lastUpdate
        let task = Task { @MainActor in
            await previous?.value
            await update()
        }
        lastUpdate = task
        await task.value
    }

    /// Runs the blocking scan on a background thread. `Task.detached` matters: a plain
    /// `Task` started here would inherit the main actor and freeze the menu bar while it waits.
    private func scanInBackground(_ owners: [MenuBarItem.Owner]) async -> [MenuBarItem] {
        let scan = self.scan
        let started = ContinuousClock.now
        let found = await Task.detached(priority: .userInitiated) { scan(owners) }.value
        let milliseconds = Int(((ContinuousClock.now - started) / .milliseconds(1)).rounded())
        Self.logger.info("Scanned \(owners.count, privacy: .public) apps in \(milliseconds, privacy: .public) ms: \(found.count, privacy: .public) items")
        return found
    }

    /// Stores `newItems` left to right and calls `onChange` if anything differs.
    private func apply(_ newItems: [MenuBarItem]) {
        let sorted = newItems.sorted { $0.frame.minX < $1.frame.minX }
        guard sorted != items else { return }
        items = sorted
        onChange?(sorted)
    }
}
