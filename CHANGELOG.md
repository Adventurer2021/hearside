# Changelog

## 1.0.0 (2026-10-09)

First public release.

- Offline dictation into any app (Win+H), with a floating "Listening" bar and tray icon; any key or Win+H stops it.
- Live captions (Meta+Shift+H) in a movable, resizable window that stays on top without taking focus (KDE), with A−/A+ text size, scroll-back and a Stop button; transcripts saved to `~/Transcripts/`.
- Captions hear the microphone **and** the computer's own audio, with PipeWire's WebRTC echo canceller removing speaker sound from the mic.
- Optional offline speaker-labelled transcripts (pyannote community-1, network-sandboxed, telemetry off).
- One-step `install.sh` (Debian/Ubuntu and Fedora/RHEL families) that first checks KDE Plasma 5.27+ is installed and running (`--check` runs only that), and `uninstall.sh`.
- Tested on Debian 13, AlmaLinux 10.2 and Ubuntu 26.04.1 LTS with KDE Plasma 6.3–6.6.
