# Changelog

## 1.2.1 (2026-11-07)

- **HearSide branding:** the name is now written HearSide everywhere. The dictation bar and the caption window show a small italic small-caps HearSide wordmark; every notification is headed HearSide; window titles, tray tooltips and the menu entries say HearSide. The GitHub address and install folders stay lowercase `hearside`, so nothing moves.
- **Narrower dictation bar:** its text is stacked (HearSide, then the state, then a short hint such as "Win+H or any key to stop") instead of one long line. The X11 listening notification is shorter too.
- "Speaker-labeled transcript ready" (US spelling).
- **Upgrading from 1.2.0:** download **hearside-1.2.1.tar.gz**, unpack it and run `sudo ./install.sh` (settings, models and transcripts are kept). Then close the dictation bar and stop captions if they are open, and start them again.

## 1.2.0 (2026-11-06)

- **Pause for live captions:** a **⏸ Pause / ▶ Resume** button in the caption window, also in the tray icon's right-click menu (a left click still stops). While paused, nothing is heard, captioned or recorded, and the window stays open. Resume continues the same transcript, which gets a line such as `[paused 10:42:05 – 10:55:31]` (or `– stopped]` if captions were stopped while paused). The speaker-labelled transcript skips the paused part: the recording holds silence there, so its times stay in step.

## 1.1.0 (2026-10-21)

**Installed once for every user** of the computer, like Win+H on Windows, and a **Windows-style dictation bar**.

- **Shared install:** `sudo ./install.sh` puts the program, its Python environment and the models in `/opt/hearside` once (~6–7 GB in total, instead of ~7 GB per user). Every regular account is set up (`--users` to choose), the hotkey and typing services start at each user's login, and each user's logs, transcripts, shortcuts and window rules are made automatically at their first login. Re-running the installer sets up accounts added since. The 8-bit model is prepared once for everyone; machine settings live in `/opt/hearside/hearside.env`, per-user overrides still in `~/.config/voice-dictation.env`.
- **Dictation bar:** Win+H opens a small bar and starts listening. Its 🎤 button, Win+H or the tray icon start and stop listening; typing any key pauses it; the bar stays until its ✕ is clicked. It can be dragged anywhere and reopens in the same place, and never takes keyboard focus. The speech model stays loaded while the bar is open (about 3.3 GB of memory, 2.3 GB in 8-bit mode; no CPU while idle), so listening starts at once instead of after a model load. Also in the application menu as **Dictation (HearSide)**.
- **Remote desktops:** typing through a RustDesk session now pauses dictation too (its virtual keyboard used to be ignored). Lone Shift/Ctrl/Alt/lock-key presses never pause it. The README explains how to dictate into a remote-desktop window with your own computer's microphone.
- The dictation bar and the caption window are now ordinary Qt windows on both Wayland and X11, kept on top and focus-free by KWin rules; `gtk4-layer-shell` is no longer needed (or built from source on AlmaLinux/RHEL).
- **Moving over from 1.0.x:** install 1.1.0 with `--speaker-model-from ~/.cache/huggingface/hub` (the speech model is reused from the old install automatically, so nothing big is downloaded), then each user runs `./remove-per-user-install.sh`. It removes the old copy, its services, its menu entries and, if wanted, its model files (including ones kept in Hugging Face's shared blob store), keeps transcripts and personal settings, and starts the shared HearSide at once. Until then the old copy keeps working and the shared one stays out of its way.
- Installer: the recommended 8-bit question defaults to yes (`[Y/n]`); SELinux labels are restored on installed files; it ends by advising a restart, since a user session kept alive (for example by an SSH connection) would otherwise keep the old services and groups.
- `sudo ./uninstall.sh` removes the shared install for everyone and keeps every user's transcripts.
- Tested on Debian 13 (four machines, including a laptop used by two accounts), AlmaLinux 10.2 (SELinux enforcing) and Kubuntu 26.04 on X11.

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
