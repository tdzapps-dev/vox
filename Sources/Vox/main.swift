import AppKit

// Top-level code runs on the main thread at launch; assert main-actor
// isolation so we can touch NSApplication / AppDelegate directly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
