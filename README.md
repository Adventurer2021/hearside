# Hearside

**Hearside** is a set of offline voice tools for Linux, built for the KDE Plasma desktop. Everything runs on your own computer: no cloud service, no subscription, and your audio and words never leave the machine.

- **Dictation (Win+H)**: speak, and the words are typed into whatever text field has focus, much like Windows 11's Win+H.
- **Live captions (Meta+Shift+H)**: real-time captions in a small window you can move and resize, for phone calls on speaker, Zoom/Webex meetings, or anything your computer plays. Built for people who are hard of hearing. Every session is saved as a transcript.
- **Speaker-labelled transcripts (optional)**: a few minutes after a captions session ends, a second transcript says who spoke when (`Speaker 1: … / Speaker 2: …`), re-transcribed from the recording for better accuracy.

> **Meta** is the "Windows" key. **Win+H** and **Meta+H** are the same thing.

## Quick start

```bash
tar xzf hearside-1.0.0.tar.gz
cd hearside-1.0.0
./install.sh
```

The installer asks for your password once (for system packages) and may ask you to log out and back in, then run it again. **Read [INSTALL.md](INSTALL.md) first.** It lists the requirements and explains the one-time Hugging Face account that the optional speaker labels need.

## What it does, in more detail

| | Dictation (Win+H) | Live captions (Meta+Shift+H) |
|---|---|---|
| Listens to | your microphone | your microphone **and** your computer's own audio (Zoom, Webex, a browser…) |
| Output | typed into the focused app | caption window + transcript file in `~/Transcripts/` |
| Stops when | Win+H again, or any key | Meta+Shift+H again, the window's **Stop** button, closing the window, or clicking the tray icon. Typing never stops it. |
| Speakers without headphones? | — | Fine: a built-in echo canceller removes your speakers' sound from the mic, so the other people on a call aren't captured twice |

**Transcripts** (all private to your user account):

```
~/Transcripts/2026-10-09_15-16-43.txt            live captions, timestamped at each pause
~/Transcripts/2026-10-09_15-16-43.wav            the recording (left: your mic, right: computer audio)
~/Transcripts/2026-10-09_15-16-43-speakers.txt   [15:17:09] Speaker 2: Hello there, how are you?
```

Speakers are numbered in the order they first speak. Rename them with your editor's Find & Replace (in Kate, Ctrl+R).

## Requirements (short version)

- **Linux with KDE Plasma** 5.27 or 6.x, on Wayland or X11. Other desktops partly work; see [INSTALL.md](INSTALL.md#other-desktops).
- **Debian / Ubuntu** (apt) or **Fedora / RHEL / AlmaLinux / Rocky** (dnf), with **PipeWire** sound (the default on all current releases).
- A microphone, `sudo` rights, and internet **during installation only**.
- About **6 GB** of disk (plus **1.5 GB** for speaker labels). Any recent x86-64 CPU; slow ones (Intel N100 class) use an 8-bit mode the installer offers.

## Tested on

| Distribution | KDE Plasma | Hardware | Notes |
|---|---|---|---|
| Debian 13 "trixie" | 6.3.6, Wayland | Intel Core i9-13900HK mini PC (20 threads) | All features, including a real speakerphone call |
| AlmaLinux 10.2 | 6.6.4, Wayland | Intel Core i7-11700 desktop (16 threads) | The installer builds `gtk4-layer-shell` from source (not packaged for EL10) |
| Ubuntu 26.04.1 LTS (Kubuntu) | 6.6.6, Wayland | Intel Core i5-6400 desktop (4 threads) | Speaker labels use a bubblewrap sandbox (Ubuntu's AppArmor blocks plain `unshare`) |
| Debian 13 "trixie" | 6.3.6, Wayland | Intel N100 mini PC (4 threads, 12 GB) | 8-bit mode; captions use about half the CPU |

## Privacy

- Speech recognition, captions, transcripts and speaker labelling all run **locally**. The models are downloaded once during installation.
- Speaker labelling runs inside a **sandbox with no network access**, and pyannote's optional usage statistics are switched off.
- Logs record timings and counts only, **never what was said**. Transcripts and recordings are readable only by your user account.
- Recording a phone call or meeting may require the other people's consent where you live. Telling them you're using captions because of your hearing covers it in most places.

## Uninstall

```bash
./uninstall.sh
```

This keeps your `~/Transcripts` and asks before removing the downloaded models and the system-level parts.

## Credits and license

Hearside is released under the [MIT License](LICENSE). It builds on NVIDIA's Nemotron speech model, pyannote's speaker-diarization model, ydotool, gtk4-layer-shell, PipeWire's WebRTC echo canceller, PyTorch, Hugging Face Transformers and Qt. Their licenses and the required attributions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). How it works inside: [docs/DESIGN.md](docs/DESIGN.md).
