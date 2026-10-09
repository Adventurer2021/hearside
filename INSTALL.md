# Installing Hearside

This guide takes about 15–30 minutes, most of it waiting for downloads. You'll need:

- [ ] A Linux computer running **KDE Plasma** 5.27 or newer (Wayland or X11), and **logged into it** while installing; required
- [ ] **Debian / Ubuntu / Kubuntu**, or **Fedora / RHEL / AlmaLinux / Rocky Linux**
- [ ] **PipeWire** sound (standard on all current releases of those)
- [ ] A **microphone**
- [ ] An account with **sudo** rights (you'll type your password once)
- [ ] **Internet** during installation (~4 GB of downloads; nothing afterwards)
- [ ] About **6 GB** free disk space, plus **1.5 GB** for the optional speaker labels
- [ ] For speaker labels only: a free **Hugging Face** account. Step 4 below shows how to create one; no payment details are needed.

---

## 1. Check your system (optional, 1 minute)

Open a terminal (Konsole) and run these. Each line shows what you should see:

```bash
echo $XDG_CURRENT_DESKTOP     # KDE
echo $XDG_SESSION_TYPE        # wayland  (x11 also works)
pactl info | grep "Server Name"   # ...PipeWire...
df -h ~                       # at least 6G under "Avail"
```

Or let the installer check for you, without installing anything:

```bash
./install.sh --check      # "OK: KDE Plasma 6.x.x ... This computer can run Hearside."
```

**Hearside requires KDE Plasma.** The installer checks this first and stops if Plasma isn't installed, is older than 5.27, or isn't the desktop you're logged into right now.

## 2. Unpack it

```bash
cd ~/Downloads                      # or wherever you saved it
tar xzf hearside-1.0.0.tar.gz
cd hearside-1.0.0
```

(If you received the `.zip` instead, unpack it with `unzip hearside-1.0.0.zip`. Zip files often lose the "executable" flag, so start the installer with `bash install.sh` instead of `./install.sh`. The same goes for `bash uninstall.sh`.)

## 3. Run the installer

```bash
./install.sh
```

Run it as **yourself**, not with `sudo`, while **logged into your Plasma desktop**. Running it in Konsole is simplest; over SSH works too, as long as you're logged into Plasma on that computer at the same time. It asks for your password when it needs it. What happens:

0. **Checks first** that KDE Plasma 5.27+ is installed and is the desktop you're logged into. If not, it stops and says why, before changing anything.

1. **System packages** (asks for your password). It installs Python tools, PipeWire's echo canceller, `bubblewrap`, `ydotool` (to type dictated text; downloaded from its GitHub release and checksum-verified) and, for the floating "Listening" bar, `gtk4-layer-shell` (built from checksum-verified source if your distribution doesn't package it). It also adds you to the `input` group. Your package manager will show the list and ask you to confirm.
2. **If it says to log out and back in**: do that (on some systems a reboot is needed), then run `./install.sh` again. It skips what's already done.
3. **Dictation and live captions.** It downloads PyTorch (~1 GB, CPU-only) and NVIDIA's speech model (~2.5 GB), then sets up the Win+H and Meta+Shift+H hotkeys, the caption window, and a "Live Captions (Hearside)" entry in the application menu.
4. **Speaker labels (optional).** It asks whether you want them. If you say yes, follow step 4 below when it pauses.

**Slow computer?** On CPUs like the Intel N100, the installer offers an **8-bit mode**. Say yes: it's about twice as fast and gave the same words in testing. You can also choose it yourself: `./install.sh --int8 --threads 3`.

## 4. Speaker labels: the one-time Hugging Face step

The speaker-labelling model (pyannote "community-1") is free, but its authors require each user to accept their terms before downloading. You do this once, on their website:

1. **Create a free account** at <https://huggingface.co/join> and confirm your email address.
2. **Accept the model's terms.** While signed in, open <https://huggingface.co/pyannote/speaker-diarization-community-1>. Scroll down past "Use this model" to the box titled *"You need to agree to share your contact information to access this model."*
   - **Company/university** is required. If this is personal use, "Personal" is fine.
   - **Use case** is required. Pick the closest option.
   - Click **Agree and access repository**. The box should change to say you have access.
   - If the box only shows *Log in / Sign Up* links, that browser isn't signed in.
3. **Create an access token.** Open <https://huggingface.co/settings/tokens>, click **Create new token**, choose type **Read**, give it any name, and click **Create**. Copy the token (it starts with `hf_`).
   - A "fine-grained" token also works, but only if you tick **"Read access to contents of all public gated repos you can access"**.
4. **Back in the installer**, press Enter, choose **Paste an access token** (arrow keys, then Enter), and paste it with **Ctrl+Shift+V**. Nothing shows as you paste; that's normal. If it asks about git credentials, answer **n**.

The installer downloads the model (33 MB), then **logs your computer out of Hugging Face again**, so no token stays stored. You can also delete the token on the website afterwards.

What you agreed to: pyannote's authors receive your account's username and email, and may occasionally email you about their models and paid services; you can unsubscribe. **No audio or transcripts are ever sent to them or to Hugging Face.** Speaker labelling runs in a sandbox that has no network access at all.

**Common problem:** *"403 … not in the authorized list"* means step 2 wasn't completed. Accept the terms, then run `./install-speakers.sh`.

