"""
Vox (Windows) — ditado por voz on-device.

Segura a tecla (Ctrl direito por padrão), fala, solta: o áudio é transcrito
localmente com faster-whisper (Whisper) e colado onde o cursor estiver.
Nada sai da máquina. Roda na bandeja do sistema (system tray).

Mesma pegada do app nativo do Mac, mas em Python pra rodar no Windows.
"""

import sys
import time
import threading

import numpy as np
import sounddevice as sd
import pyperclip
from pynput import keyboard
from pynput.keyboard import Controller, Key
import pystray
from PIL import Image, ImageDraw
from faster_whisper import WhisperModel

# ------------------------------------------------------------------ config ---
SAMPLE_RATE = 16000          # Whisper espera 16 kHz
MODEL_SIZE = "small"         # tiny | base | small | medium  (small = bom equilíbrio)
DEFAULT_LANGUAGE = "pt"      # pt | en
TRIGGER_KEY = Key.ctrl_r     # tecla push-to-talk (Ctrl direito)

PASTE_MOD = Key.cmd if sys.platform == "darwin" else Key.ctrl  # ⌘V no Mac, Ctrl+V no Windows

COLORS = {
    "idle": (170, 170, 175, 255),
    "listening": (235, 64, 52, 255),
    "transcribing": (90, 140, 255, 255),
}


class Vox:
    def __init__(self):
        self.recording = False
        self.frames = []
        self.stream = None
        self.lock = threading.Lock()
        self.kb = Controller()
        self.language = DEFAULT_LANGUAGE
        self.icon = None

        print(f"[Vox] carregando modelo '{MODEL_SIZE}' (1ª vez baixa, aguarde)...")
        self.model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
        print("[Vox] modelo pronto. Segure Ctrl direito e fale.")

    # ---------------------------------------------------------------- audio ---
    def _audio_callback(self, indata, frames, time_info, status):
        if self.recording:
            self.frames.append(indata.copy())

    def start_recording(self):
        with self.lock:
            if self.recording:
                return
            self.recording = True
            self.frames = []
            self.stream = sd.InputStream(
                samplerate=SAMPLE_RATE, channels=1,
                dtype="float32", callback=self._audio_callback,
            )
            self.stream.start()
        self._set_state("listening")

    def stop_and_transcribe(self):
        with self.lock:
            if not self.recording:
                return
            self.recording = False
            if self.stream is not None:
                self.stream.stop()
                self.stream.close()
                self.stream = None
            frames = self.frames
            self.frames = []

        self._set_state("transcribing")
        threading.Thread(target=self._transcribe, args=(frames,), daemon=True).start()

    def _transcribe(self, frames):
        try:
            if not frames:
                return
            audio = np.concatenate(frames, axis=0).flatten().astype(np.float32)
            if audio.size < SAMPLE_RATE // 4:  # < 0,25s: provavelmente toque acidental
                return
            segments, _ = self.model.transcribe(audio, language=self.language, beam_size=1)
            text = "".join(seg.text for seg in segments).strip()
            if text:
                self._paste(text)
        except Exception as exc:
            print("[Vox] erro na transcrição:", exc)
        finally:
            self._set_state("idle")

    # ---------------------------------------------------------------- paste ---
    def _paste(self, text):
        previous = None
        try:
            previous = pyperclip.paste()
        except Exception:
            pass

        pyperclip.copy(text)
        time.sleep(0.05)
        self.kb.press(PASTE_MOD)
        self.kb.press("v")
        self.kb.release("v")
        self.kb.release(PASTE_MOD)

        if previous is not None:
            def restore():
                time.sleep(0.4)
                try:
                    pyperclip.copy(previous)
                except Exception:
                    pass
            threading.Thread(target=restore, daemon=True).start()

    # --------------------------------------------------------------- hotkey ---
    def on_press(self, key):
        if key == TRIGGER_KEY:
            self.start_recording()

    def on_release(self, key):
        if key == TRIGGER_KEY:
            self.stop_and_transcribe()

    # ----------------------------------------------------------------- tray ---
    @staticmethod
    def _make_icon(color):
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        draw.rounded_rectangle((26, 10, 38, 38), radius=6, fill=color)  # cápsula do mic
        draw.arc((20, 22, 44, 46), start=0, end=180, fill=color, width=4)  # suporte
        draw.line((32, 46, 32, 54), fill=color, width=4)                   # haste
        draw.line((24, 56, 40, 56), fill=color, width=4)                   # base
        return img

    def _set_state(self, state):
        if self.icon is None:
            return
        self.icon.icon = self._make_icon(COLORS.get(state, COLORS["idle"]))
        self.icon.title = f"Vox — {state}"

    def _choose_language(self, lang):
        def handler(icon, item):
            self.language = lang
        return handler

    def run(self):
        listener = keyboard.Listener(on_press=self.on_press, on_release=self.on_release)
        listener.start()

        menu = pystray.Menu(
            pystray.MenuItem("Vox — segure Ctrl direito p/ ditar", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Português", self._choose_language("pt"),
                             checked=lambda i: self.language == "pt", radio=True),
            pystray.MenuItem("English", self._choose_language("en"),
                             checked=lambda i: self.language == "en", radio=True),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Sair", lambda icon, item: icon.stop()),
        )
        self.icon = pystray.Icon("vox", self._make_icon(COLORS["idle"]), "Vox", menu)
        self.icon.run()


if __name__ == "__main__":
    Vox().run()
