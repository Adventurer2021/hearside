#!/usr/bin/env python3
"""Toggle live voice dictation, like Windows 11 Win+H. Launched by
hotkey_listener.py: the first run listens and types words into the focused
window as they are recognised (via ydotool); a second run while one is active
stops it, as does pressing any ordinary key. Uses NVIDIA's Nemotron streaming
ASR model fully offline. Loads the model per session (a few seconds) instead
of staying resident, so nothing runs between sessions. Shows a tray icon plus
a floating layer-shell bar (indicator.py) while active.

With --caption it runs as live captions instead (Meta+Shift+H): words go to a
click-through caption strip (captions.py) and a transcript file, never to the
keyboard, and typing does not stop it. Runs independently of dictation.

timeline.log records session events and counts only - never dictated text."""
import collections
import datetime
import glob
import json
import os
import queue
import selectors
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import traceback
import warnings

import evdev
import numpy as np
import torch
from PySide6.QtCore import QTimer
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication, QSystemTrayIcon

# Per-machine settings come from ~/.config/voice-dictation.env via dictate.sh.
# Slow CPUs (e.g. Intel N100) need DICTATION_INT8=1 to keep up with speech.
CPU_THREADS = int(os.environ.get("DICTATION_THREADS", "4"))
USE_INT8 = os.environ.get("DICTATION_INT8") == "1"
torch.set_num_threads(CPU_THREADS)

CAPTION_MODE = "--caption" in sys.argv
MODE_NAME = "Captions" if CAPTION_MODE else "Dictation"

STATE_DIR = os.path.expanduser("~/.local/share/dictation")
INT8_CACHE = os.path.join(STATE_DIR, "model-int8.pt")
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or STATE_DIR
PID_FILE = os.path.join(RUNTIME_DIR, "voice-captions.pid" if CAPTION_MODE else "voice-dictation.pid")
TIMELINE_LOG = os.path.join(STATE_DIR, "timeline.log")
LOG_MAX_BYTES = 1_000_000
INDICATOR_SCRIPT = os.path.join(STATE_DIR, "indicator.py")
INDICATOR_X11_SCRIPT = os.path.join(STATE_DIR, "indicator_x11.py")
CAPTIONS_SCRIPT = os.path.join(STATE_DIR, "captions.py")
TRANSCRIPT_DIR = os.path.expanduser(os.environ.get("CAPTION_TRANSCRIPT_DIR", "~/Transcripts"))
# Long calls: restart recognition at a quiet moment every few minutes so each pass stays short.
SEGMENT_SECONDS = float(os.environ.get("CAPTION_SEGMENT_SECONDS", "120")) if CAPTION_MODE else 0.0
PAUSE_NEWLINE_SECONDS = 2.5
LONG_LINE_CHARS = 400
# Speaker-labelled transcripts are made after the call from the saved audio (speakers.sh).
SPEAKERS_SCRIPT = os.path.join(STATE_DIR, "speakers.sh")
SPEAKER_MODEL_CACHE = os.path.expanduser("~/.cache/huggingface/hub/models--pyannote--speaker-diarization-community-1")
SPEAKERS_READY = (os.path.isfile(SPEAKERS_SCRIPT) and os.path.isdir(os.path.join(STATE_DIR, "speakers-venv"))
                  and bool(glob.glob(os.path.join(SPEAKER_MODEL_CACHE, "snapshots", "*", "config.yaml"))))
