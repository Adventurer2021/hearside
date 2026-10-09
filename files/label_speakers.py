#!/usr/bin/env python3
"""Writes the speaker-labelled transcript of a captions session: takes the
speaker turns from diarize.py and re-transcribes each turn from the call audio
with the same offline speech model dictation uses (non-streaming, which is
more accurate than the live captions because it hears whole sentences).
Runs in the dictation venv inside the network-less sandbox (speakers.sh).

Usage: label_speakers.py call.wav segments.json live-transcript.txt out.txt"""
import datetime
import json
import os
import re
import sys
import time
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictate  # noqa: E402  (shares the model loading, incl. the int8 cache on slow CPUs)

SAMPLE_RATE = 16000
MERGE_GAP = 1.0        # same speaker again within this many seconds -> one turn
MIN_TURN = 0.3         # shorter turns are noise
PAD = 0.15             # seconds of context either side of a turn
MAX_PIECE = 30.0       # long turns are transcribed in pieces of at most this length
SPLIT_SEARCH = 5.0     # ...cut at the quietest moment in the last few seconds of each piece
SIDE_MIN_LEVEL = 0.002  # computer-audio level (RMS, full scale = 1) below which a recording counts as mic-only


def read_audio(path: str) -> "tuple[np.ndarray, np.ndarray | None]":
    """Returns (audio to transcribe, per-channel audio or None). Stereo recordings are the
    echo-cancelled mic (left) + computer audio (right); they're mixed as the live captions were."""
    with wave.open(path) as w:
        channels = w.getnchannels()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    if channels == 1:
        return pcm, None
    split = pcm.reshape(-1, channels)
    return np.clip(split.sum(axis=1), -1.0, 1.0), split


def split_by_channel(segments: list[dict], split: np.ndarray) -> list[dict]:
    """With the mic and computer audio on separate channels, someone in the room (mic) can never
    be the same person as someone on the call (computer audio), so a voice-matched speaker whose
    turns come from both sides is split in two. Short phrases are where voice matching alone slips."""
    right = split[:, 1]
    if float(np.sqrt(np.mean(right ** 2))) < SIDE_MIN_LEVEL:
        return segments  # no computer audio in this recording (e.g. a speakerphone call)
    out = []
    for s in segments:
        a, b = int(s["start"] * SAMPLE_RATE), int(s["end"] * SAMPLE_RATE)
        mic = float(np.sqrt(np.mean(split[a:b, 0] ** 2))) if b > a else 0.0
        computer = float(np.sqrt(np.mean(split[a:b, 1] ** 2))) if b > a else 0.0
        side = "room" if mic > computer else "call"
        out.append(dict(s, speaker=f"{s['speaker']}|{side}"))
    return out


def call_start(live_transcript: str, wav_path: str) -> datetime.datetime:
    try:
        with open(live_transcript) as f:
            m = re.search(r"started (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", f.readline())
        if m:
            return datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
    except OSError:
        pass
    return datetime.datetime.fromtimestamp(os.path.getmtime(wav_path))


def merge_turns(segments: list[dict]) -> list[dict]:
    turns: list[dict] = []
    for s in segments:
        if turns and turns[-1]["speaker"] == s["speaker"] and s["start"] - turns[-1]["end"] <= MERGE_GAP:
            turns[-1]["end"] = max(turns[-1]["end"], s["end"])
        else:
            turns.append(dict(s))
    return [t for t in turns if t["end"] - t["start"] >= MIN_TURN]


def pieces(audio: np.ndarray) -> list[np.ndarray]:
    out, limit, search = [], int(MAX_PIECE * SAMPLE_RATE), int(SPLIT_SEARCH * SAMPLE_RATE)
    frame = SAMPLE_RATE // 10
    while len(audio) > limit:
        window = audio[limit - search:limit]
        energy = [float(np.mean(window[i:i + frame] ** 2)) for i in range(0, len(window) - frame + 1, frame)]
        cut = limit - search + int(np.argmin(energy)) * frame + frame // 2
        out.append(audio[:cut])
        audio = audio[cut:]
    out.append(audio)
    return out


def main() -> None:
    wav_path, seg_path, live_path, out_path = sys.argv[1:5]
    t0 = time.time()
    import torch
    from transformers import AutoProcessor

    # dictate sets its live-dictation thread count; this runs after the call at low priority, so use more.
    torch.set_num_threads(int(os.environ.get("SPEAKER_THREADS") or max(1, (os.cpu_count() or 2) - 2)))

    processor = AutoProcessor.from_pretrained(dictate.MODEL_ID)
    model = dictate.load_model()
    audio, split = read_audio(wav_path)
    with open(seg_path) as f:
        segments = json.load(f)["segments"]
    if split is not None:
        segments = split_by_channel(segments, split)
    turns = merge_turns(segments)

    names: dict[str, str] = {}  # pyannote labels -> "Speaker 1", "Speaker 2"... in order of first appearance
    started = call_start(live_path, wav_path)
    lines = []
    for turn in turns:
        a = audio[max(0, int((turn["start"] - PAD) * SAMPLE_RATE)):int((turn["end"] + PAD) * SAMPLE_RATE)]
        texts = []
        for piece in pieces(a):
            if len(piece) < SAMPLE_RATE // 4:
                continue
            inputs = processor(piece, sampling_rate=SAMPLE_RATE, return_tensors="pt").to(model.device, dtype=model.dtype)
            with torch.no_grad():
                result = model.generate(**inputs)
            seqs = result.sequences if hasattr(result, "sequences") else result
            texts.append(processor.batch_decode(seqs, skip_special_tokens=True)[0].strip())
        text = " ".join(t for t in texts if t)
        if not text:
            continue
        name = names.setdefault(turn["speaker"], f"Speaker {len(names) + 1}")
        stamp = started + datetime.timedelta(seconds=turn["start"])
        lines.append(f"[{stamp:%H:%M:%S}] {name}: {text}")

    header = [
        f"# Speaker-labelled transcript - {os.uname().nodename} - call started {started:%Y-%m-%d %H:%M:%S}",
        "# Made offline from the call audio after the call. Speakers are numbered in the order they first",
        "# spoke; rename them with find & replace (e.g. \"Speaker 1\" -> \"John\").",
        f"# Speakers found: {len(names)}",
        "",
    ]
    fd = os.open(out_path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(header + lines) + "\n")
    os.replace(out_path + ".tmp", out_path)
    print(f"label_speakers: {len(audio) / SAMPLE_RATE:.0f}s of audio, {len(turns)} turns, "
          f"{len(names)} speaker(s), {len(lines)} lines written in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
