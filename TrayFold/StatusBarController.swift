import AppKit

/// Owns TrayFold's own menu bar item (the chevron). A left-click opens the tray popup;
/// a right-click or ⌃-click opens a small menu with the permission state, the divider
/// toggle, the live icons setting and Quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    /// macOS remembers where the user ⌘-dragged an item with this name.
    static let autosaveName = "TrayFoldChevron"
    /// Shown under the divider toggle in smaller text.
    static let dividerHint = "⌘-drag icons left of the divider to hide them"

    /// What a click on the chevron opens.
    enum ClickAction: Equatable { case tray, menu }

    private let permission: AccessibilityPermission
    private let divider: DividerController
    private let tray: TrayController
    private let liveIcons: LiveIcons
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let allowItem = NSMenuItem(title: "Allow Accessibility Access…", action: nil, keyEquivalent: "")
    private let dividerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let liveIconsItem = NSMenuItem(title: "Show Live Icons", action: nil, keyEquivalent: "")
    private let allowRecordingItem = NSMenuItem(title: "Allow Screen Recording…", action: nil, keyEquivalent: "")

    init(permission: AccessibilityPermission, divider: DividerController, tray: TrayController, liveIcons: LiveIcons) {
        self.permission = permission
        self.divider = divider
        self.tray = tray
        self.liveIcons = liveIcons
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = Self.autosaveName
        // Every click comes to `chevronClicked`, which picks the tray or the menu.
        // (A permanently set `statusItem.menu` would open on every click.)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(chevronClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

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
        liveIconsItem.target = self
        liveIconsItem.action = #selector(toggleLiveIcons)
        allowRecordingItem.target = self
        allowRecordingItem.action = #selector(openRecordingSettings)
        menu.addItem(liveIconsItem)
        menu.addItem(allowRecordingItem)
        menu.addItem(.separator())
        // No target: the action travels up to NSApplication, which quits.
        menu.addItem(NSMenuItem(title: "Quit TrayFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

    /// Left-click opens the tray; right-click or ⌃-click (the Mac's other right-click)
    /// opens the menu. Without the Accessibility permission the tray would be empty,
    /// so every click opens the menu, which has the button to allow it.
    /// `type` is nil when the press wasn't a mouse click on the chevron (VoiceOver,
    /// Accessibility, `performClick`): that counts as a plain left-click.
    static func clickAction(for type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags, granted: Bool) -> ClickAction {
        let wantsMenu = type == .rightMouseUp || (type == .leftMouseUp && modifiers.contains(.control))
        return granted && !wantsMenu ? .tray : .menu
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
        // A checkmark while on. `isActive` only checks the permission once the user turned it on.
        liveIconsItem.state = liveIcons.isEnabled ? .on : .off
        liveIconsItem.subtitle = LiveIcons.subtitle(enabled: liveIcons.isEnabled, allowed: liveIcons.isActive)
        allowRecordingItem.isHidden = !liveIcons.isEnabled || liveIcons.isActive
    }

    @objc private func chevronClicked(_ sender: NSStatusBarButton) {
        // Only trust the current event if it's the click on this button; a press from
        // VoiceOver or Accessibility may leave no event, or an older one from elsewhere.
        let event = NSApp.currentEvent.flatMap { $0.window == sender.window ? $0 : nil }
        permission.refresh()
        switch Self.clickAction(for: event?.type, modifiers: event?.modifierFlags ?? [], granted: permission.isGranted) {
        case .tray:
            tray.toggle(relativeTo: sender)
        case .menu:
            tray.close()
            // Attach the menu for this one click so macOS shows it in the usual place,
            // then detach it in `menuDidClose` so the next left-click opens the tray.
            statusItem.menu = menu
            sender.performClick(nil)
        }
    }

    // Called just before the menu shows: the cheapest moment to re-check the permission.
    func menuWillOpen(_ menu: NSMenu) {
        permission.refresh()
        update()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        permission.openSettings()
    }

    @objc private func toggleDivider() {
        divider.toggle()
    }

    @objc private func toggleLiveIcons() {
        liveIcons.setEnabled(!liveIcons.isEnabled)
    }

    @objc private func openRecordingSettings() {
        NSWorkspace.shared.open(LiveIcons.settingsURL)
    }
}