SPEAKER_LABELS = CAPTION_MODE and SPEAKERS_READY and os.environ.get("CAPTION_SPEAKER_LABELS", "1") == "1"
SAVE_AUDIO = SPEAKER_LABELS or os.environ.get("CAPTION_SAVE_AUDIO") == "1"
# Captions also hear the computer's own audio (Zoom, Webex...). Without headphones the mic hears the
# speakers too, so the mic first goes through a private WebRTC echo canceller (captions-echo-cancel.conf)
# that removes whatever the speakers play - about 35 dB in testing - so call audio isn't doubled.
COMPUTER_AUDIO = CAPTION_MODE and os.environ.get("CAPTION_COMPUTER_AUDIO", "1") == "1"
ECHO_CANCEL = COMPUTER_AUDIO and os.environ.get("CAPTION_ECHO_CANCEL", "1") == "1"
ECHO_CANCEL_CONF = os.path.join(STATE_DIR, "captions-echo-cancel.conf")
AEC_SOURCE = "captions_aec_source"
COMPUTER_SOURCE = "@DEFAULT_MONITOR@"
MAX_COMPUTER_BACKLOG = 16000  # bytes = 0.5 s of 16 kHz 16-bit audio; older computer audio is dropped to stay in sync
MODEL_ID = "nvidia/nemotron-speech-streaming-en-0.6b"
NUM_LOOKAHEAD_TOKENS = 6  # valid: 13, 6, 1, 0 - lower is faster but drops words
SAMPLE_RATE = 16000
STOP_TAIL_SECONDS = 0.5
YDOTOOL_SOCKET = f"/run/user/{os.getuid()}/.ydotool_socket"
IGNORE_DEVICE_SUBSTRINGS = ["ydotool", "rustdesk", "uinput"]
META_KEYS = {evdev.ecodes.KEY_LEFTMETA, evdev.ecodes.KEY_RIGHTMETA}


def log(event: str) -> None:
    try:
        if os.path.getsize(TIMELINE_LOG) > LOG_MAX_BYTES:
            os.replace(TIMELINE_LOG, TIMELINE_LOG + ".1")
    except OSError:
        pass
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    tag = "captions" if CAPTION_MODE else "dictate"
    with open(TIMELINE_LOG, "a") as f:
        f.write(f"{ts} [{tag} pid={os.getpid()}] {event}\n")


def notify_error(message: str) -> None:
    log(f"ERROR POPUP: {message}")
    subprocess.run(["notify-send", "-u", "critical", "-a", MODE_NAME, message], check=False)


def type_text(text: str) -> None:
    if not text:
        return
    env = dict(os.environ, YDOTOOL_SOCKET=YDOTOOL_SOCKET)
    subprocess.run(["ydotool", "type", text], env=env, check=False)


class ImmediateTextStreamer:
    """Yields newly decoded text as soon as each token arrives. The stock
    TextIteratorStreamer holds back the last word until the next word starts,
    which strands the final word (or types it after the key that stopped
    dictation)."""

    def __init__(self, tokenizer):
        self.tokenizer = tokenizer
        self.token_ids: list[int] = []
        self.emitted = ""
        self.q: "queue.Queue[str | None]" = queue.Queue()

    def put(self, value) -> None:
        if value.dim() > 1:
            value = value[0]
        self.token_ids.extend(value.tolist())
        text = self.tokenizer.decode(self.token_ids, skip_special_tokens=True)
        if text.startswith(self.emitted):
            delta = text[len(self.emitted):]
            if delta:
                self.emitted = text
                self.q.put(delta)
        else:
            log("streamer: decoded text no longer extends what was typed; waiting for it to re-converge")

    def end(self) -> None:
        self.q.put(None)

    def __iter__(self):
        return self

    def __next__(self) -> str:
        item = self.q.get()
        if item is None:
            raise StopIteration
        return item


def notify_status(message: str, replace_id: "str | None", timeout_ms: int) -> "str | None":
    # Status pop-up for sessions where the floating bar can't run (X11). Replacing one
    # notification keeps a single pop-up; "transient" keeps it out of notification history.
    cmd = ["notify-send", "-a", "Dictation", "-i", "audio-input-microphone", "-p",
           "-t", str(timeout_ms), "-h", "int:transient:1"]
    if replace_id:
        cmd += ["-r", replace_id]
    result = subprocess.run(cmd + [message], capture_output=True, text=True, check=False)
    return result.stdout.strip() or replace_id