**Setting up a second computer of your own:** you don't need to log in again. Copy the model from the first computer before running the installer on the second (replace `OTHER-COMPUTER` with its name or address):

```bash
M=models--pyannote--speaker-diarization-community-1
tar -h -C ~/.cache/huggingface/hub -cf - $M/snapshots $M/refs \
  | ssh OTHER-COMPUTER 'mkdir -p ~/.cache/huggingface/hub && tar -C ~/.cache/huggingface/hub -xf -'
```

## 5. Try it

**Dictation**
1. Click into any text field (a text editor, a browser box…).
2. Press **Win+H**. After about 3 seconds (longer on slow computers), a small **● Listening** bar appears at the top of the screen.
3. Speak. Words appear as you talk.
4. Press **Win+H** again, or **any key**, to stop.

**Live captions**
1. Press **Meta+Shift+H**, or choose **Live Captions (Hearside)** from the application menu.
2. A black caption window appears and stays on top of other windows, without ever taking your keyboard focus, so keep typing as normal.
3. **Move and resize** it like any window; it remembers where you put it. **A− / A+** change the text size. Scroll up to re-read earlier captions.
4. Stop with the red **■ Stop** button, by closing the window, with **Meta+Shift+H**, or by clicking the tray icon. A notification shows where the transcript was saved.

**What captions hear:** your microphone **plus** whatever your computer plays (Zoom, Webex, a browser…). If you use speakers rather than headphones, that's fine: an echo canceller removes the speaker sound from your mic, so call audio isn't captured twice. For a **phone call**, put the phone on speaker next to your microphone.

**Speaker labels:** a few minutes after you stop (about 15 minutes per hour of audio on a fast computer, longer on slow ones), a notification says the `-speakers.txt` file is ready in `~/Transcripts/`. Rename "Speaker 1", "Speaker 2"… with Find & Replace (Kate: **Ctrl+R**).

## 6. Settings

Put any of these in `~/.config/voice-dictation.env`, one per line (e.g. `CAPTION_KEEP_AUDIO=0`). They take effect at the next session.

| Setting | Default | What it does |
|---|---|---|
| `DICTATION_INT8` | `0` | `1` = 8-bit speech model (faster; for slow CPUs) |
| `DICTATION_THREADS` | `4` | CPU cores for live recognition |
| `CAPTION_FONT_SIZE` | `22` | Starting text size in pixels (A−/A+ overrides and remembers) |
| `CAPTION_TRANSCRIPT_DIR` | `~/Transcripts` | Where transcripts and recordings go |
| `CAPTION_COMPUTER_AUDIO` | `1` | `0` = captions hear the microphone only |
| `CAPTION_ECHO_CANCEL` | `1` | `0` = don't clean speaker sound out of the mic (e.g. if you always use headphones) |
| `CAPTION_SPEAKER_LABELS` | `1` | `0` = don't make speaker-labelled transcripts |
| `CAPTION_KEEP_AUDIO` | `1` | `0` = delete the `.wav` recording once the labelled transcript is made |
| `SPEAKER_THREADS` | all but 2 | CPU cores for the after-call labelling (runs at low priority) |

The hotkeys can be changed in **System Settings → Shortcuts → Voice Dictation**.

## Other desktops

Hearside supports **KDE Plasma only**. Its hotkeys, its caption window that stays on top without taking focus, and its floating "Listening" bar all use KDE's own services, so the installer refuses to run on GNOME, Cinnamon, XFCE and others. (The speech engine underneath is desktop-neutral, so support could be added later.)

## Troubleshooting

| Problem | What to check |
|---|---|
| Win+H / Meta+Shift+H does nothing | `systemctl --user status dictation-hotkey`. In `~/.local/share/dictation/timeline.log`, look for `[listener] registered toggle-dictation` / `toggle-captions`. A `WARNING ... assigned no key` line means another shortcut already uses that key; change one in System Settings → Shortcuts. |
| Listening, but nothing is typed | `systemctl --user status ydotoold`, and check you're in the `input` group (`id -nG`). If you just installed, log out and back in. |
| "No audio captured", or captions stay empty | Check the input device in System Settings → Sound, and look at "peak mic level" in `timeline.log`. |
| Caption window appears behind other windows or takes focus | `grep -A3 hearside-captions ~/.config/kwinrulesrc`. If nothing shows, run `~/.local/share/dictation/setup-caption-window-rule.sh`. |
| Call audio doubled / echoey in captions | Look for `audio: mic=echo-cancelled` in `timeline.log`. If it says `plain`, PipeWire's WebRTC echo canceller is missing: Debian/Ubuntu `libspa-0.2-modules`, Fedora/RHEL `pipewire-libs`. |
| No speaker-labelled file appeared | `~/.local/share/dictation/speakers.log` shows each run and any error. `FAILED: ... sandbox` means neither `unshare` nor `bwrap` works there; install `bubblewrap`. |
| Too slow / computer runs hot | Use 8-bit mode (`DICTATION_INT8=1`) and fewer threads (`DICTATION_THREADS=2`). |

Logs never contain what was said, only timings and counts, so they're safe to share when asking for help. Python error messages go to `~/.local/share/dictation/debug.log`.

## Updating and uninstalling

- **Update:** unpack the newer version and run its `./install.sh`. Your settings and transcripts are kept.
- **Uninstall:** `./uninstall.sh`. It keeps `~/Transcripts`, and asks before removing the models (~2.5 GB) and the system-level parts.
