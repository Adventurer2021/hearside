# How Hearside works

## Pieces

| Piece | Lives in | Role |
|---|---|---|
| `hotkey_listener.py` | `~/.local/share/dictation/`, run by `dictation-hotkey.service` (systemd user unit, starts with the desktop session) | Registers **Meta+H** and **Meta+Shift+H** with KDE's global-shortcut service (kglobalaccel) over D-Bus, and launches `dictate.sh` / `dictate.sh --caption` on each press. KWin swallows the keypress. Loads no model and never reads or grabs the keyboard. |
| `dictate.py` (via `dictate.sh`) | same | One process per session. Loads the speech model (~3 s; ~8 s on an N100), records with `parecord`, and either types text with `ydotool` (dictation) or feeds the caption window and transcript (`--caption`). Exits completely afterwards. Launching it again while a session runs stops that session. Dictation and captions have separate PID files, so they run independently. |
| `indicator.py` / `indicator_x11.py` | same | Dictation's floating "● Listening" bar: a Wayland layer-shell overlay with keyboard interactivity off, or an override-redirect X11 window that is never focused. |
| `captions.py` | same, dictation venv | The caption window: an ordinary Qt window (movable, resizable, A−/A+, scroll-back, Stop). Exit code 0 (user closed it) tells `dictate.py` to stop. |
| `setup-caption-window-rule.sh` | run by the installer | A KWin rule keyed on the window's app id `hearside-captions`: keep above, never accept focus, skip the task switcher, remember position and size. |
| `captions-echo-cancel.conf` | same | A private `pipewire -c` process started per captions session: PipeWire's WebRTC echo canceller in monitor mode, producing the source `captions_aec_source` (mic minus what the speakers play). |
| `speakers.sh` → `diarize.py` → `label_speakers.py` | same; `speakers-venv` for pyannote | After a captions session: who-spoke-when, then per-turn re-transcription, inside a network-less sandbox. |
| `ydotoold.service` | systemd user unit | The daemon `ydotool` types through (`/dev/uinput`, which the `input` group may use via `99-uinput.rules`). |
| Models | `~/.cache/huggingface/hub/` | Loaded with `HF_HUB_OFFLINE=1`; sessions make no network calls. |

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
- **No resident model daemon.** A version that kept the model loaded leaked CPU (200–670%) after sessions. Each session loads fresh and exits. The few seconds of startup are the trade-off.
- **KDE "Command" custom shortcuts were unreliable** for launching this (their systemd-run units often never ran). Registering through kglobalaccel's D-Bus API works reliably.
- **The listener follows the desktop session** (`PartOf=graphical-session.target`, plus a restart whenever kglobalaccel's D-Bus owner changes). Otherwise, after logout and login with user linger on, KWin holds the shortcut but marks it inactive.
- **`parecord --latency-msec=50` is essential.** By default audio arrives in ~2 s bursts, which makes every word lag.
- **Last-word bug:** the stock `TextIteratorStreamer` holds the last word back until the next one starts. A custom streamer emits each word immediately, with clean end-of-stream handling.
- **Dictation's bar must never take focus**, or typing breaks. Hence layer-shell (or an override-redirect window on X11) rather than an "always on top" window. The caption window is different: it's an ordinary window people can move, and a KWin rule supplies "on top, never focused".
- **Copying the gated model between machines needs `tar -h`.** huggingface_hub 1.x stores the real files in a shared blob store outside the model's folder.
