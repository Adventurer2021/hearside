#!/usr/bin/env python3
"""Live caption window for dictate.py --caption. An ordinary window, so it can
be moved and resized like any other; a KWin rule (setup-caption-window-rule.sh)
keeps it above other windows, stops it ever taking keyboard focus (typing
always reaches the app being worked in) and remembers its position and size.
A-/A+ change the text size, which is remembered in ~/.config/voice-captions.json.
Scrolling up reads back through earlier captions; new text only jumps the view
back down when it was already at the bottom.

Reads JSON lines on stdin ({"state": ...}, {"text": ...}, {"newline": true}).
Exits when stdin closes, so it can't outlive the captions process. Exit code 0
means the user closed the window, which dictate.py treats as "stop captions".
Runs in the dictation venv (PySide6)."""
import json
import os
import sys

from PySide6.QtCore import QSocketNotifier, Qt
from PySide6.QtGui import QFont, QTextCursor
from PySide6.QtWidgets import (QApplication, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton, QVBoxLayout,
                               QWidget)

APP_ID = "hearside-captions"  # Wayland app_id; the KWin rule matches on it
SETTINGS = os.path.expanduser("~/.config/voice-captions.json")
DEFAULT_FONT_PX = int(os.environ.get("CAPTION_FONT_SIZE", "22"))
FONT_MIN, FONT_MAX, FONT_STEP = 12, 72, 2
DEFAULT_SIZE = (1000, 190)
KEEP_PARAGRAPHS = 500  # scroll-back limit; the full text is always in the transcript file

STYLE = """
QWidget#root { background: #000000; }
QLabel#status { color: #8e8e93; font-size: 13px; }
QLabel#status[live="true"] { color: #ff453a; }
QPlainTextEdit { background: #000000; color: #ffffff; border: none; }
QPushButton { background: #1c1c1e; color: #ffffff; border: 1px solid #3a3a3c; border-radius: 6px;
              padding: 2px 10px; font-size: 13px; }
QPushButton:hover { background: #2c2c2e; }
QPushButton#stop { background: #3a0d0b; border-color: #ff453a; }
QPushButton#stop:hover { background: #5c1410; }
QScrollBar:vertical { background: #000000; width: 8px; }
QScrollBar::handle:vertical { background: #3a3a3c; border-radius: 4px; min-height: 30px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
"""


def load_font_px() -> int:
    try:
        with open(SETTINGS) as f:
            return max(FONT_MIN, min(FONT_MAX, int(json.load(f)["font_px"])))
    except (OSError, ValueError, KeyError, TypeError):
        return DEFAULT_FONT_PX


def save_font_px(px: int) -> None:
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"font_px": px}, f)
    os.replace(tmp, SETTINGS)


class CaptionWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setObjectName("root")
        self.setWindowTitle("Live Captions")
        self.resize(*DEFAULT_SIZE)

        self.status = QLabel("● Captions — loading…")
        self.status.setObjectName("status")
        smaller = QPushButton("A−")
        larger = QPushButton("A+")
        smaller.setToolTip("Smaller text")
        larger.setToolTip("Larger text")
        stop = QPushButton("■ Stop")
        stop.setObjectName("stop")
        stop.setToolTip("Stop captions and save the transcript")
        # The window never takes keyboard focus, so the buttons mustn't try to either.
        for b in (smaller, larger, stop):
            b.setFocusPolicy(Qt.NoFocus)
        smaller.clicked.connect(lambda: self.change_font(-FONT_STEP))
        larger.clicked.connect(lambda: self.change_font(FONT_STEP))
        # Exit code 0 is what closing the window gives; dictate.py treats it as "stop captions".
        stop.clicked.connect(self.close)
        top = QHBoxLayout()
        top.addWidget(self.status)
        top.addStretch(1)
        top.addWidget(smaller)
        top.addWidget(larger)
        top.addSpacing(10)
        top.addWidget(stop)

        self.text = QPlainTextEdit()
        self.text.setReadOnly(True)
        self.text.setFocusPolicy(Qt.NoFocus)
        self.text.setTextInteractionFlags(Qt.NoTextInteraction)
        self.text.setMaximumBlockCount(KEEP_PARAGRAPHS)
        self.text.setLineWrapMode(QPlainTextEdit.WidgetWidth)
        self.font_px = load_font_px()
        self.apply_font()

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 8, 14, 10)
        layout.setSpacing(6)
        layout.addLayout(top)
        layout.addWidget(self.text, 1)

    def apply_font(self) -> None:
        font = QFont(self.text.font())
        font.setPixelSize(self.font_px)
        self.text.setFont(font)

    def change_font(self, step: int) -> None:
        px = max(FONT_MIN, min(FONT_MAX, self.font_px + step))
        if px == self.font_px:
            return
        self.font_px = px
        self.apply_font()
        self.scroll_to_end()
        try:
            save_font_px(px)
        except OSError as exc:
            print(f"captions: could not save text size: {exc!r}", file=sys.stderr)

    def at_bottom(self) -> bool:
        bar = self.text.verticalScrollBar()
        return bar.value() >= bar.maximum() - 2

    def scroll_to_end(self) -> None:
        bar = self.text.verticalScrollBar()
        bar.setValue(bar.maximum())

    def apply(self, msg: dict) -> None:
        if msg.get("state") == "listening":
            self.status.setText("● Live captions")
            self.status.setProperty("live", "true")
            self.status.style().unpolish(self.status)
            self.status.style().polish(self.status)
        follow = self.at_bottom()
        cursor = self.text.textCursor()
        cursor.movePosition(QTextCursor.End)
        if msg.get("newline") and not self.text.document().isEmpty():
            cursor.insertText("\n")
        if "text" in msg:
            cursor.insertText(msg["text"])
        if follow:
            self.scroll_to_end()


def main() -> None:
    app = QApplication(sys.argv)
    app.setDesktopFileName(APP_ID)
    app.setApplicationDisplayName("Live Captions")
    app.setStyleSheet(STYLE)
    win = CaptionWindow()

    fd = sys.stdin.fileno()
    pending = [b""]

    def on_stdin() -> None:
        data = os.read(fd, 65536)
        if not data:
            notifier.setEnabled(False)
            app.exit(2)  # captions process ended: not a user close
            return
        *lines, pending[0] = (pending[0] + data).split(b"\n")
        for line in lines:
            try:
                win.apply(json.loads(line))
            except ValueError:
                continue

    notifier = QSocketNotifier(fd, QSocketNotifier.Read)
    notifier.activated.connect(on_stdin)
    win.show()
    sys.exit(app.exec())  # 0 = window closed by the user


if __name__ == "__main__":
    main()
