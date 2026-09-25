import SwiftUI

/// The app's entry point. TrayFold has no regular window: everything lives in
/// the menu bar item that `AppDelegate` creates. SwiftUI's `MenuBarExtra` isn't
/// used because later phases need direct `NSStatusItem` control (its width is
/// how the divider hides other icons).
@main
struct TrayFoldApp: App {
    /// Lets an AppKit delegate receive the launch callback.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An `App` must declare at least one scene. An empty Settings scene opens
        // nothing at launch (unlike `WindowGroup`, which would show a blank window).
        Settings { EmptyView() }
    }
}
