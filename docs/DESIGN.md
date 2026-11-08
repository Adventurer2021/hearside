# How HearSide works

## Pieces

Everything that is the same for every user is installed once, read-only, under `/opt/hearside`; everything personal is made in each user's home at login.

| Piece | Lives in | Role |
|---|---|---|
| `hotkey_listener.py` | `/opt/hearside`, run by `hearside-hotkey.service` (systemd **user** unit in `/usr/lib/systemd/user`, enabled for everyone with `systemctl --global`, starts with each user's desktop session) | Writes that user's KWin window rules if missing (`setup-window-rules.sh`), registers **Meta+H** and **Meta+Shift+H** with KDE's global-shortcut service (kglobalaccel) over D-Bus, and launches `dictate.sh` / `dictate.sh --caption` on each press. KWin swallows the keypress. Loads no model and never reads or grabs the keyboard. |
| `dictate.py` (via `dictate.sh`) | `/opt/hearside`; logs in `~/.local/share/hearside/` | **Dictation:** one process per open bar. Loads the speech model once (~3 s; ~7 s on an i5-6400 in 8-bit mode), then listens each time the bar's 🎤, Win+H (a second run sends `SIGUSR1`) or the tray asks, typing with `ydotool`; a key press (physical keyboard or a remote-desktop keyboard) ends a listen. Closing the bar ends the process. **Captions (`--caption`):** one process per session, as before; a second run stops it. Dictation and captions have separate PID files, so they run independently. |
| `bar.py` | `/opt/hearside`, venv | The dictation bar: a frameless Qt window (app id `hearside-bar`) with 🎤, status and ✕; dragging calls the compositor's own move (`startSystemMove`). Talks to `dictate.py` over stdin/stdout (`loading/starting/listening/idle` in, `toggle/close` out) and exits when its stdin closes. |
| `captions.py` | `/opt/hearside`, venv | The caption window: an ordinary Qt window (movable, resizable, A−/A+, scroll-back, Pause/Resume, Stop). Pause/Resume clicks go to `dictate.py` as `{"pause": "toggle"}` on its stdout, and `dictate.py` answers with the new state. Exit code 0 (user closed it) tells `dictate.py` to stop. While paused, the microphone keeps being read but its audio is thrown away: the recognizer gets nothing and the saved recording gets silence, so the speaker-labelled transcript's times still match. |
| `setup-window-rules.sh` | run per user at login | Two KWin rules, keyed on app ids `hearside-bar` and `hearside-captions`: keep above, never accept focus, skip switcher/pager (and the task bar for the bar), remember position (and size for captions). Versioned, so it only writes when a rule is missing or out of date. |
| `captions-echo-cancel.conf` | `/opt/hearside` | A private `pipewire -c` process started per captions session: PipeWire's WebRTC echo canceller in monitor mode, producing the source `captions_aec_source` (mic minus what the speakers play). |
| `speakers.sh` → `diarize.py` → `label_speakers.py` | `/opt/hearside`; `speakers-venv` for pyannote | After a captions session: who-spoke-when, then per-turn re-transcription, inside a network-less sandbox, as the user. |
| `hearside-ydotoold.service` | systemd user unit, global | The daemon `ydotool` types through (`/dev/uinput`, which the `input` group may use via `99-uinput.rules`), one per logged-in user on `$XDG_RUNTIME_DIR/.ydotool_socket`. |
| Models | `/opt/hearside/hf` (`HF_HOME`); the 8-bit model as `/opt/hearside/model-int8.pt` | Downloaded or copied by the installer as root; loaded with `HF_HUB_OFFLINE=1`, so sessions make no network calls. |

Both user units carry `ConditionGroup=input` (only accounts set up for HearSide run them) and `ConditionPathExists=!%h/.config/systemd/user/<old unit>`, so a user who still has a 1.0.x per-user install keeps using it and the two never run at once.

## Audio path for captions

```
default mic ──► WebRTC echo canceller ◄── speaker output (reference)
                      │
              captions_aec_source ──┐
                                    ├── mixed ──► live speech recognition ──► caption window + transcript
@DEFAULT_MONITOR@ (computer audio) ─┘
                                    └── stereo .wav (left: mic, right: computer) ──► speaker labelling
```

- The mic stream is the clock. Computer audio is taken in step with it (silence if none arrived), with the backlog capped at 0.5 s so the two stay in sync.
- Without the canceller, a remote voice reaches captions twice (directly, and through the speakers, the room and the mic), which doubles words and invents an extra "speaker". Measured with a speech recording played aloud on a desktop: raw mic 1050 vs echo-cancelled 18 (35 dB), below the room's noise floor. Local speech still passes.
- If the canceller can't start, captions log it and use the plain mic.

## Long sessions

Live recognition restarts at a quiet moment about every 2 minutes (`CAPTION_SEGMENT_SECONDS`), so the cost per word doesn't grow over an hour-long call. A new line in the transcript starts at each pause of 2.5 s or more, or at a sentence end after 400 characters. The transcript is flushed after every word, and the `.wav` header is re-patched every 5 s, so a crash loses nothing.

## Speaker labelling

1. `diarize.py` runs pyannote community-1 on the recording (passed as an in-memory waveform, so no ffmpeg/torchcodec decoding) and keeps its *exclusive* output, where overlaps are resolved to one speaker. The analysis window is stepped 2.5 s instead of the default 1 s. On a 20-thread i9, with a 10-minute two-voice test: 1 s = 0.41× real time, 2.5 s = 0.18× at the same 99.7% of speech labelled correctly, 5 s = 0.08× but 99.1%.
2. With a stereo recording, a speaker whose turns come from both channels is split in two: someone in the room (mic channel) can't be someone on the call (computer channel). This catches short phrases that voice matching alone merges.
3. `label_speakers.py` merges consecutive turns by the same speaker (gap ≤ 1 s) and re-transcribes each turn with the same speech model in **non-streaming** mode, which hears whole sentences and is more accurate than the live captions. Turns over 30 s are cut at their quietest moment.
4. Both steps run in `unshare --user --net` or, where that's blocked (Ubuntu's `kernel.apparmor_restrict_unprivileged_userns=1`), `bwrap --unshare-net`. If neither is available, `speakers.sh` refuses to run. pyannote's telemetry (file duration and speaker counts to `otel.pyannote.ai`) is switched off in its saved config and by `PYANNOTE_METRICS_ENABLED=0`, and the sandbox would block it anyway. The pip install also brings `pyannoteai-sdk`, pyannote's cloud client; nothing here uses it.
5. Jobs run one at a time (`flock`), at `nice 10`, with all CPU cores but two.

