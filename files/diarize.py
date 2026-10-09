#!/usr/bin/env python3
"""Who spoke when: runs pyannote's speaker-diarization-community-1 on a call's
audio and writes the speaker turns as JSON. Runs in speakers-venv, offline from
the local Hugging Face cache, inside a network-less sandbox (speakers.sh), with
pyannote's usage telemetry switched off.

Usage: diarize.py call.wav segments.json"""
import os

os.environ["PYANNOTE_METRICS_ENABLED"] = "0"
os.environ.setdefault("HF_HUB_OFFLINE", "1")

import json  # noqa: E402
import sys  # noqa: E402
import time  # noqa: E402
import wave  # noqa: E402

import numpy as np  # noqa: E402
import torch  # noqa: E402

MODEL = "pyannote/speaker-diarization-community-1"
# Runs after the call at low priority (nice), so it may use most of the CPU.
THREADS = int(os.environ.get("SPEAKER_THREADS") or max(1, (os.cpu_count() or 2) - 2))
torch.set_num_threads(THREADS)
# pyannote slides its 10 s analysis window 1 s at a time by default. Measured on a 20-thread Intel i9
# (10-min two-voice test): 1 s = 0.41x real time, 2.5 s = 0.18x with the same 99.7% of speech labelled
# correctly, 5 s = 0.08x but 99.1%. So 2.5 s.
STEP_SECONDS = float(os.environ.get("SPEAKER_WINDOW_STEP", "2.5"))


def read_wav(path: str) -> "tuple[torch.Tensor, int]":
    with wave.open(path) as w:
        if w.getsampwidth() != 2:
            sys.exit(f"diarize: {path} is not 16-bit PCM")
        rate, channels = w.getframerate(), w.getnchannels()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    if channels > 1:
        pcm = pcm.reshape(-1, channels).mean(axis=1)
    return torch.from_numpy(pcm).unsqueeze(0), rate


def main() -> None:
    wav_path, out_path = sys.argv[1:3]
    t0 = time.time()
    from pyannote.audio import Pipeline

    pipeline = Pipeline.from_pretrained(MODEL)
    seg = getattr(pipeline, "_segmentation", None)  # internal; if a pyannote update renames it, keep the default
    if seg is not None and hasattr(seg, "duration"):
        seg.step = min(STEP_SECONDS, seg.duration)
    else:
        print("diarize: couldn't set the window step - using pyannote's (slower) default", file=sys.stderr)
    waveform, rate = read_wav(wav_path)
    seconds = waveform.shape[1] / rate
    # Passing the samples directly skips pyannote's own file decoding (torchcodec/ffmpeg).
    result = pipeline({"waveform": waveform, "sample_rate": rate})
    # community-1 also returns an "exclusive" version with overlaps resolved to one speaker,
    # which is what a written transcript needs.
    annotation = getattr(result, "exclusive_speaker_diarization", None) or getattr(result, "speaker_diarization", result)
    segments = [
        {"start": round(turn.start, 3), "end": round(turn.end, 3), "speaker": str(label)}
        for turn, _track, label in annotation.itertracks(yield_label=True)
    ]
    segments.sort(key=lambda s: s["start"])
    tmp = out_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"audio_seconds": seconds, "segments": segments}, f)
    os.replace(tmp, out_path)
    speakers = len({s["speaker"] for s in segments})
    print(f"diarize: {seconds:.0f}s of audio -> {len(segments)} turns, {speakers} speaker(s) in {time.time() - t0:.1f}s "
          f"(step {STEP_SECONDS}s, {THREADS} threads)")


if __name__ == "__main__":
    main()
