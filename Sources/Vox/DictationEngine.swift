import AVFoundation
import Speech

/// Wraps macOS 26's on-device `SpeechAnalyzer` / `SpeechTranscriber`.
/// Lifecycle for one push-to-talk turn: `startListening()` while the key is
/// held, then `stopAndTranscribe()` on release returns the final transcript.
@MainActor
final class DictationEngine {

    enum State { case idle, listening, transcribing }

    private(set) var state: State = .idle
    var locale: Locale = Locale(identifier: "pt-BR")
    var onStateChange: ((State) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = ""
    private var modelTask: Task<Void, Error>?
    private var modelTaskLocaleID: String?

    // Each press gets a fresh token. If the key is released (or pressed again)
    // while a session is still spinning up — e.g. a model is still downloading —
    // the token changes and the in-flight setup aborts cleanly instead of
    // orphaning the engine in a stuck state.
    private var sessionToken = 0
    private var preparing = false

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    // MARK: - Start

    func startListening() async throws {
        guard state == .idle, !preparing else { return }
        let token = sessionToken &+ 1
        sessionToken = token
        preparing = true
        finalizedText = ""
        defer { preparing = false }

        // Model is normally pre-downloaded at launch; this is fast if so.
        do {
            try await modelInstall().value
        } catch {
            invalidateModel() // allow a retry on the next press
            throw error
        }
        // Released (or re-pressed) while the model was downloading? Abort.
        guard sessionToken == token else { return }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard sessionToken == token else { return }

        self.transcriber = transcriber
        self.analyzer = analyzer

        // Drain transcription results, keeping only finalized text.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard result.isFinal else { continue }
                    let chunk = String(result.text.characters)
                    await MainActor.run { self?.appendFinalized(chunk) }
                }
            } catch {
                // Stream ended or errored; final text already accumulated.
            }
        }

        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder

        try await analyzer.start(inputSequence: stream)
        guard sessionToken == token else {
            await teardown()
            return
        }

        try startAudioCapture(analyzerFormat: analyzerFormat)
        setState(.listening)
    }

    /// Cleanly tears the analyzer/stream/audio down without producing a result.
    /// Used when a session is aborted mid-setup.
    private func teardown() async {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        if state != .listening { setState(.idle) }
    }

    private func appendFinalized(_ chunk: String) {
        if !finalizedText.isEmpty && !chunk.isEmpty {
            finalizedText += " "
        }
        finalizedText += chunk
    }

    private func startAudioCapture(analyzerFormat: AVAudioFormat?) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let analyzerFormat else {
            throw NSError(domain: "Vox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Sem formato de áudio compatível para este idioma."])
        }

        let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let builder = self.inputBuilder, let converter else { return }

            let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }

            if error == nil && outBuffer.frameLength > 0 {
                builder.yield(AnalyzerInput(buffer: outBuffer))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Stop

    @discardableResult
    func stopAndTranscribe() async -> String {
        // Released while still spinning up (e.g. model downloading): invalidate
        // the in-flight session so it aborts, and produce nothing.
        if preparing {
            sessionToken &+= 1
            return ""
        }
        guard state == .listening else { return "" }
        setState(.transcribing)

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        inputBuilder?.finish()
        inputBuilder = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Best-effort; whatever was finalized stands.
        }

        // Drain the final segments — but never hang in .transcribing.
        await drainResults(timeout: 6)
        resultsTask?.cancel()
        resultsTask = nil

        let text = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        analyzer = nil
        transcriber = nil
        setState(.idle)
        return text
    }

    /// Awaits the results task, but gives up after `timeout` seconds so a
    /// misbehaving stream can't leave the UI stuck transcribing forever.
    private func drainResults(timeout seconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.resultsTask?.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Model assets

    /// Kicks off (or reuses) the on-device model download for the current
    /// locale. Call at launch and whenever the locale changes so the first
    /// dictation doesn't stall on a cold download.
    func prepareModel() {
        _ = modelInstall()
    }

    func invalidateModel() {
        modelTask = nil
        modelTaskLocaleID = nil
    }

    /// Shared task that completes when the current locale's model is installed.
    /// Deduplicates concurrent callers; rebuilt if the locale changed.
    private func modelInstall() -> Task<Void, Error> {
        let localeID = locale.identifier(.bcp47)
        if let task = modelTask, modelTaskLocaleID == localeID {
            return task
        }
        let locale = self.locale
        let task = Task<Void, Error> {
            try await Self.installModelIfNeeded(locale: locale)
        }
        modelTask = task
        modelTaskLocaleID = localeID
        return task
    }

    private static func installModelIfNeeded(locale: Locale) async throws {
        let target = locale.identifier(.bcp47)

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == target }) { return }

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == target }) else {
            throw NSError(domain: "Vox", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Idioma \(target) não é suportado on-device."])
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        Log.write("model: downloading \(target)…")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        Log.write("model: ready \(target)")
    }
}
