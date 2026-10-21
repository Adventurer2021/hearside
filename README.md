# Hearside

**Hearside** is a set of offline voice tools for Linux, built for the KDE Plasma desktop. Everything runs on your own computer: no cloud service, no subscription, and your audio and words never leave the machine. It is installed once and works for every user of the computer, like Win+H on Windows.

- **Dictation (Win+H)**: a small dictation bar, much like Windows 11's voice typing. Speak, and the words are typed into whatever text field has focus. Its microphone button (or Win+H) starts and stops listening; the bar stays on screen until you close it, and you can drag it anywhere.
- **Live captions (Meta+Shift+H)**: real-time captions in a small window you can move and resize, for phone calls on speaker, Zoom/Webex meetings, or anything your computer plays. Built for people who are hard of hearing. Every session is saved as a transcript.
- **Speaker-labelled transcripts (optional)**: a few minutes after a captions session ends, a second transcript says who spoke when (`Speaker 1: … / Speaker 2: …`), re-transcribed from the recording for better accuracy.

> **Meta** is the "Windows" key. **Win+H** and **Meta+H** are the same thing.

## Quick start

```bash
tar xzf hearside-1.1.0.tar.gz
cd hearside-1.1.0
sudo ./install.sh
```

Then restart the computer (or have each user log out and back in once). **Read [INSTALL.md](INSTALL.md) first.** It lists the requirements, explains the one-time Hugging Face account that the optional speaker labels need, and how to move over from an older (1.0.x) install.

## What it does, in more detail

| | Dictation (Win+H) | Live captions (Meta+Shift+H) |
|---|---|---|
| Listens to | your microphone | your microphone **and** your computer's own audio (Zoom, Webex, a browser…) |
| Output | typed into the focused app | caption window + transcript file in `~/Transcripts/` |
| Start / stop | Win+H, the bar's 🎤 button, or the tray icon. **Typing any key** pauses listening. The bar stays until you click its ✕. | Meta+Shift+H, the window's **Stop** button, closing the window, or the tray icon. Typing never stops it. |
| Speakers without headphones? | — | Fine: a built-in echo canceller removes your speakers' sound from the mic, so the other people on a call aren't captured twice |

The dictation bar and the caption window never take keyboard focus, so clicking their buttons leaves your cursor where it was. Both remember where you put them.

**Transcripts** (each user's own, private to their account):

```
~/Transcripts/2026-10-09_15-16-43.txt            live captions, timestamped at each pause
~/Transcripts/2026-10-09_15-16-43.wav            the recording (left: your mic, right: computer audio)
~/Transcripts/2026-10-09_15-16-43-speakers.txt   [15:17:09] Speaker 2: Hello there, how are you?
```

Speakers are numbered in the order they first speak. Rename them with your editor's Find & Replace (in Kate, Ctrl+R).

**Dictating into a remote desktop (RustDesk and similar):** remote-desktop tools don't pass your microphone to the other computer. Instead, open the dictation bar on **your own** computer, click into the remote-desktop window, and click the bar's 🎤: your computer types the words, and the remote-desktop tool sends the keystrokes across. (While the remote window has focus, Win+H itself goes to the remote computer.)

## Requirements (short version)

- **Linux with KDE Plasma** 5.27 or newer, on Wayland or X11. **KDE Plasma is required**; the installer checks first and stops otherwise. `./install.sh --check` tests a computer without installing anything.
- **Debian / Ubuntu** (apt) or **Fedora / RHEL / AlmaLinux / Rocky** (dnf), with **PipeWire** sound (the default on all current releases).
- A microphone, `sudo` rights for installing, and internet **during installation only**.
- About **6–7 GB** of disk in `/opt/hearside`, once for all users (speaker labels included). Any recent x86-64 CPU; slower ones (Intel N100, older i3/i5 class) use an 8-bit mode the installer offers.
- While the dictation bar is open, the speech model stays loaded so listening starts at once: about 3.3 GB of memory (2.3 GB in 8-bit mode), no CPU while idle. Closing the bar frees it.

## Tested on

| Distribution | KDE Plasma | Hardware | Notes |
|---|---|---|---|
| Debian 13 "trixie" | 6.3.6, Wayland | Intel Core i9-13900HK mini PC (20 threads) | All features, including a real speakerphone call |
| Debian 13 "trixie" | 6.3.6, Wayland | AMD Ryzen 7 5825U laptop (16 threads) | |
| Debian 13 "trixie" | 6.3.6, Wayland | Intel Core i3-6100U laptop (4 threads), **two user accounts** | 8-bit mode; one install used by both accounts |
| Debian 13 "trixie" | 6.3.6, Wayland | Intel N100 mini PC (4 threads, 12 GB) | 8-bit mode |
| AlmaLinux 10.2 | 6.6.4, Wayland | Intel Core i7-11700 desktop (16 threads) | SELinux enforcing |
| Ubuntu 26.04.1 LTS (Kubuntu) | 6.6.6, **X11** | Intel Core i5-6400 desktop (4 threads) | 8-bit mode; speaker labels use a bubblewrap sandbox (Ubuntu's AppArmor blocks plain `unshare`) |

## Privacy

- Speech recognition, captions, transcripts and speaker labelling all run **locally**. The models are downloaded once during installation.
- Speaker labelling runs inside a **sandbox with no network access**, and pyannote's optional usage statistics are switched off.
- Logs record timings and counts only, **never what was said**. Each user's transcripts and recordings are readable only by that user.
- Recording a phone call or meeting may require the other people's consent where you live. Telling them you're using captions because of your hearing covers it in most places.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes Hearside for every user. Everyone's `~/Transcripts` are kept.

## Credits and license

Hearside is released under the [MIT License](LICENSE). It builds on NVIDIA's Nemotron speech model, pyannote's speaker-diarization model, ydotool, PipeWire's WebRTC echo canceller, PyTorch, Hugging Face Transformers and Qt. Their licenses and the required attributions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). How it works inside: [docs/DESIGN.md](docs/DESIGN.md).
