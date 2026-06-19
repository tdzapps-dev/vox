# Vox 🎙️

**Free, on-device voice dictation.** Hold a key, talk, release — your words
appear wherever the cursor is (terminal, editor, browser, any text field).

Everything runs **locally**. No audio ever leaves your machine, no API keys, no
subscription, no cloud.

- **macOS** — native menu-bar app using Apple's on-device `SpeechAnalyzer` (macOS 26).
- **Windows** — Python port using local Whisper (`faster-whisper`). See [`windows/`](windows/).

> A free, private alternative to cloud dictation tools. Tiny and focused.

<!-- Add a short screen recording here and it sells itself:
![demo](docs/demo.gif) -->

> The sections below cover the **macOS** app. For Windows, see [`windows/README.md`](windows/README.md).

## Features

- **Push-to-talk** — hold a key, speak, release. That's the whole interaction.
- **On-device** — uses Apple's `SpeechAnalyzer` (macOS 26). Private and offline.
- **Pastes anywhere** — works in terminals too (great for CLIs like Claude Code).
- **Menu-bar only** — no Dock icon, no window. A mic glyph that turns red while listening.
- **Multilingual** — switch language from the menu (ships with English + Portuguese).
- **Free & MIT-licensed.**

## Requirements

- **macOS 26 (Tahoe) or later** — required for the on-device `SpeechAnalyzer` API.
- Xcode 26 / Swift 6 toolchain to build from source.

## Install

### Build from source

```bash
git clone https://github.com/tdzapps-dev/vox.git
cd vox
./scripts/make-app.sh          # builds build/Vox.app (release)
cp -R build/Vox.app /Applications/
open /Applications/Vox.app
```

`make-app.sh` signs with your Apple Development identity if you have one (so the
macOS permission grants persist across rebuilds), and falls back to ad-hoc
signing otherwise.

If macOS blocks an ad-hoc build on first launch: right-click the app → **Open**,
or run `xattr -dr com.apple.quarantine /Applications/Vox.app`.

## Permissions (first launch)

macOS will ask for three — all required:

- **Microphone** — to capture speech.
- **Speech Recognition** — to transcribe on-device.
- **Accessibility** — to listen for the global hotkey and paste the result.
  (System Settings → Privacy & Security → Accessibility → enable Vox.)

Vox auto-arms the hotkey the moment Accessibility is granted — no restart.
The speech model for each language downloads once on first use.

## Usage

1. Click into any text field.
2. **Hold `⌃` Control**, speak, then **release**.
3. The transcribed text is pasted into the focused app.

Menu-bar icon states: `mic` idle · red `mic.fill` listening · `waveform` transcribing.

### Changing the hotkey

The trigger is a single constant in [`Sources/Vox/HotKeyMonitor.swift`](Sources/Vox/HotKeyMonitor.swift):

```swift
private let triggerKeyCode: UInt16 = 59          // 59 = Control
private let triggerFlag: NSEvent.ModifierFlags = .control
```

Set it to another modifier (e.g. `61` + `.option` for right Option) and rebuild.

## How it works

- **Hotkey** — a global `NSEvent` monitor for `flagsChanged` (Accessibility only,
  no Input Monitoring needed).
- **Capture** — `AVAudioEngine` taps the mic and converts buffers to the analyzer's format.
- **Transcription** — `SpeechAnalyzer` + `SpeechTranscriber` on-device, streaming.
- **Insertion** — copies to the pasteboard and synthesizes `⌘V`, then restores the
  previous clipboard.

Source layout:

| File | Role |
|------|------|
| `main.swift` | Entry point (menu-bar-only agent) |
| `MenuBarController.swift` | Status item, menu, dictation flow |
| `HotKeyMonitor.swift` | Push-to-talk via global key monitor |
| `DictationEngine.swift` | Audio capture + on-device `SpeechAnalyzer` |
| `TextInjector.swift` | Pasteboard + synthetic `⌘V` |
| `Permissions.swift` | Mic / speech / accessibility |

## Windows

A Python port lives in [`windows/`](windows/) — same idea (hold a key, speak,
release, paste anywhere), running Whisper locally via `faster-whisper`. It runs
from the system tray and is installed with a couple of `.bat` scripts. Full
instructions in [`windows/README.md`](windows/README.md).

## Roadmap

- Configurable hotkey from the UI (currently a one-line code change).
- Double-tap-to-lock for hands-free long-form dictation.
- Better punctuation (commas in particular) and an optional cleanup pass.

PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
