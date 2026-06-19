# Vox for Windows 🎙️

The Windows port of [Vox](../README.md) — **free, on-device voice dictation**.
Hold a key, speak, release: your words are transcribed locally and pasted
wherever the cursor is (terminal, editor, browser, any text field).

Runs entirely on your machine via [`faster-whisper`](https://github.com/SYSTRAN/faster-whisper)
(local Whisper). No audio leaves your PC, no API keys, no subscription. Lives in
the system tray.

> 🇧🇷 Guia rápido em português: [`COMO-USAR.txt`](COMO-USAR.txt)

## Requirements

- Windows 10/11
- [Python 3.11+](https://www.python.org/downloads/) — **check "Add Python to PATH"** during install.

## Install

1. Download/clone this folder.
2. Double-click **`setup.bat`** — creates a virtual env, installs dependencies,
   and downloads the speech model once (a few minutes the first time).

## Usage

1. Double-click **`run.bat`** → a 🎙️ icon appears in the system tray.
2. Click into any text field.
3. **Hold the right `Ctrl`**, speak, then **release** — the text is pasted into
   the focused app.

Switch language (English / Português) from the tray icon's right-click menu.
Quit from the same menu.

## Configuration

Edit the constants at the top of [`vox.py`](vox.py):

```python
MODEL_SIZE = "small"         # tiny | base | small | medium  (bigger = better, slower)
DEFAULT_LANGUAGE = "pt"      # pt | en
TRIGGER_KEY = Key.ctrl_r     # push-to-talk key (e.g. Key.alt_r, Key.cmd)
```

## Troubleshooting

- **Nothing happens / no tray icon** — run **`run-debug.bat`** instead; it keeps a
  console window open showing any error.
- **Text won't paste into one specific app** — that app may be running *as
  administrator*; run it normally, or run Vox as administrator too.
- **Slow transcription** — set `MODEL_SIZE = "base"` for speed (or `"medium"` for
  accuracy on a strong machine).

## Build a standalone .exe (optional)

`build_exe.bat` bundles everything into `dist\Vox.exe` with PyInstaller, so it
runs without the Python step. The speech model still downloads on first use.

## Start with Windows (optional)

Press `Win + R`, type `shell:startup`, Enter. Drop a shortcut to `run.bat` there.

## Notes

This port is community-tested but younger than the macOS app. Issues and PRs welcome.
