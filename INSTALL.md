# Installing HearSide

HearSide is installed **once per computer**, by someone with `sudo` rights, and then works for every user account on it, the way Win+H works for everyone on Windows. This guide takes about 15–30 minutes, most of it waiting for downloads. You'll need:

- [ ] A Linux computer with **KDE Plasma** 5.27 or newer (Wayland or X11); required
- [ ] **Debian / Ubuntu / Kubuntu**, or **Fedora / RHEL / AlmaLinux / Rocky Linux**
- [ ] **PipeWire** sound (standard on all current releases of those)
- [ ] A **microphone**
- [ ] **sudo** rights for installing (users don't need them to use HearSide)
- [ ] **Internet** during installation (~4 GB of downloads; nothing afterwards)
- [ ] About **6–7 GB** free in `/opt` (shared by all users, speaker labels included)
- [ ] For speaker labels only: a free **Hugging Face** account. Step 4 below shows how to create one; no payment details are needed.

**Upgrading from HearSide 1.0.x?** That version was installed separately in each user's home folder. Install 1.1.0 as below, then see [Moving over from 1.0.x](#moving-over-from-10x): the models are copied from your old install, so nothing big is downloaded again.

---

## 1. Check your system (optional, 1 minute)

```bash
./install.sh --check      # "OK: KDE Plasma 6.x.x. This computer can run HearSide."
```

**HearSide requires KDE Plasma.** The installer checks this first and stops if Plasma isn't installed or is older than 5.27. `--check` also lists the system packages the installer would add (or says they're all there already). It installs nothing and needs no sudo.

## 2. Unpack it

```bash
cd ~/Downloads                      # or wherever you saved it
tar xzf hearside-1.1.0.tar.gz
cd hearside-1.1.0
```

(If you received the `.zip` instead, unpack it with `unzip hearside-1.1.0.zip`. Zip files often lose the "executable" flag, so start scripts with `sudo bash install.sh` instead of `sudo ./install.sh`.)

## 3. Run the installer

```bash
sudo ./install.sh
```

What happens:

1. **Checks first** that KDE Plasma 5.27+ is installed. If not, it stops before changing anything.
2. **Slow computer?** On CPUs with 4 threads or fewer (Intel N100, older Core i3/i5…), it offers the **8-bit model**: about twice as fast, and it gave the same words in testing. Press **Enter** to accept (the recommended answer is the default). You can also choose it yourself: `sudo ./install.sh --int8 --threads 3`.
3. **System packages and accounts.** It lists the system packages that are missing and asks **"Install them now? [Y/n]"** before adding them (packages already installed are left alone; `--yes` skips the question). It installs Python tools, PipeWire's echo canceller, `bubblewrap` and `ydotool` (which types the dictated text; downloaded from its GitHub release and checksum-verified), and adds **every regular user account** to the `input` group, which dictation needs to type text. To set up only some accounts: `sudo ./install.sh --users "anna ben"`.
4. **Dictation and live captions**, shared by everyone, in `/opt/hearside`: PyTorch (~1 GB, CPU-only), NVIDIA's speech model (~2.5 GB), the hotkey and typing services (started at each user's login), and **Dictation (HearSide)** / **Live Captions (HearSide)** entries in the application menu.
5. **Speaker labels (optional).** It asks whether you want them. If you say yes, follow step 4 below when it pauses.

It ends with **"All done"**. It is safe to re-run: it repairs or upgrades an install, and sets up user accounts added since.

## 4. Speaker labels: the one-time Hugging Face step

The speaker-labelling model (pyannote "community-1") is free, but its authors require each downloader to accept their terms first. You do this once, on their website:

1. **Create a free account** at <https://huggingface.co/join> and confirm your email address.
2. **Accept the model's terms.** While signed in, open <https://huggingface.co/pyannote/speaker-diarization-community-1>. Scroll down past "Use this model" to the box titled *"You need to agree to share your contact information to access this model."*
   - **Company/university** is required. If this is personal use, "Personal" is fine.
   - **Use case** is required. Pick the closest option.
   - Click **Agree and access repository**. The box should change to say you have access.
   - If the box only shows *Log in / Sign Up* links, that browser isn't signed in.
3. **Create an access token.** Open <https://huggingface.co/settings/tokens>, click **Create new token**, choose type **Read**, give it any name, and click **Create**. Copy the token (it starts with `hf_`).
   - A "fine-grained" token also works, but only if you tick **"Read access to contents of all public gated repos you can access"**.
