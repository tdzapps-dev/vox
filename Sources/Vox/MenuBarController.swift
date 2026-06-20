import AppKit

@MainActor
final class MenuBarController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = DictationEngine()
    private let hotkey = HotKeyMonitor()
    private var accessibilityWatcher: Timer?
    private var lastTrusted = false
    // Serializes start/stop so overlapping or rapid press/release cycles can't
    // race each other into a corrupted (0-char / stuck) session.
    private var opChain: Task<Void, Never> = Task { @MainActor in }

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

        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.endDictation() }

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

    /// Appends an operation to the serial chain so press/release are always
    /// processed strictly in order — never overlapping.
    private func enqueue(_ op: @MainActor @escaping () async -> Void) {
        let previous = opChain
        opChain = Task { @MainActor in
            await previous.value
            await op()
        }
    }

    private func beginDictation() {
        Log.write("press")
        enqueue { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.startListening()
            } catch {
                Log.write("startListening error: \(error.localizedDescription)")
                self.updateIcon(.idle)
                NSSound.beep()
            }
        }
    }

    private func endDictation() {
        enqueue { [weak self] in
            guard let self else { return }
            let text = await self.engine.stopAndTranscribe()
            Log.write("release → \(text.count) chars")
            if text.isEmpty {
                NSSound.beep()
            } else {
                TextInjector.insert(text)
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
