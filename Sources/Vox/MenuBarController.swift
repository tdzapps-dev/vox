import AppKit

@MainActor
final class MenuBarController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = DictationEngine()
    private let hotkey = HotKeyMonitor()
    private var accessibilityWatcher: Timer?
    private var lastTrusted = false
    // Dictation is driven off the physical key state, reconciled by a single
    // loop — never separate queued press/release ops that can desync and wedge.
    private var keyDown = false
    private var reconciling = false

    private let languages: [(title: String, identifier: String)] = [
        ("Português (Brasil)", "pt-BR"),
        ("English (US)", "en-US"),
    ]

    func start() {
        updateIcon(.idle)
        engine.onStateChange = { [weak self] state in self?.updateIcon(state) }
        buildMenu()

        Task { await requestPermissionsAndArm() }
    }

    // MARK: - Setup

    private func requestPermissionsAndArm() async {
        let mic = await Permissions.requestMic()
        let speech = await Permissions.requestSpeech()
        let ax = Permissions.accessibilityTrusted(prompt: true)
        Log.write("launch: mic=\(mic) speech=\(speech) accessibility=\(ax)")

        hotkey.onPress = { [weak self] in self?.setKeyDown(true) }
        hotkey.onRelease = { [weak self] in self?.setKeyDown(false) }

        // Pre-download the speech model now so the first dictation is instant.
        engine.prepareModel()

        // Persistent watchdog: arms the hotkey, re-arms it if macOS ever revokes
        // and restores Accessibility mid-session, and logs every transition so
        // we can see exactly when/if the grant drops.
        startAccessibilityWatchdog()
        buildMenu()
    }

    private func startAccessibilityWatchdog() {
        accessibilityWatcher?.invalidate()
        accessibilityWatcher = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAccessibility() }
        }
        checkAccessibility()
    }

    private func checkAccessibility() {
        let trusted = Permissions.accessibilityTrusted(prompt: false)
        if trusted {
            let armed = hotkey.start() // idempotent; arms only if not already armed
            if !lastTrusted {
                Log.write("accessibility OK — hotkey armed=\(armed)")
                buildMenu()
            }
        } else if lastTrusted {
            Log.write("accessibility LOST — hotkey disabled (macOS revoked the grant)")
            hotkey.stop()
            buildMenu()
        }
        lastTrusted = trusted
    }

    // MARK: - Dictation flow

    /// Records the physical key state and kicks the reconciler. Key held =
    /// should be recording; key up = should be stopped + transcribed.
    private func setKeyDown(_ down: Bool) {
        Log.write(down ? "key down" : "key up")
        keyDown = down
        reconcile()
    }

    /// A single loop that drives the engine toward the desired state implied by
    /// `keyDown`, re-checking after every step. Because there's only ever one
    /// loop (the `reconciling` guard) and it re-reads `keyDown` each pass, no
    /// amount of fast mashing can leave it stuck or overlapping.
    private func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        Task { @MainActor in
            defer { reconciling = false }
            while true {
                let want = keyDown
                let state = engine.state
                if want && state == .idle {
                    do { try await engine.startListening() }
                    catch { Log.write("start error: \(error.localizedDescription)") }
                    if engine.state != .listening { break } // start aborted/failed — don't spin
                } else if !want && state != .idle {
                    let text = await engine.stopAndTranscribe()
                    Log.write("release → \(text.count) chars")
                    if text.isEmpty { NSSound.beep() } else { TextInjector.insert(text) }
                } else {
                    break // engine already matches the desired state
                }
            }
        }
    }

    // MARK: - Menu bar icon

    private func updateIcon(_ state: DictationEngine.State) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle:         symbol = "mic"
        case .listening:    symbol = "mic.fill"
        case .transcribing: symbol = "waveform"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vox")
        image?.isTemplate = (state == .idle)
        button.image = image
        button.contentTintColor = (state == .listening) ? .systemRed : nil
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Vox", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let hint = NSMenuItem(title: "Segure Control (⌃) para ditar", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let langHeader = NSMenuItem(title: "Idioma", action: nil, keyEquivalent: "")
        langHeader.isEnabled = false
        menu.addItem(langHeader)

        for lang in languages {
            let item = NSMenuItem(title: lang.title,
                                  action: #selector(selectLanguage(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = lang.identifier
            item.state = (engine.locale.identifier(.bcp47) == lang.identifier) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if !Permissions.accessibilityTrusted(prompt: false) {
            let fix = NSMenuItem(title: "Liberar Acessibilidade…",
                                 action: #selector(openAccessibility),
                                 keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }

        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        engine.locale = Locale(identifier: identifier)
        engine.invalidateModel()
        engine.prepareModel() // pre-download the newly selected language
        buildMenu()
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAccessibilityNeeded() {
        let alert = NSAlert()
        alert.messageText = "Vox precisa de Acessibilidade"
        alert.informativeText = "Pra escutar o atalho e colar o texto, libere o Vox em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Depois")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openAccessibilitySettings()
        }
    }
}