4. **Back in the installer**, press Enter, choose **Paste an access token** (arrow keys, then Enter), and paste it with **Ctrl+Shift+V**. Nothing shows as you paste; that's normal. If it asks about git credentials, answer **n**.

The installer downloads the model (33 MB), then **logs the computer out of Hugging Face again**, so no token stays stored. You can also delete the token on the website afterwards.

What you agreed to: pyannote's authors receive your account's username and email, and may occasionally email you about their models and paid services; you can unsubscribe. **No audio or transcripts are ever sent to them or to Hugging Face.** Speaker labelling runs in a sandbox that has no network access at all.

**Common problem:** *"403 … not in the authorized list"* means step 2 wasn't completed. Accept the terms, then run `sudo ./install-speakers.sh`.

**Another computer of your own:** no need to log in again. Copy the model folder from a computer that has it, then point the installer at it:

```bash
M=models--pyannote--speaker-diarization-community-1
ssh FIRST-COMPUTER "tar -h -C /opt/hearside/hf/hub -cf - $M/snapshots $M/refs" | (mkdir -p ~/hearside-model && tar -C ~/hearside-model -xf -)
sudo ./install.sh --speaker-model-from ~/hearside-model
```

(On a computer with the older 1.0.x install the model is in `~/.cache/huggingface/hub` instead; see below.)

## 5. Restart

Restart the computer, or have each user log out and back in once, so their new `input` group membership and the HearSide services take effect.

## 6. Try it

**Dictation**
1. Click into any text field (a text editor, a browser box…).
2. Press **Win+H**. The **dictation bar** appears and, after a few seconds the first time (longer on slow computers), says **Listening**.
3. Speak. Words appear as you talk.
4. **Pause** with the bar's 🎤 button, **Win+H**, or by **typing any key**. The bar stays on screen: click 🎤 or press Win+H to talk again; listening starts at once, since the model stays loaded while the bar is open.
5. **Drag** the bar anywhere (grab it anywhere except its buttons); it reopens in the same place. **✕** closes it.

The bar never takes keyboard focus, so clicking it leaves your cursor in the text field. It can also be opened from the application menu (**Dictation (HearSide)**). While it is open, its tray icon starts/stops listening (left click) and closes it (right-click menu).

**Live captions**
1. Press **Meta+Shift+H**, or choose **Live Captions (HearSide)** from the application menu.
2. A black caption window appears and stays on top of other windows, without ever taking your keyboard focus, so keep typing as normal.
3. **Move and resize** it like any window; it remembers where you put it. **A− / A+** change the text size. Scroll up to re-read earlier captions.
4. **⏸ Pause** stops listening without closing the window (nothing is heard or saved while paused); **▶ Resume** carries on in the same transcript, which notes the gap as `[paused 10:42:05 – 10:55:31]`. The tray icon's right-click menu pauses and resumes too.
5. Stop with the red **■ Stop** button, by closing the window, with **Meta+Shift+H**, or by clicking the tray icon. A notification shows where the transcript was saved.

**What captions hear:** your microphone **plus** whatever your computer plays (Zoom, Webex, a browser…). If you use speakers rather than headphones, that's fine: an echo canceller removes the speaker sound from your mic, so call audio isn't captured twice. For a **phone call**, put the phone on speaker next to your microphone.

**Speaker labels:** a few minutes after you stop (about 15 minutes per hour of audio on a fast computer, longer on slow ones), a notification says the `-speakers.txt` file is ready in `~/Transcripts/`. Rename "Speaker 1", "Speaker 2"… with Find & Replace (Kate: **Ctrl+R**).

**Through a remote desktop (RustDesk and similar):** remote-desktop tools don't pass your microphone across. Open the dictation bar on **your own** computer, click into the remote window, and click the bar's 🎤; the words are typed on your computer and the remote-desktop tool forwards the keystrokes. Typing through a RustDesk session also pauses dictation running on the remote computer.

## 7. Settings

**For the whole computer:** `/opt/hearside/hearside.env` (written by the installer; edit with `sudo`).
**For one user:** `~/.config/voice-dictation.env`, which overrides the computer's settings.
One setting per line (e.g. `CAPTION_KEEP_AUDIO=0`). They take effect at the next session.