def indicator_command() -> "list[str] | None":
    if CAPTION_MODE:
        if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"):
            return [sys.executable, CAPTIONS_SCRIPT]  # ordinary Qt window, venv Python; KWin rule pins it
        return None
    if os.environ.get("WAYLAND_DISPLAY"):
        return ["/usr/bin/python3", INDICATOR_SCRIPT]  # GTK4 layer-shell, system Python
    if os.environ.get("DISPLAY"):
        return [sys.executable, INDICATOR_X11_SCRIPT]  # override-redirect Qt window, venv Python
    return None


def start_indicator(cmd: "list[str]") -> "subprocess.Popen | None":
    # Separate process that exits when its stdin closes, including if this
    # process dies, so it can't be left on screen.
    try:
        return subprocess.Popen(cmd, stdin=subprocess.PIPE, text=True)
    except OSError as exc:
        log(f"indicator failed to start (dictation unaffected): {exc!r}")
        return None


_indicator_lock = threading.Lock()
_dead_indicators: set[int] = set()


def send_indicator(proc: "subprocess.Popen | None", state: str) -> None:
    if proc is None or proc.pid in _dead_indicators:
        return
    # Caption text is sent from the recognition thread while the Qt thread sends state.
    with _indicator_lock:
        try:
            proc.stdin.write(state + "\n")
            proc.stdin.flush()
        except (OSError, ValueError) as exc:
            # Log once; captions send many updates and the transcript doesn't depend on the window.
            _dead_indicators.add(proc.pid)
            log(f"indicator unreachable (dictation unaffected): {exc!r}")


class StreamingWav:
    """16 kHz 16-bit WAV (mono, or stereo: left = mic, right = computer audio) written as audio
    arrives. The header's sizes are re-patched every few seconds, so the file stays playable even
    if the session dies mid-call."""

    def __init__(self, path: str, channels: int = 1):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        self.file = os.fdopen(fd, "wb")
        self.channels = channels
        self.data_bytes = 0
        self.lock = threading.Lock()
        self.last_patch = time.time()
        self._write_header()

    def _write_header(self) -> None:
        self.file.seek(0)
        self.file.write(b"RIFF" + struct.pack("<I", 36 + self.data_bytes) + b"WAVEfmt "
                        + struct.pack("<IHHIIHH", 16, 1, self.channels, SAMPLE_RATE,
                                      SAMPLE_RATE * 2 * self.channels, 2 * self.channels, 16)
                        + b"data" + struct.pack("<I", self.data_bytes))
        self.file.seek(0, os.SEEK_END)

    def write(self, chunk: bytes) -> None:
        with self.lock:
            if self.file.closed:
                return
            self.file.write(chunk)
            self.data_bytes += len(chunk)
            if time.time() - self.last_patch > 5:
                self._write_header()
                self.file.flush()
                self.last_patch = time.time()

    def close(self) -> None:
        with self.lock:
            frame = 2 * self.channels
            if self.data_bytes % frame:
                pad = frame - self.data_bytes % frame
                self.file.write(b"\0" * pad)
                self.data_bytes += pad
            self._write_header()
            self.file.close()


