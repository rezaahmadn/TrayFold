import AppKit

/// Owns TrayFold's own menu bar item (the chevron): an icon plus a small menu with
/// the permission state, the divider toggle and Quit. A later phase adds the tray popup.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    /// macOS remembers where the user ⌘-dragged an item with this name.
    static let autosaveName = "TrayFoldChevron"
    /// Shown under the divider toggle in smaller text.
    static let dividerHint = "⌘-drag icons left of the divider to hide them"

    private let permission: AccessibilityPermission
    private let divider: DividerController
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let allowItem = NSMenuItem(title: "Allow Accessibility Access…", action: nil, keyEquivalent: "")
    private let dividerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(permission: AccessibilityPermission, divider: DividerController) {
        self.permission = permission
        self.divider = divider
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = Self.autosaveName

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        allowItem.target = self
        allowItem.action = #selector(openSettings)
        menu.addItem(statusLine)
        menu.addItem(allowItem)
        menu.addItem(.separator())
        dividerItem.target = self
        dividerItem.action = #selector(toggleDivider)
        // A second, smaller line under the title (macOS 14.4+).
        dividerItem.subtitle = Self.dividerHint
        menu.addItem(dividerItem)
        menu.addItem(.separator())
        // No target: the action travels up to NSApplication, which quits.
        menu.addItem(NSMenuItem(title: "Quit TrayFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        permission.onChange = { [weak self] _ in self?.update() }
        update()
    }

    /// SF Symbol shown in the menu bar: a downward chevron (the tray opens below it)
    /// once allowed, a warning triangle until then.
    /// Pure (no AppKit calls), so tests can check it without a menu bar.
    static func symbolName(granted: Bool) -> String {
        granted ? "chevron.down" : "exclamationmark.triangle"
    }

    /// Text of the divider toggle: what clicking it will do.
    static func dividerTitle(isExpanded: Bool) -> String {
        isExpanded ? "Show Hidden Icons" : "Hide Icons"
    }

    private func update() {
        let granted = permission.isGranted
        // SF Symbols are template images: macOS tints them black or white to match
        // the menu bar. VoiceOver reads the description instead of the picture.
        statusItem.button?.image = NSImage(
            systemSymbolName: Self.symbolName(granted: granted),
            accessibilityDescription: "TrayFold"
        )
        statusLine.title = AccessibilityPermission.statusTitle(granted: granted)
        allowItem.isHidden = granted
        dividerItem.title = Self.dividerTitle(isExpanded: divider.isExpanded)
    }

    // Called just before the menu shows: the cheapest moment to re-check the permission.
    func menuWillOpen(_ menu: NSMenu) {
        permission.refresh()
        update()
    }

    @objc private func openSettings() {
        permission.openSettings()
    }

    @objc private func toggleDivider() {
        divider.toggle()
    }
}