| Setting | Default | What it does |
|---|---|---|
| `DICTATION_INT8` | `0` | `1` = 8-bit speech model (faster; for slow CPUs). The installer prepares it once for everyone. |
| `DICTATION_THREADS` | `4` | CPU cores for live recognition |
| `CAPTION_FONT_SIZE` | `22` | Starting text size in pixels (A−/A+ overrides and remembers) |
| `CAPTION_TRANSCRIPT_DIR` | `~/Transcripts` | Where transcripts and recordings go |
| `CAPTION_COMPUTER_AUDIO` | `1` | `0` = captions hear the microphone only |
| `CAPTION_ECHO_CANCEL` | `1` | `0` = don't clean speaker sound out of the mic (e.g. if you always use headphones) |
| `CAPTION_SPEAKER_LABELS` | `1` | `0` = don't make speaker-labelled transcripts |
| `CAPTION_KEEP_AUDIO` | `1` | `0` = delete the `.wav` recording once the labelled transcript is made |
| `SPEAKER_THREADS` | all but 2 | CPU cores for the after-call labelling (runs at low priority) |

Each user can change their hotkeys in **System Settings → Shortcuts → Voice Dictation**.

## Adding a user account later

Run `sudo ./install.sh` again (it only sets up what's missing), or just add the account to the `input` group: `sudo usermod -aG input NAME`. HearSide starts for them at their next login.

## Moving over from 1.0.x

1.0.x lived in each user's `~/.local/share/dictation` (~7 GB each, with the models in `~/.cache/huggingface/hub`). To switch a computer over:

1. **Install 1.1.0**, reusing the models from your old install instead of downloading them:
   ```bash
   sudo ./install.sh --speaker-model-from ~/.cache/huggingface/hub
   ```
   (The speech model is reused automatically from the account that runs `sudo`.) Until step 2, the old copy keeps working and the new one stays out of its way.
2. **Each user with an old copy** then runs, as themselves:
   ```bash
   ./remove-per-user-install.sh
   ```
   It stops and removes the old copy, its menu entries and (if you agree) its model copies, keeps transcripts and personal settings, and starts the shared HearSide straight away. No restart needed.

## Other desktops

HearSide supports **KDE Plasma only**. Its hotkeys and its two windows that stay on top without taking focus rely on KDE's own services, so the installer refuses to run on GNOME, Cinnamon, XFCE and others. (The speech engine underneath is desktop-neutral, so support could be added later.)

## Troubleshooting

| Problem | What to check |
|---|---|
| Win+H / Meta+Shift+H does nothing | `systemctl --user status hearside-hotkey`. In `~/.local/share/hearside/timeline.log`, look for `[listener] registered toggle-dictation` / `toggle-captions`. A `WARNING ... assigned no key` line means another shortcut already uses that key; change one in System Settings → Shortcuts. If the service shows "skipped, unmet condition", the user isn't in the `input` group yet (log out and back in) or still has a 1.0.x copy (run `remove-per-user-install.sh`). |
| Listening, but nothing is typed | `systemctl --user status hearside-ydotoold`, and check you're in the `input` group (`id -nG`). Right after installing, restart or log out and back in. |
| "No audio captured", or captions stay empty | Check the input device in System Settings → Sound, and look at "peak mic level" in `timeline.log`. |
| The bar or caption window takes focus or hides behind windows | Look in **System Settings → Window Rules** for "Dictation bar (HearSide)" and "Live Captions (HearSide)". If they're missing, run `/opt/hearside/setup-window-rules.sh --force` and log out and back in. |
| Call audio doubled / echoey in captions | Look for `audio: mic=echo-cancelled` in `timeline.log`. If it says `plain`, PipeWire's WebRTC echo canceller is missing: Debian/Ubuntu `libspa-0.2-modules`, Fedora/RHEL `pipewire-libs`. |
| No speaker-labelled file appeared | `~/.local/share/hearside/speakers.log` shows each run and any error. `FAILED: ... sandbox` means neither `unshare` nor `bwrap` works there; install `bubblewrap`. |
| Too slow / computer runs hot | Use 8-bit mode (`DICTATION_INT8=1`) and fewer threads (`DICTATION_THREADS=2`). |

Logs never contain what was said, only timings and counts, so they're safe to share when asking for help. Python error messages go to `~/.local/share/hearside/debug.log`.

## Updating and uninstalling

- **Update:** unpack the newer version and run its `sudo ./install.sh`. Settings and transcripts are kept.
- **Uninstall:** `sudo ./uninstall.sh`. It removes HearSide for everyone and keeps every user's `~/Transcripts`.
