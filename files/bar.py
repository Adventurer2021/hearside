#!/usr/bin/env python3
"""Dictation bar for dictate.py (Win+H), like the Windows 11 voice typing bar: a small
floating bar with a microphone button that starts and stops listening, and a close
button. It stays on screen between dictations until closed, and can be dragged anywhere.

An ordinary frameless window (Wayland and X11 alike). A KWin rule
(setup-window-rules.sh) keeps it above other windows, out of the task bar and
switcher, never lets it take keyboard focus (so clicking the microphone leaves the
cursor in the text field being dictated into) and remembers where it was dragged.

Talks to dictate.py over stdin/stdout, one word per line:
  in:  loading | starting | listening | idle      (what dictation is doing)
  out: toggle | close                              (what the user clicked)
Exits when stdin closes, so it can't outlive dictation. Runs in the Hearside venv (PySide6)."""
import os
import sys

from PySide6.QtCore import QSocketNotifier, Qt, QTimer
from PySide6.QtWidgets import QApplication, QHBoxLayout, QLabel, QPushButton, QWidget

APP_ID = "hearside-bar"  # Wayland app_id / X11 class; the KWin rule matches on it

STYLE = """
QWidget#pill { background: rgba(28, 28, 30, 235); border-radius: 20px; }
QLabel { color: #ffffff; background: transparent; }
QLabel#title { font-weight: bold; }
QLabel#hint { color: #c7c7cc; font-size: 11px; }
QLabel#grip { color: #8e8e93; font-size: 14px; }
QPushButton { border: none; color: #ffffff; background: transparent; }
QPushButton#mic { background: #3a3a3c; border-radius: 16px; font-size: 16px; min-width: 32px; min-height: 32px; }
QPushButton#mic:hover { background: #4a4a4c; }
QPushButton#mic[live="true"] { background: #d70015; }
QPushButton#mic[live="true"]:hover { background: #ff3b30; }
QPushButton#mic:disabled { background: #2c2c2e; color: #636366; }
QPushButton#close { font-size: 15px; color: #c7c7cc; min-width: 22px; }
QPushButton#close:hover { color: #ffffff; }
"""

STATES = {
    "loading": ("Loading dictation…", "the first start takes a few seconds"),
    "starting": ("Starting…", ""),
    "listening": ("Listening", "click the mic, Win+H or any key to stop"),
    "idle": ("Dictation paused", "click the mic or Win+H to talk"),
}


def send(word: str) -> None:
    try:
        print(word, flush=True)
    except (BrokenPipeError, ValueError):
        pass


class Bar(QWidget):
    def __init__(self):
        flags = Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.Tool
        super().__init__(None, flags)
        self.setWindowTitle("Dictation")
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setFocusPolicy(Qt.NoFocus)

        pill = QWidget(self)
        pill.setObjectName("pill")
        row = QHBoxLayout(pill)
        row.setContentsMargins(10, 6, 8, 6)
        row.setSpacing(10)

        grip = QLabel("⠿")
        grip.setObjectName("grip")
        grip.setToolTip("Drag to move")
        self.mic = QPushButton("🎤")
        self.mic.setObjectName("mic")
        self.mic.setToolTip("Start or stop listening (Win+H)")
        self.title = QLabel()
        self.title.setObjectName("title")
        self.hint = QLabel()
        self.hint.setObjectName("hint")
        texts = QWidget()
        col = QHBoxLayout(texts)
        col.setContentsMargins(0, 0, 0, 0)
        col.setSpacing(8)
        col.addWidget(self.title)
        col.addWidget(self.hint)
        close = QPushButton("✕")
        close.setObjectName("close")
        close.setToolTip("Close the dictation bar")

        # The bar must never take keyboard focus away from the app being dictated into.
        for w in (grip, self.mic, self.title, self.hint, texts, close, pill):
            w.setFocusPolicy(Qt.NoFocus)
        self.mic.clicked.connect(lambda: send("toggle"))
        close.clicked.connect(self.close)

        row.addWidget(grip)
        row.addWidget(self.mic)
        row.addWidget(texts)
        row.addSpacing(4)
        row.addWidget(close)
        outer = QHBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(pill)

        self.pulse_on = False
        self.pulse = QTimer(self)
        self.pulse.timeout.connect(self.blink)
        self.set_state("loading")

    def set_state(self, state: str) -> None:
        if state not in STATES:
            return
        title, hint = STATES[state]
        self.title.setText(title)
        self.hint.setText(hint)
        live = state == "listening"
        self.mic.setEnabled(state in ("listening", "idle"))
        self.mic.setProperty("live", "true" if live else "false")
        self.mic.style().unpolish(self.mic)
        self.mic.style().polish(self.mic)
        if live:
            self.pulse.start(700)
        else:
            self.pulse.stop()
            self.title.setStyleSheet("")
        self.adjustSize()

    def blink(self) -> None:
        self.pulse_on = not self.pulse_on
        self.title.setStyleSheet("color: #ff6961;" if self.pulse_on else "")

    # Dragging anywhere on the bar (except the buttons) moves it. The compositor does the
    # move, so it is smooth on Wayland too, and the KWin rule remembers the new place.
    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.LeftButton and self.windowHandle() is not None:
            self.windowHandle().startSystemMove()

    def closeEvent(self, event) -> None:
        send("close")
        event.accept()


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_ID)  # X11 window class, for the KWin rule
    app.setDesktopFileName(APP_ID)  # Wayland app_id
    app.setApplicationDisplayName("Dictation")
    app.setStyleSheet(STYLE)
    bar = Bar()

    fd = sys.stdin.fileno()
    pending = [b""]

    def on_stdin() -> None:
        data = os.read(fd, 4096)
        if not data:
            notifier.setEnabled(False)
            app.exit(2)  # dictation ended
            return
        *lines, pending[0] = (pending[0] + data).split(b"\n")
        for line in lines:
            bar.set_state(line.decode(errors="replace").strip())

    notifier = QSocketNotifier(fd, QSocketNotifier.Read)
    notifier.activated.connect(on_stdin)
    bar.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
