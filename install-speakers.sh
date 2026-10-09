#!/bin/bash
# Hearside - speaker-labelled transcripts (optional add-on; normal user,
# no sudo). Run after install-user.sh (install.sh runs it for you). After each
# captions session it writes ~/Transcripts/<time>-speakers.txt ("Speaker 1: ...
# / Speaker 2: ...") using pyannote's speaker-diarization-community-1, fully
# offline, in a sandbox with no network, with pyannote's telemetry off.
# Safe to re-run.
#
# The model (33 MB) is "gated" on Hugging Face: each person downloads it once
# with their own free account (see INSTALL.md, "Speaker labels"). To set up a
# second machine of your own without logging in again, copy it over:
#   M=models--pyannote--speaker-diarization-community-1
#   tar -h -C ~/.cache/huggingface/hub -cf - $M/snapshots $M/refs \
#     | ssh OTHER-MACHINE 'mkdir -p ~/.cache/huggingface/hub && tar -C ~/.cache/huggingface/hub -xf -'
# (-h matters: huggingface_hub keeps the real files in a shared blob store outside
#  the model folder, so copying the folder as-is would carry only dangling links)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/dictation"
VENV="$DEST/speakers-venv"
TORCH_VERSION="2.14.1"    # same CPU-only build as the dictation venv
MODEL="pyannote/speaker-diarization-community-1"
CACHE="$HOME/.cache/huggingface/hub/models--pyannote--speaker-diarization-community-1"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || fail "run this as your normal user, not root/sudo"
[ -x "$DEST/venv/bin/python3" ] && [ -f "$DEST/dictate.py" ] || fail "install dictation first (install-user.sh)"
# Same sandbox choice as speakers.sh: unshare, or bubblewrap where Ubuntu's AppArmor blocks unshare.
if unshare --user --net --map-current-user true 2>/dev/null; then
    SANDBOX=(unshare --user --net --map-current-user)
elif command -v bwrap >/dev/null && bwrap --unshare-net --dev-bind / / true 2>/dev/null; then
    SANDBOX=(bwrap --unshare-net --dev-bind / /)
else
    fail "this system can't run a network-less sandbox (unshare or bwrap); speaker labels refuse to run without it"
fi
echo "network-less sandbox: ${SANDBOX[0]}"

echo "== Files =="
install -m 644 "$HERE/files/diarize.py" "$HERE/files/label_speakers.py" "$DEST/"
install -m 755 "$HERE/files/speakers.sh" "$DEST/"

echo "== Python environment for pyannote (separate from dictation's; CPU-only torch) =="
want_py="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
if [ -d "$VENV" ] && [ ! -d "$VENV/lib/python$want_py" ]; then
    echo "Existing environment was built for a different Python - rebuilding it for $want_py"
    rm -rf "$VENV"
fi
echo "Installing pyannote and its own copy of PyTorch (about 1.5 GB). This takes several minutes"
echo "and shows little output - please wait..."
[ -x "$VENV/bin/python3" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "torch==$TORCH_VERSION" --index-url https://download.pytorch.org/whl/cpu
constraints="$(mktemp)"; echo "torch==$TORCH_VERSION" > "$constraints"
echo "  PyTorch done; installing pyannote.audio..."
"$VENV/bin/pip" install -q pyannote.audio --extra-index-url https://download.pytorch.org/whl/cpu -c "$constraints"
echo "  pyannote.audio installed."
rm -f "$constraints"

echo "== Telemetry off (saved as pyannote's default; speakers.sh also forces it off and blocks the network) =="
PYANNOTE_METRICS_ENABLED=0 "$VENV/bin/python3" -c \
    "from pyannote.audio.telemetry import set_telemetry_metrics; set_telemetry_metrics(False, save_choice_as_default=True)"

echo "== Model =="
if ls "$CACHE"/snapshots/*/config.yaml >/dev/null 2>&1; then
    echo "already present: $CACHE"
else
    echo "Not present. Trying a download with a Hugging Face token, if one is logged in..."
    if PYANNOTE_METRICS_ENABLED=0 "$VENV/bin/python3" -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL')"; then
        echo "Downloaded. You can now log this machine out of Hugging Face: $DEST/venv/bin/hf auth logout"
    else
        fail "model missing. Follow INSTALL.md \"Speaker labels\" (accept the terms at https://huggingface.co/$MODEL,
       then run '$DEST/venv/bin/hf auth login'), then re-run this script - or copy it from another machine (see the top of this script)"
    fi
fi

echo "== Offline check (inside the network-less sandbox) =="
cd /tmp
PYANNOTE_METRICS_ENABLED=0 HF_HUB_OFFLINE=1 "${SANDBOX[@]}" "$VENV/bin/python3" -c \
    "from pyannote.audio import Pipeline; Pipeline.from_pretrained('$MODEL'); print('pyannote loads offline: OK')" 2>&1 \
    | grep -v -i warn | tail -1

echo
echo "Done. From the next captions session (Meta+Shift+H) on, the call audio is saved next to the"
echo "transcript and a '-speakers.txt' version follows a few minutes after you stop."
echo "To turn it off: CAPTION_SPEAKER_LABELS=0 in ~/.config/voice-dictation.env"
echo "To delete call audio once labelled: CAPTION_KEEP_AUDIO=0 in the same file"
