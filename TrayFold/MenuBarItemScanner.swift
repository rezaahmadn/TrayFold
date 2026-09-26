import AppKit

/// Reads every app's menu bar items through the Accessibility API. An `enum` with no
/// cases is a namespace: it can't be instantiated, it only groups the functions.
/// Two steps, split by cost: `candidateApps()` lists which apps to ask (cheap, main
/// actor); `scan(_:)` asks them (blocking, so run it in the background).
enum MenuBarItemScanner {
    /// Whether `app` might own menu bar items. Skips TrayFold (including a second copy,
    /// such as a development build) and background-only apps, which can't show anything
    /// on screen. (On the author's Mac: 52 of 105 running apps were background-only, none
    /// with a menu bar, and skipping them halves a scan.)
    static func isCandidate(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && app.bundleIdentifier != Bundle.main.bundleIdentifier
            && app.activationPolicy != .prohibited
    }

    /// The parts of `app` that the rest of TrayFold needs, as a plain value.
    static func owner(of app: NSRunningApplication) -> MenuBarItem.Owner {
        MenuBarItem.Owner(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        )
    }

    /// Every running app worth asking.
    @MainActor
    static func candidateApps() -> [MenuBarItem.Owner] {
        NSWorkspace.shared.runningApplications.filter(isCandidate).map(owner(of:))
    }

    /// Asks each app for its menu bar items. Blocks while the apps answer: about 20 ms
    /// for all apps, but ~0.5 s the first time (macOS sets up a connection to each app),
    /// plus `AXElement.messagingTimeout` for every app that doesn't answer.
    static func scan(_ owners: [MenuBarItem.Owner]) -> [MenuBarItem] {
        owners.flatMap(items(of:))
    }

    /// The menu bar items of one app, in the order the app reports them.
    static func items(of owner: MenuBarItem.Owner) -> [MenuBarItem] {
        // "AXExtrasMenuBar" is the app's part of the right side of the menu bar.
        // Apps without menu bar items don't have one.
        guard let bar = AXElement.application(pid: owner.pid).element("AXExtrasMenuBar") else { return [] }
        return bar.children.enumerated().compactMap { index, element in
            // Control Center also lists modules macOS isn't drawing: zero size at x = 0,
            // with no title, description or identifier. Skip anything without a width.
            guard let frame = element.frame, frame.width > 0 else { return nil }
            let identifier = element.string("AXIdentifier")
            return MenuBarItem(
                id: "\(owner.pid)/\(identifier ?? "#\(index)")",
                owner: owner,
                title: element.string("AXTitle"),
                accessibilityDescription: element.string("AXDescription"),
                identifier: identifier,
                frame: frame,
                element: element
            )
        }
    }
}
