import AppKit
import os

/// Wires TrayFold together once the app has launched.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "App")

    // Kept alive for the app's lifetime; releasing them would remove the menu bar item.
    private var permission: AccessibilityPermission?
    private var statusBar: StatusBarController?
    private var divider: DividerController?
    private var menuBarItems: MenuBarItemStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; skip the menu bar item and permission prompt there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let permission = AccessibilityPermission()
        permission.startObserving()
        Self.logger.notice("Launched; Accessibility allowed: \(permission.isGranted, privacy: .public)")
        if !permission.isGranted {
            // macOS shows its own dialog (at most once per app) and adds TrayFold,
            // switched off, to the Accessibility list, so the user only flips the switch.
            permission.promptIfNeeded()
        }
        // The divider first: it seeds both items' positions before either exists,
        // so a first launch puts it right next to the chevron. Starts expanded.
        let divider = DividerController(chevronAutosaveName: StatusBarController.autosaveName)
        statusBar = StatusBarController(permission: permission, divider: divider)
        self.divider = divider
        self.permission = permission

        let menuBarItems = MenuBarItemStore()
        menuBarItems.onChange = { items in
            Self.logger.notice("Menu bar items: \(MenuBarItemStore.summary(items), privacy: .public)")
        }
        menuBarItems.start()
        self.menuBarItems = menuBarItems
    }

    /// Called when the user opens TrayFold again while it's running (Spotlight,
    /// Finder). On a crowded notched bar, showing hidden icons can push the chevron
    /// itself out of sight; opening the app again folds everything back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        divider?.expand()
        return false
    }
}
