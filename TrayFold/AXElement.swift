import ApplicationServices

/// A handle to one piece of another app's user interface (the app itself, its part
/// of the menu bar, one menu bar item), as seen through the Accessibility API.
///
/// Why `@unchecked Sendable`: Swift can't tell whether `AXUIElement`, a Core Foundation
/// type, is safe to share between threads, so it refuses to send it from the background
/// scan to the main actor. It is safe: the element is an immutable token (process id plus
/// element id), reading an attribute only sends a message to the other app, and Core
/// Foundation's reference counting is thread-safe. The one setting it carries, the
/// messaging timeout, is set in `init` before the element is shared.
struct AXElement: @unchecked Sendable, Equatable {
    /// Longest wait, in seconds, for another app to answer one question. macOS's default
    /// is 6 s, so a single hung app would stall a scan that long. Measured on the author's
    /// Mac: a stopped app costs exactly this timeout; a responsive one answers in under 1 ms.
    static let messagingTimeout: Float = 0.25

    /// The Core Foundation reference this wraps.
    let raw: AXUIElement

    /// Wraps `raw` and applies `messagingTimeout` to it. macOS applies a timeout only to
    /// the exact element it was set on, not to elements read from it, so every element
    /// TrayFold uses is created through here.
    init(_ raw: AXUIElement) {
        self.raw = raw
        AXUIElementSetMessagingTimeout(raw, Self.messagingTimeout)
    }

    /// The top-level element of the app with process id `pid`.
    static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    /// A text attribute such as "AXTitle", or nil when it's missing or empty.
    func string(_ attribute: String) -> String? {
        guard let text = value(attribute) as? String, !text.isEmpty else { return nil }
        return text
    }

    /// An attribute that points at another element, such as "AXExtrasMenuBar".
    func element(_ attribute: String) -> AXElement? {
        // Core Foundation values arrive untyped; check the type before casting.
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement)
    }

    /// A yes/no attribute such as "AXSelected"; false when it's missing.
    func bool(_ attribute: String) -> Bool {
        value(attribute) as? Bool ?? false
    }

    /// An attribute that lists elements, such as "AXChildren" or "AXWindows".
    func elements(_ attribute: String) -> [AXElement] {
        (value(attribute) as? [AXUIElement] ?? []).map(AXElement.init)
    }

    /// The element's children, in the order the app reports them.
    var children: [AXElement] { elements("AXChildren") }

    /// Clicks the element, as VoiceOver would. Blocks until the app answers, at most
    /// `messagingTimeout`: an app that opens a menu only answers once the menu closes, so
    /// for menus this returns `.cannotComplete` after the timeout while the menu is already
    /// open (measured: menu open after 14–30 ms). Call it from a background task.
    func press() -> AXError {
        AXUIElementPerformAction(raw, "AXPress" as CFString)
    }

    /// Position and size in screen points. x grows to the right from the left edge of the
    /// main display (the same x axis AppKit uses); y grows downward from its top.
    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        // `AXValueGetValue` copies the boxed point or size into the variable after `&`.
        guard let position = boxed("AXPosition"), AXValueGetValue(position, .cgPoint, &origin),
              let extent = boxed("AXSize"), AXValueGetValue(extent, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Two handles are equal when they point at the same UI element, even if they came
    /// from different scans.
    static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        CFEqual(lhs.raw, rhs.raw)
    }

    /// Asks the other app for one attribute; nil on any error (missing, timed out, app gone).
    private func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, attribute as CFString, &result)
        return error == .success ? result : nil
    }

    /// Reads an attribute that Accessibility wraps in an `AXValue` box (points, sizes).
    private func boxed(_ attribute: String) -> AXValue? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