class CaptionOutput:
    """Caption mode's output: shows recognised text in the caption window and appends it
    to a private transcript file, flushed as it arrives so a crash loses nothing. Also
    records the call audio next to it for the speaker-labelled transcript made afterwards."""

    def __init__(self, window: "subprocess.Popen | None"):
        self.window = window
        os.makedirs(TRANSCRIPT_DIR, exist_ok=True)
        started = datetime.datetime.now()
        stem = os.path.join(TRANSCRIPT_DIR, started.strftime("%Y-%m-%d_%H-%M-%S"))
        self.path = stem + ".txt"
        self.audio_path = stem + ".wav" if SAVE_AUDIO else None
        fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        self.file = os.fdopen(fd, "w")
        self.file.write(f"# Live captions - {socket.gethostname()} - started {started:%Y-%m-%d %H:%M:%S}\n")
        self.file.flush()
        self.audio = StreamingWav(self.audio_path, 2 if COMPUTER_AUDIO else 1) if self.audio_path else None
        self.last_text_time = None
        self.last_char = ""
        self.line_len = 0
        self.chars = 0

    def write(self, text: str) -> None:
        now = time.time()
        paused = self.last_text_time is None or now - self.last_text_time > PAUSE_NEWLINE_SECONDS
        long_line = self.line_len > LONG_LINE_CHARS and self.last_char in ".?!"
        if paused or long_line:
            text = text.lstrip()
            if not text:
                return
            self.file.write(f"\n[{datetime.datetime.now():%H:%M:%S}] ")
            if self.chars:
                send_indicator(self.window, json.dumps({"newline": True}))
            self.line_len = 0
        self.last_text_time = now
        self.file.write(text)
        self.file.flush()
        send_indicator(self.window, json.dumps({"text": text}))
        self.chars += len(text)
        self.line_len += len(text)
        if text.strip():
            self.last_char = text.rstrip()[-1]

    def close(self) -> "tuple[str, str | None] | None":
        if self.audio:
            self.audio.close()
        if self.chars == 0:
            self.file.close()
            os.remove(self.path)
            if self.audio_path:
                os.remove(self.audio_path)
            return None
        self.file.write(f"\n\n# ended {datetime.datetime.now():%H:%M:%S}\n")
        self.file.close()
        return self.path, self.audio_path


def _die_with_parent() -> None:
    # PR_SET_PDEATHSIG: if this session dies, the kernel stops its echo canceller too.
    import ctypes
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)


def start_echo_cancel() -> "subprocess.Popen | None":
    if not ECHO_CANCEL:
        return None
    if not (shutil.which("pipewire") and os.path.isfile(ECHO_CANCEL_CONF)):
        log("echo canceller unavailable (pipewire binary or config missing) - captions use the plain mic")
        return None
    try:
        return subprocess.Popen(["pipewire", "-c", ECHO_CANCEL_CONF], stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=_die_with_parent)
    except OSError as exc:
        log(f"echo canceller failed to start ({exc!r}) - captions use the plain mic")
        return None


def stop_echo_cancel(proc: "subprocess.Popen | None") -> None:
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()


def source_exists(name: str, timeout: float) -> bool:
    deadline = time.time() + timeout
    while True:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True, text=True, check=False).stdout
        if any(line.split("\t")[1:2] == [name] for line in out.splitlines()):
            return True
        if time.time() >= deadline:
            return False
        time.sleep(0.2)


