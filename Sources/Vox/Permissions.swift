import AppKit
import AVFoundation
import Speech
import ApplicationServices

/// Thin wrappers around the three TCC permissions Vox needs:
/// microphone (capture), speech recognition (transcribe), and
/// accessibility (listen for the global hotkey + post the ⌘V paste).
enum Permissions {

    // MARK: Microphone

    static var micAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    @discardableResult
    static func requestMic() async -> Bool {
        if micAuthorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: Speech recognition

    static var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    @discardableResult
    static func requestSpeech() async -> Bool {
        if speechAuthorized { return true }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: Accessibility

    /// Whether this process is trusted for the Accessibility API.
    /// Pass `prompt: true` to surface the system "grant access" dialog.
    @discardableResult
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
