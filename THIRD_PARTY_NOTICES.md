# Third-party components

Hearside' own code (the scripts and Python files in this package) is MIT-licensed; see [LICENSE](LICENSE).

**None of the components below is included in this package.** The installer downloads each one from its official source onto your computer, under that component's own license, which you accept by installing it. They're listed here for credit, and because some licenses ask for attribution.

## AI models

| Model | Used for | License |
|---|---|---|
| **NVIDIA Nemotron Speech Streaming EN 0.6B** (`nvidia/nemotron-speech-streaming-en-0.6b`), by NVIDIA | Speech recognition for dictation, captions and the labelled transcripts | [NVIDIA Open Model License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/); NVIDIA states it is ready for commercial and non-commercial use |
| **pyannote speaker-diarization-community-1** (`pyannote/speaker-diarization-community-1`), by pyannote / pyannoteAI | Working out who spoke when | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Gated: each user accepts the authors' conditions on [its Hugging Face page](https://huggingface.co/pyannote/speaker-diarization-community-1) before downloading |

Attribution for the speaker-labelling model: *"pyannote speaker-diarization-community-1" by pyannote, used under CC BY 4.0. Used unmodified; only one analysis setting is changed at run time (window step 2.5 s instead of 1 s).*

## Software

| Component | Used for | License |
|---|---|---|
| [pyannote.audio](https://github.com/pyannote/pyannote-audio) | Runs the speaker-labelling model | MIT |
| [PyTorch](https://pytorch.org) (CPU build) | Runs both models | BSD-3-Clause |
| [Hugging Face Transformers](https://github.com/huggingface/transformers), [huggingface_hub](https://github.com/huggingface/huggingface_hub), [Accelerate](https://github.com/huggingface/accelerate) | Loading and running the speech model | Apache-2.0 |
| [Qt for Python (PySide6)](https://doc.qt.io/qtforpython/) | Caption window, tray icon, hotkey listener | LGPL-3.0 (used unmodified, as a separately installed library) |
| [NumPy](https://numpy.org), [librosa](https://librosa.org) | Audio processing | BSD-3-Clause, ISC |
| [python-evdev](https://github.com/gvalkov/python-evdev) | Detecting a keypress to stop dictation | BSD-3-Clause |
| [ydotool](https://github.com/ReimuNotMoe/ydotool) v1.0.4 | Typing dictated text into apps | AGPL-3.0 (installed unmodified as a separate program; this package only runs it) |
| [gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell) | The floating "Listening" bar on Wayland | MIT |
| [PipeWire](https://pipewire.org) with the [WebRTC audio processing](https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing) echo canceller | Audio capture and echo cancellation | MIT; BSD-3-Clause |
| [bubblewrap](https://github.com/containers/bubblewrap) | Network-less sandbox for speaker labelling (where `unshare` isn't allowed) | LGPL-2.0-or-later |

KDE Plasma, KWin and the other desktop components belong to the [KDE community](https://kde.org) and are used through their standard interfaces (global shortcuts, window rules). "KDE" and "Plasma" are trademarks of KDE e.V.; this project is not affiliated with or endorsed by KDE.