def start_speaker_labels(audio: str, transcript: str) -> None:
    # Detached so it carries on after this session exits; speakers.sh notifies when done.
    try:
        subprocess.Popen([SPEAKERS_SCRIPT, audio, transcript], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log("speaker labelling started in the background")
    except OSError as exc:
        log(f"could not start speaker labelling: {exc!r}")


def stop_indicator(proc: "subprocess.Popen | None") -> None:
    if proc is None:
        return
    try:
        proc.stdin.close()
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()


def real_keyboard_devices() -> list[str]:
    paths = []
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities()
        is_kbd = evdev.ecodes.EV_KEY in caps and evdev.ecodes.KEY_A in caps.get(evdev.ecodes.EV_KEY, [])
        if not is_kbd:
            continue
        if any(s in dev.name.lower() for s in IGNORE_DEVICE_SUBSTRINGS):
            continue
        paths.append(path)
    return paths


def remove_pid_file(owner: int) -> None:
    # Only remove the file if it still names `owner`, so a session that is finishing
    # can't delete the PID file of a new session started in the meantime.
    if read_pid_file() == owner:
        try:
            os.remove(PID_FILE)
        except FileNotFoundError:
            pass


def load_model():
    from transformers import AutoModelForRNNT

    if not USE_INT8:
        return AutoModelForRNNT.from_pretrained(MODEL_ID, device_map="cpu", dtype=torch.float32)
    # Quantizing takes ~11s on an N100, so do it once and reuse the saved result.
    if os.path.exists(INT8_CACHE):
        try:
            return torch.load(INT8_CACHE, weights_only=False, mmap=True)
        except Exception as exc:
            log(f"int8 model cache unusable ({exc!r}) - rebuilding it")
    model = AutoModelForRNNT.from_pretrained(MODEL_ID, device_map="cpu", dtype=torch.float32)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        model = torch.ao.quantization.quantize_dynamic(model, {torch.nn.Linear}, dtype=torch.qint8)
    torch.save(model, INT8_CACHE + ".tmp")
    os.replace(INT8_CACHE + ".tmp", INT8_CACHE)
    log("built int8 model cache")
    return model


def run_dictation(work_done: threading.Event, stop_event: threading.Event, listening_started: threading.Event,
                  session: dict) -> None:
    try:
        _run_dictation_inner(stop_event, listening_started, session)
    except Exception:
        log(f"CRASHED:\n{traceback.format_exc()}")
        notify_error(f"{MODE_NAME} crashed - see ~/.local/share/dictation/timeline.log")
    finally:
        stop_echo_cancel(session.get("echo_cancel"))
        output = session.get("output")
        if output is not None:
            session["transcript"] = output.close()
        # The Qt main loop only quits once this is set, so it must happen even on a crash.
        work_done.set()


def _run_dictation_inner(stop_event: threading.Event, listening_started: threading.Event, session: dict) -> None:
    t0 = time.time()
    # Started before the model loads so it's ready by the time capture begins.
    session["echo_cancel"] = start_echo_cancel()
    from transformers import AutoProcessor

    processor = AutoProcessor.from_pretrained(MODEL_ID)
    model = load_model()
    processor.set_num_lookahead_tokens(NUM_LOOKAHEAD_TOKENS)
    log(f"model loaded in {time.time() - t0:.2f}s (int8={USE_INT8}, threads={CPU_THREADS})")

    audio_q: "queue.Queue[bytes | None]" = queue.Queue()
    peak_rms = [0.0]
    recorder = None
    if CAPTION_MODE:
        # Created before capture starts so the saved audio and the transcript share a start time.
        session["output"] = CaptionOutput(session.get("indicator"))
        recorder = session["output"].audio

    def record(device: "str | None") -> subprocess.Popen:
        # Without --latency-msec, parecord delivers audio in ~2s bursts, delaying every word.
        cmd = ["parecord", "--channels=1", "--rate=16000", "--format=s16le", "--file-format=raw", "--latency-msec=50"]
        if device:
            cmd.append(f"--device={device}")
        return subprocess.Popen(cmd, stdout=subprocess.PIPE)

    mic_device = None
    if session.get("echo_cancel") is not None:
        if source_exists(AEC_SOURCE, timeout=5):
            mic_device = AEC_SOURCE
        else:
            log("echo canceller didn't come up - captions use the plain mic")
            stop_echo_cancel(session.pop("echo_cancel"))
    if CAPTION_MODE:
        log(f"audio: mic={'echo-cancelled' if mic_device else 'plain'}, computer audio={'on' if COMPUTER_AUDIO else 'off'}")

    def capture_audio():
        mic = record(mic_device)
        computer = record(COMPUTER_SOURCE) if COMPUTER_AUDIO else None
        backlog = bytearray()
        backlog_lock = threading.Lock()

        def read_computer():
            while True:
                data = computer.stdout.read(4096)
                if not data:
                    return
                with backlog_lock:
                    backlog.extend(data)
                    excess = len(backlog) - MAX_COMPUTER_BACKLOG
                    if excess > 0:
                        del backlog[:excess + excess % 2]

        if computer is not None:
            threading.Thread(target=read_computer, daemon=True).start()

        leftover = b""
        tail_bytes_left = None
        while tail_bytes_left is None or tail_bytes_left > 0:
            chunk = mic.stdout.read(4096)
            if not chunk:
                break
            chunk = leftover + chunk
            leftover = chunk[len(chunk) - len(chunk) % 2:]
            chunk = chunk[:len(chunk) - len(chunk) % 2]
            if not chunk:
                continue
            if computer is None:
                mixed = chunk
                if recorder is not None:
                    recorder.write(chunk)
            else:
                # The mic is the clock: take the same amount of computer audio, silence if none arrived.
                m = np.frombuffer(chunk, dtype=np.int16)
                c = np.zeros_like(m)
                with backlog_lock:
                    take = min(len(backlog), len(chunk)) // 2 * 2
                    c[:take // 2] = np.frombuffer(bytes(backlog[:take]), dtype=np.int16)
                    del backlog[:take]
                mixed = np.clip(m.astype(np.int32) + c, -32768, 32767).astype(np.int16).tobytes()
                if recorder is not None:
                    recorder.write(np.column_stack((m, c)).tobytes())
            audio_q.put(mixed)
            pcm = np.frombuffer(mixed, dtype=np.int16).astype(np.float32)
            if len(pcm):
                peak_rms[0] = max(peak_rms[0], float(np.sqrt(np.mean(pcm**2))))
            if tail_bytes_left is not None:
                tail_bytes_left -= len(chunk)
            elif stop_event.is_set():
                # Keep a short tail so a syllable still in the audio pipe isn't cut off.
                tail_bytes_left = int(SAMPLE_RATE * 2 * STOP_TAIL_SECONDS)
        mic.terminate()
        if computer is not None:
            computer.terminate()
        audio_q.put(None)

    threading.Thread(target=capture_audio, daemon=True).start()

    def watch_physical_keyboard():
        devices = [evdev.InputDevice(p) for p in real_keyboard_devices()]
        if not devices:
            log("no physical keyboard found - stop with Win+H only")
            return
        sel = selectors.DefaultSelector()
        for dev in devices:
            sel.register(dev, selectors.EVENT_READ)

        # Discard the tail of the Win+H press that launched us.
        startup_deadline = time.time() + 1.0
        while time.time() < startup_deadline:
            for key, _ in sel.select(timeout=0.1):
                key.fileobj.read()

        meta_held = False
        while not stop_event.is_set():
            for key, _ in sel.select(timeout=0.3):
                for event in key.fileobj.read():
                    if event.type != evdev.ecodes.EV_KEY:
                        continue
                    if event.code in META_KEYS:
                        meta_held = event.value != 0
                        continue
                    # Keys pressed with Meta held are a Win+H stop, handled by the second
                    # invocation; treating them as typing too would race it into a new session.
                    if event.value == 1 and not meta_held:
                        log("keypress -> stopping")
                        stop_event.set()
                        return

    # Captions must keep running while the user types, so only dictation stops on a keypress.
    if not CAPTION_MODE:
        threading.Thread(target=watch_physical_keyboard, daemon=True).start()

    sample_buffer = np.zeros(0, dtype=np.float32)
    audio_ended = False

    def next_samples(n: int):
        nonlocal sample_buffer, audio_ended
        # The end-of-audio sentinel is consumed only once; without this flag the next
        # call blocks forever, generate() never returns and the last word is never flushed.
        if audio_ended and len(sample_buffer) == 0:
            return None
        while len(sample_buffer) < n and not audio_ended:
            chunk = audio_q.get()
            if chunk is None:
                audio_ended = True
                break
            pcm = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
            sample_buffer = np.concatenate([sample_buffer, pcm])
        if len(sample_buffer) == 0:
            return None
        if len(sample_buffer) < n:
            sample_buffer = np.concatenate([sample_buffer, np.zeros(n - len(sample_buffer), dtype=np.float32)])
        out, sample_buffer = sample_buffer[:n], sample_buffer[n:]
        return out

    emit = session["output"].write if CAPTION_MODE else type_text

    listen_start = None
    chars_out = 0
    segment = 0
    gen_thread = None
    while True:
        first_samples = next_samples(processor.num_samples_first_audio_chunk)
        if first_samples is None:
            if segment == 0:
                notify_error("No audio captured - check the microphone")
                return
            break

        first_chunk_inputs = processor(
            first_samples, sampling_rate=SAMPLE_RATE, is_streaming=True, is_first_audio_chunk=True, return_tensors="pt"
        ).to(model.device, dtype=model.dtype)
        segment_cut = [False]

        def input_features_generator(first_chunk_inputs=first_chunk_inputs, first_samples=first_samples,
                                     segment_cut=segment_cut):
            yield first_chunk_inputs.input_features[:, : processor.num_mel_frames_first_audio_chunk, :]
            segment_samples = len(first_samples)
            recent_rms = collections.deque(maxlen=64)
            while True:
                chunk_samples = next_samples(processor.num_samples_per_audio_chunk)
                if chunk_samples is None:
                    return
                inputs = processor(
                    chunk_samples, sampling_rate=SAMPLE_RATE, is_streaming=True, is_first_audio_chunk=False, return_tensors="pt"
                ).to(model.device, dtype=model.dtype)
                yield inputs.input_features
                if not SEGMENT_SECONDS:
                    continue
                # End this pass at a quiet chunk (quietest quarter of the last ~30s) once it's long
                # enough; the next pass starts fresh, so cost per word doesn't grow over a long call.
                segment_samples += len(chunk_samples)
                rms = float(np.sqrt(np.mean(chunk_samples ** 2)))
                recent_rms.append(rms)
                seconds = segment_samples / SAMPLE_RATE
                if seconds >= SEGMENT_SECONDS and len(recent_rms) >= 8:
                    if rms <= float(np.percentile(recent_rms, 25)) or seconds >= 2 * SEGMENT_SECONDS:
                        segment_cut[0] = True
                        return

        streamer = ImmediateTextStreamer(processor.tokenizer)
        generate_kwargs = {**first_chunk_inputs, "input_features": input_features_generator(), "streamer": streamer}

        def run_generate(generate_kwargs=generate_kwargs, streamer=streamer):
            try:
                model.generate(**generate_kwargs)
            except Exception:
                log(f"model.generate() CRASHED:\n{traceback.format_exc()}")
            finally:
                streamer.end()

        gen_thread = threading.Thread(target=run_generate, daemon=True)
        gen_thread.start()

        if segment == 0:
            listening_started.set()
            log("listening")
            listen_start = time.time()
        first_text = True
        for text_chunk in streamer:
            # A new pass starts without the separating space the previous pass would have produced.
            if segment > 0 and first_text and not text_chunk[:1].isspace():
                text_chunk = " " + text_chunk
            first_text = False
            emit(text_chunk)
            chars_out += len(text_chunk)

        gen_thread.join(timeout=0.5)
        if not segment_cut[0]:
            break
        segment += 1
        log(f"recognition pass {segment} ended at a quiet moment; starting the next")

    remove_pid_file(os.getpid())
    if not CAPTION_MODE:
        type_text(" ")
    log(
        f"stopped: {time.time() - listen_start:.1f}s listened, {chars_out} chars output, {segment + 1} pass(es), "
        f"peak mic level {peak_rms[0]:.0f}, model thread finished={not gen_thread.is_alive()}"
    )


def read_pid_file() -> "int | None":
    try:
        with open(PID_FILE) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def is_dictation_process(pid: int) -> bool:
    # Guards against a stale PID file pointing at an unrelated process that reused the number,
    # and keeps dictation and captions from stopping each other.
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = f.read().split(b"\0")
    except OSError:
        return False
    return any(a.endswith(b"dictate.py") for a in args) and (b"--caption" in args) == CAPTION_MODE


def stop_dictation(pid: int) -> None:
    log(f"stop requested for pid={pid}")
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        time.sleep(0.1)
        if not is_dictation_process(pid):
            return
    log(f"pid={pid} did not exit within 3s - force killing it and its recorder")
    subprocess.run(["pkill", "-9", "-P", str(pid), "-x", "parecord"], check=False)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def main() -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    pid = read_pid_file()
    if pid is not None:
        if is_dictation_process(pid):
            stop_dictation(pid)
            return
        log(f"removing stale PID file (pid={pid} is not a dictation process)")
        remove_pid_file(pid)

    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    log("session starting")

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    work_done = threading.Event()
    stop_event = threading.Event()
    listening_started = threading.Event()
    tray = QSystemTrayIcon()
    tray.setIcon(QIcon.fromTheme("dictation-idle"))
    tray.setToolTip(f"{MODE_NAME}: loading...")
    if CAPTION_MODE:
        # The caption strip is click-through, so the tray icon is the mouse way to stop.
        tray.activated.connect(lambda _reason: stop_event.set())
    tray.show()
    bar_cmd = indicator_command()
    use_bar = bar_cmd is not None
    indicator = start_indicator(bar_cmd) if use_bar else None
    if CAPTION_MODE and not use_bar:
        notify_error("No graphical session for the caption window - the transcript is still being saved")
    notice_id = None if use_bar else notify_status(f"Loading {MODE_NAME.lower()}…", None, 60000)
    stop_hint = "Meta+Shift+H or click the tray icon to stop" if CAPTION_MODE else "press Win+H or any key to stop"

    session = {"indicator": indicator}
    signal.signal(signal.SIGTERM, lambda signum, frame: stop_event.set())
    threading.Thread(target=run_dictation, args=(work_done, stop_event, listening_started, session), daemon=True).start()

    shown_listening = False
    window_gone = False
    timer = QTimer()

    # Cross-thread Qt signals didn't reliably repaint the tray icon here; polling a flag does.
    def poll():
        nonlocal shown_listening, notice_id, window_gone
        if CAPTION_MODE and indicator is not None and not window_gone and indicator.poll() is not None:
            window_gone = True
            if indicator.returncode == 0:
                log("caption window closed by the user -> stopping")
                stop_event.set()
            else:
                log(f"caption window exited with code {indicator.returncode} (transcript still being saved)")
                notify_error("The caption window closed unexpectedly - the transcript is still being saved")
        if not shown_listening and listening_started.is_set():
            shown_listening = True
            tray.setIcon(QIcon.fromTheme("dictation-listening"))
            tray.setToolTip(f"{MODE_NAME}: LISTENING - {stop_hint}")
            send_indicator(indicator, json.dumps({"state": "listening"}) if CAPTION_MODE else "listening")
            if not use_bar:
                notice_id = notify_status(f"Listening — {stop_hint}", notice_id, 0)
        if work_done.is_set():
            timer.stop()
            stop_indicator(indicator)
            if CAPTION_MODE:
                saved = session.get("transcript")
                if not saved:
                    notify_status("Captions stopped (nothing was heard, no transcript saved)", notice_id, 8000)
                else:
                    transcript, audio = saved
                    message = f"Captions stopped. Transcript saved:\n{transcript}"
                    if SPEAKER_LABELS and audio:
                        start_speaker_labels(audio, transcript)
                        message += "\nA speaker-labelled version will follow in a few minutes."
                    notify_status(message, notice_id, 10000)
            elif not use_bar:
                notify_status("Dictation stopped", notice_id, 1500)
            remove_pid_file(os.getpid())
            app.quit()

    timer.timeout.connect(poll)
    timer.start(150)
    app.exec()


if __name__ == "__main__":
    if "--prepare-model" in sys.argv:
        t0 = time.time()
        load_model()
        print(f"model ready in {time.time() - t0:.1f}s (int8={USE_INT8})")
        sys.exit(0)
    try:
        main()
    except Exception as exc:
        log(f"TOP-LEVEL CRASH:\n{traceback.format_exc()}")
        notify_error(f"Dictation error: {exc}")
        raise
