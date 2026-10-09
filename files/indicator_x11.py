#!/usr/bin/env python3
"""Floating "listening" bar for X11 sessions (the Wayland version is indicator.py).
An override-redirect tooltip-type window: the window manager never manages or
focuses it, it never requests focus itself, and it is transparent to the mouse,
so it can't take the keyboard from the app being dictated into. Reads state
lines ("listening") on stdin and exits when stdin closes. Runs under the
dictation venv's Python (PySide6)."""
import os
import sys

from PySide6.QtCore import QSocketNotifier, Qt, QTimer
from PySide6.QtWidgets import QApplication, QHBoxLayout, QLabel, QWidget

if not os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
    sys.exit("indicator_x11: not an X11 session - bar disabled")

PILL = "background: rgba(28, 28, 30, 230); border-radius: 18px;"
DOT_IDLE = "color: #8e8e93; font-size: 15px; background: transparent;"
DOT_LIVE = "color: #ff3b30; font-size: 15px; background: transparent;"
DOT_DIM = "color: #5a1a17; font-size: 15px; background: transparent;"
TITLE = "color: #ffffff; font-weight: bold; background: transparent;"
HINT = "color: #c7c7cc; font-size: 11px; background: transparent;"


def main() -> None:
    app = QApplication(sys.argv)
    flags = (
        Qt.ToolTip
        | Qt.FramelessWindowHint
        | Qt.WindowStaysOnTopHint
        | Qt.WindowDoesNotAcceptFocus
        | Qt.X11BypassWindowManagerHint
    )
    win = QWidget(None, flags)
    win.setAttribute(Qt.WA_ShowWithoutActivating)
    win.setAttribute(Qt.WA_TransparentForMouseEvents)
    win.setAttribute(Qt.WA_TranslucentBackground)
    win.setFocusPolicy(Qt.NoFocus)

    pill = QWidget(win)
    pill.setStyleSheet(PILL)
    row = QHBoxLayout(pill)
    row.setContentsMargins(16, 6, 16, 6)
    row.setSpacing(8)
    dot = QLabel("●")
    dot.setStyleSheet(DOT_IDLE)
    title = QLabel("Loading dictation…")
    title.setStyleSheet(TITLE)
    hint = QLabel("")
    hint.setStyleSheet(HINT)
    for w in (dot, title, hint):
        w.setFocusPolicy(Qt.NoFocus)
        row.addWidget(w)
    outer = QHBoxLayout(win)
    outer.setContentsMargins(0, 0, 0, 0)
    outer.addWidget(pill)

    def place() -> None:
        win.adjustSize()
        screen = app.primaryScreen().geometry()
        win.move(screen.x() + (screen.width() - win.width()) // 2, screen.y() + 10)

    pulse_on = [True]
    pulse = QTimer()

    def toggle_pulse() -> None:
        pulse_on[0] = not pulse_on[0]
        dot.setStyleSheet(DOT_LIVE if pulse_on[0] else DOT_DIM)

    pulse.timeout.connect(toggle_pulse)

    def on_stdin() -> None:
        data = os.read(sys.stdin.fileno(), 4096)
        if not data:
            app.quit()
            return
        if b"listening" in data:
            dot.setStyleSheet(DOT_LIVE)
            title.setText("Listening")
            hint.setText("Win+H or any key to stop")
            place()
            pulse.start(600)

    notifier = QSocketNotifier(sys.stdin.fileno(), QSocketNotifier.Read)
    notifier.activated.connect(on_stdin)

    place()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
