import AppKit

/// Owns TrayFold's menu bar item. Phase 1: an icon plus a small menu with the
/// permission state and Quit. Later phases add the divider and the tray popup.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let permission: AccessibilityPermission
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let allowItem = NSMenuItem(title: "Allow Accessibility Access…", action: nil, keyEquivalent: "")

    init(permission: AccessibilityPermission) {
        self.permission = permission
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // macOS remembers where the user ⌘-dragged an item with this name.
        statusItem.autosaveName = "TrayFoldChevron"

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        allowItem.target = self
        allowItem.action = #selector(openSettings)
        menu.addItem(statusLine)
        menu.addItem(allowItem)
        menu.addItem(.separator())
        // No target: the action travels up to NSApplication, which quits.
        menu.addItem(NSMenuItem(title: "Quit TrayFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        permission.onChange = { [weak self] _ in self?.update() }
        update()
    }

    /// Where the menu bar image comes from. Each `case` carries a name (an
    /// "associated value"), and `switch` makes callers handle both kinds.
    /// `Equatable` lets tests compare values with `==`.
    enum Icon: Equatable {
        /// An image in `Assets.xcassets`, loaded with `NSImage(named:)`.
        case asset(String)
        /// A built-in SF Symbol, loaded with `NSImage(systemSymbolName:)`.
        case symbol(String)
    }

    /// TrayFold's own glyph once allowed, a warning triangle until then.
    /// Pure (no AppKit calls), so tests can check it without a menu bar.
    static func icon(granted: Bool) -> Icon {
        granted ? .asset("MenuBarIcon") : .symbol("exclamationmark.triangle")
    }

    private func update() {
        let granted = permission.isGranted
        let image: NSImage?
        switch Self.icon(granted: granted) {
        case .asset(let name):
            // The asset catalog marks this image as a template, so macOS tints it
            // black or white to match the menu bar, like an SF Symbol.
            image = NSImage(named: name)
        case .symbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        // VoiceOver reads this instead of describing the picture.
        image?.accessibilityDescription = "TrayFold"
        statusItem.button?.image = image
        statusLine.title = AccessibilityPermission.statusTitle(granted: granted)
        allowItem.isHidden = granted
    }

    // Called just before the menu shows: the cheapest moment to re-check the permission.
    func menuWillOpen(_ menu: NSMenu) {
        permission.refresh()
        update()
    }

    @objc private func openSettings() {
        permission.openSettings()
    }
}
