#!/usr/bin/env python3
"""Always-running listener: registers Meta+H (dictation) and Meta+Shift+H
(live captions) with KDE's global shortcut service (kglobalaccel) and
launches dictate.sh each time one fires. KWin consumes the keypress, so no
stray "h" reaches the focused app. Loads no AI model, reads no keyboard
devices and never grabs input. The shortcuts show up in System Settings >
Shortcuts under "Voice Dictation" and can be changed there."""
import datetime
import os
import signal
import subprocess
import sys

from PySide6.QtCore import SLOT, QCoreApplication, QObject, QTimer, Slot
from PySide6.QtDBus import QDBusConnection, QDBusServiceWatcher

STATE_DIR = os.path.expanduser("~/.local/share/dictation")
DICTATE_SCRIPT = os.path.join(STATE_DIR, "dictate.sh")
TIMELINE_LOG = os.path.join(STATE_DIR, "timeline.log")

COMPONENT = "voice-dictation"
QT_META, QT_SHIFT, QT_KEY_H = 0x10000000, 0x02000000, 0x48
# action -> (friendly name, default key, extra dictate.sh arguments)
ACTIONS = {
    "toggle-dictation": ("Start/stop dictation", QT_META | QT_KEY_H, []),
    "toggle-captions": ("Start/stop live captions", QT_META | QT_SHIFT | QT_KEY_H, ["--caption"]),
}
SET_DEFAULT = "1"
SET_PRESENT = "2"


def log(event: str) -> None:
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    with open(TIMELINE_LOG, "a") as f:
        f.write(f"{ts} [listener] {event}\n")


def kglobalaccel(path: str, interface: str, method: str, signature: str, *args: str) -> str:
    result = subprocess.run(
        ["busctl", "--user", "--timeout=5", "call", "org.kde.kglobalaccel", path, interface, method, signature, *args],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def kga(method: str, signature: str, *args: str) -> str:
    return kglobalaccel("/kglobalaccel", "org.kde.KGlobalAccel", method, signature, *args)


def action_id_args(action: str) -> list[str]:
    action_id = [COMPONENT, action, "Voice Dictation", ACTIONS[action][0]]
    return [str(len(action_id)), *action_id]


class ShortcutReceiver(QObject):
    @Slot(str, str, "qlonglong")
    def on_pressed(self, _component: str, action: str, _timestamp: int) -> None:
        if action not in ACTIONS:
            return
        extra = ACTIONS[action][2]
        log(f"shortcut {action} pressed (kglobalaccel) -> launching dictate.sh {' '.join(extra)}".rstrip())
        subprocess.Popen([DICTATE_SCRIPT, *extra])


def main() -> None:
    for action, (_name, key, _extra) in ACTIONS.items():
        args = action_id_args(action)
        kga("doRegister", "as", *args)
        kga("setShortcut", "asaiu", *args, "1", str(key), SET_DEFAULT)
        # Without NoAutoloading, kglobalaccel keeps a key the user picked in System Settings.
        active_keys = kga("setShortcut", "asaiu", *args, "1", str(key), SET_PRESENT)
        log(f"registered {action} with kglobalaccel: keys={active_keys}")
        if active_keys.split()[1] == "0":
            log(f"WARNING: kglobalaccel assigned no key to {action} - shortcut is taken by something else")
    component_path = kga("getComponent", "s", COMPONENT).split()[-1].strip('"')
    log(f"kglobalaccel component path={component_path}")

    # Registration above needs real exit codes; after this, children are auto-reaped
    # so finished dictate.sh processes don't linger as zombies.
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    app = QCoreApplication(sys.argv)
    receiver = ShortcutReceiver()
    connected = QDBusConnection.sessionBus().connect(
        "org.kde.kglobalaccel", component_path, "org.kde.kglobalaccel.Component", "globalShortcutPressed",
        receiver, SLOT("on_pressed(QString,QString,qlonglong)"),
    )
    if not connected:
        log("ERROR: could not subscribe to kglobalaccel shortcut signal")
        sys.exit(1)

    # A restarted kglobalaccel (new KDE session, KWin restart) keeps our shortcut but
    # marks it inactive until re-registered. Exit non-zero so systemd restarts us fresh.
    def on_owner_changed(_name: str, _old_owner: str, new_owner: str) -> None:
        log(f"kglobalaccel owner changed (new owner={new_owner or 'none'}) - restarting to re-register")
        app.exit(3)

    watcher = QDBusServiceWatcher(
        "org.kde.kglobalaccel", QDBusConnection.sessionBus(), QDBusServiceWatcher.WatchForOwnerChange
    )
    watcher.serviceOwnerChanged.connect(on_owner_changed)

    def shutdown(signum, _frame):
        log(f"received signal {signum}, marking shortcuts inactive and exiting")
        for action in ACTIONS:
            kga("setInactive", "as", *action_id_args(action))
        app.quit()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    # Qt's event loop doesn't return to Python on its own; this lets signal handlers run.
    tick = QTimer()
    tick.timeout.connect(lambda: None)
    tick.start(500)

    log("listening for Meta+H and Meta+Shift+H via kglobalaccel")
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
