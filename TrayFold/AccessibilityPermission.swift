import AppKit
import ApplicationServices
import os

/// Whether TrayFold may read and press other apps' menu bar items, which is
/// macOS's Accessibility permission (System Settings → Privacy & Security →
/// Accessibility). macOS gives no direct callback when the user flips the
/// switch, so `refresh()` runs at launch, whenever the menu opens, and when
/// the system broadcasts that the Accessibility list changed.
@MainActor
final class AccessibilityPermission {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Accessibility")

    /// Opens System Settings directly on the Accessibility list.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Last known answer. Changes only through `refresh()`.
    private(set) var isGranted: Bool

    /// Called on every change of `isGranted` (not on every refresh).
    var onChange: ((Bool) -> Void)?

    /// The actual system check, injectable so tests don't depend on this Mac's settings.
    private let isTrusted: () -> Bool
    private var observer: (any NSObjectProtocol)?

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
        self.isGranted = isTrusted()
    }

    /// Re-reads the permission and notifies `onChange` if it flipped.
    func refresh() {
        let now = isTrusted()
        guard now != isGranted else { return }
        isGranted = now
        Self.logger.notice("Accessibility allowed changed to \(now, privacy: .public)")
        onChange?(now)
    }

    /// Shows macOS's own permission dialog (the system shows it at most once per app).
    func promptIfNeeded() {
        // String literal instead of `kAXTrustedCheckOptionPrompt`: that constant is a
        // global `var`, which Swift 6 strict concurrency refuses to read.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane in System Settings.
    func openSettings() {
        if !NSWorkspace.shared.open(Self.settingsURL) {
            Self.logger.error("Could not open System Settings at \(Self.settingsURL.absoluteString, privacy: .public)")
        }
    }

    /// Listens for the system-wide "Accessibility list changed" broadcast.
    func startObserving() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The new value can lag the broadcast slightly; check again shortly after.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    /// Text for the (disabled) status line in the menu.
    static func statusTitle(granted: Bool) -> String {
        granted ? "Accessibility: Allowed" : "Accessibility: Not allowed"
    }
}
