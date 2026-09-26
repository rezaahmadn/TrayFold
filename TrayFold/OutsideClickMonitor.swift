import AppKit

/// Calls a closure on every mouse click in other apps while started (a "global monitor").
/// It never sees clicks in TrayFold's own menu or popup and, for mouse clicks, needs no
/// extra permission. Used to close the tray and to re-fold the divider.
@MainActor
final class OutsideClickMonitor {
    private var monitor: Any?

    /// Calls `handler` on each click of the kinds in `events`; does nothing if already started.
    func start(_ events: NSEvent.EventTypeMask, _ handler: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: events) { _ in
            // AppKit calls this on the main thread; tell Swift so.
            MainActor.assumeIsolated { handler() }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    // `isolated`: runs on the main actor like the rest of the class, so it may call `stop()`.
    isolated deinit {
        stop()
    }
}
