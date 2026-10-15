# Changelog

## 1.0.2 (2026-10-14)

- Fixed: a stray space could appear in whatever you were typing. Dictation stops on any keypress, and at the end of every session it typed one space (so the next dictation would not run into the last word). When the session was stopped by typing, that space arrived about a second after your first key, in the middle of your text (e.g. `S D` instead of `SD`). The space is now typed only when dictation is stopped with Win+H (or the tray), and only if the session typed something. The last spoken word is still always typed. Live captions are unaffected. Existing installs: re-run `install.sh`, or replace `~/.local/share/dictation/dictate.py` with `files/dictate.py`.
- Note: if you start a new dictation straight after stopping one by typing, its first word follows your text without a space.

## 1.0.1 (2026-10-10)

- Fixed: dictation could recognise speech but type nothing for a whole session after a reboot. The typing helper (`ydotoold`) could start before `/dev/uinput` had its group permission, fail, and give up after five quick retries. Its unit now retries every 2 seconds with no limit. Existing installs: re-run `install.sh`, or add `StartLimitIntervalSec=0` under `[Unit]` and `RestartSec=2` under `[Service]` in `~/.config/systemd/user/ydotoold.service`, then `systemctl --user daemon-reload`.

## 1.0.0 (2026-10-09)

First public release.

- Offline dictation into any app (Win+H), with a floating "Listening" bar and tray icon; any key or Win+H stops it.
- Live captions (Meta+Shift+H) in a movable, resizable window that stays on top without taking focus (KDE), with A−/A+ text size, scroll-back and a Stop button; transcripts saved to `~/Transcripts/`.
- Captions hear the microphone **and** the computer's own audio, with PipeWire's WebRTC echo canceller removing speaker sound from the mic.
- Optional offline speaker-labelled transcripts (pyannote community-1, network-sandboxed, telemetry off).
- One-step `install.sh` (Debian/Ubuntu and Fedora/RHEL families) that first checks KDE Plasma 5.27+ is installed and running (`--check` runs only that), and `uninstall.sh`.
- Tested on Debian 13, AlmaLinux 10.2 and Ubuntu 26.04.1 LTS with KDE Plasma 6.3–6.6.
