import AppKit
import ApplicationServices

/// Push-to-talk via a global NSEvent monitor. We watch `flagsChanged` for the
/// trigger modifier (right Option by default) going down and up, even while
/// another app is focused.
///
/// A global key-event monitor only needs **Accessibility** trust (unlike a
/// CGEvent tap, which can also demand Input Monitoring). One permission, done.
final class HotKeyMonitor {

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var monitor: Any?
    private var isHeld = false

    /// Control. keyCode 59 = kVK_Control. Held alone = push-to-talk.
    private let triggerKeyCode: UInt16 = 59
    private let triggerFlag: NSEvent.ModifierFlags = .control

    /// Starts listening. Returns false if Accessibility isn't granted yet
    /// (key events wouldn't be delivered), so the caller can retry later.
    @discardableResult
    func start() -> Bool {
        guard monitor == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        return monitor != nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isHeld = false
    }

    // Delivered on the main thread by the run loop.
    private func handle(_ event: NSEvent) {
        guard event.keyCode == triggerKeyCode else { return }

        let down = event.modifierFlags.contains(triggerFlag)
        if down && !isHeld {
            isHeld = true
            onPress?()
        } else if !down && isHeld {
            isHeld = false
            onRelease?()
        }
    }
}