## Design decisions learned the hard way

- **Never grab the keyboard** (`EVIOCGRAB`). An early version did, and KDE's lock screen then couldn't read the real keyboard, so the password couldn't be typed. The listener leaves the keyboard alone; dictation's "any key stops" watcher only reads it, and captions don't touch it at all.
- **No always-running model daemon.** An early version that kept the model loaded all the time leaked CPU (200–670%) after sessions, so 1.0 loaded it fresh for each session. 1.1's dictation bar keeps the model only while the bar is open; measured after 14 hours open on three machines: 0% CPU while idle (memory 2.3–3.3 GB). Closing the bar ends the process.
- **One install, per-user sessions.** Win+H must type into the desktop of whoever is at the screen, so the hotkey listener and `ydotoold` run inside each user's session (global user units), while everything heavy is shared and read-only in `/opt/hearside`.
- **A user session kept alive skips new services.** With an SSH connection open, the user's systemd manager survives logout, so new global units and a new `input` group membership aren't picked up. The installer advises a restart; `remove-per-user-install.sh` starts the shared services itself.
- **Remote-desktop keyboards count as typing.** Typing through RustDesk arrives on its virtual keyboard ("RustDesk UInput Keyboard"), which 1.0 ignored along with ydotool's own; 1.1 watches it, but skips lone modifier keys, which remote-desktop tools send to sync keyboard state.
- **KDE "Command" custom shortcuts were unreliable** for launching this (their systemd-run units often never ran). Registering through kglobalaccel's D-Bus API works reliably.
- **The listener follows the desktop session** (`PartOf=graphical-session.target`, plus a restart whenever kglobalaccel's D-Bus owner changes). Otherwise, after logout and login with user linger on, KWin holds the shortcut but marks it inactive.
- **`parecord --latency-msec=50` is essential.** By default audio arrives in ~2 s bursts, which makes every word lag.
- **Last-word bug:** the stock `TextIteratorStreamer` holds the last word back until the next one starts. A custom streamer emits each word immediately, with clean end-of-stream handling.
- **Dictation's bar must never take focus**, or typing breaks. 1.0 used a layer-shell overlay (Wayland) or an override-redirect window (X11), which can't be dragged smoothly. 1.1's bar is an ordinary frameless window like the caption window, with a KWin rule supplying "on top, never focused"; clicking its 🎤 leaves the cursor in the text field on both Wayland and X11 (tested).
- **Copying the gated model between machines needs `tar -h`.** huggingface_hub 1.x stores the real files in a shared blob store outside the model's folder.
