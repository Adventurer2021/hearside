#!/bin/bash
# HearSide - speaker-labelled transcripts (optional add-on; root, for every user).
# After each captions session it writes ~/Transcripts/<time>-speakers.txt ("Speaker 1: ...
# / Speaker 2: ...") using pyannote's speaker-diarization-community-1, fully offline, in a
# sandbox with no network, with pyannote's telemetry off. Run after install-app.sh
# (install.sh runs it for you). Safe to re-run.
#
# The model (33 MB) is "gated" on Hugging Face: it is downloaded once with a free account
# (see INSTALL.md, "Speaker labels"), or copied from another computer that already has it:
#     sudo bash install-speakers.sh --model-from DIR
# where DIR is a Hugging Face hub folder holding models--pyannote--speaker-diarization-community-1
# (e.g. ~/.cache/huggingface/hub from an older per-user install, or /opt/hearside/hf/hub).
set -euo pipefail

PREFIX=/opt/hearside
VENV="$PREFIX/speakers-venv"
TORCH_VERSION="2.14.1"    # same CPU-only build as the dictation venv
MODEL="pyannote/speaker-diarization-community-1"
M=models--pyannote--speaker-diarization-community-1
export HF_HOME="$PREFIX/hf"
CACHE="$HF_HOME/hub/$M"

fail() { echo "ERROR: $*" >&2; exit 1; }

model_from=""
while [ $# -gt 0 ]; do
    case "$1" in
        --model-from) model_from="${2:?--model-from needs a folder}"; shift ;;
        *) fail "unknown option: $1" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || fail "run with: sudo bash $0"
[ -x "$PREFIX/venv/bin/python3" ] && [ -f "$PREFIX/dictate.py" ] || fail "install HearSide first (install.sh)"
umask 022
# Same sandbox choice as speakers.sh: unshare, or bubblewrap where Ubuntu's AppArmor blocks unshare.
# (Checked as a normal user too, since that is who runs it after each call.)
if unshare --user --net --map-current-user true 2>/dev/null; then
    SANDBOX=(unshare --user --net --map-current-user)
elif command -v bwrap >/dev/null && bwrap --unshare-net --dev-bind / / true 2>/dev/null; then
    SANDBOX=(bwrap --unshare-net --dev-bind / /)
else
    fail "this system can't run a network-less sandbox (unshare or bwrap); speaker labels refuse to run without it"
fi
echo "network-less sandbox: ${SANDBOX[0]}"

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
# speakers.sh also forces telemetry off and blocks the network for every run.

echo "== Model =="
if ls "$CACHE"/snapshots/*/config.yaml >/dev/null 2>&1; then
    echo "already present: $CACHE"
elif [ -n "$model_from" ]; then
    ls "$model_from/$M"/snapshots/*/config.yaml >/dev/null 2>&1 || fail "no $M model in $model_from"
    install -d "$HF_HOME/hub"
    # -h: huggingface_hub keeps the real files in a blob store and links to them; copy the files.
    tar -h -C "$model_from" -cf - "$M/snapshots" "$M/refs" | tar -C "$HF_HOME/hub" -xf -
    echo "copied from $model_from"
else
    echo "Not present. Trying a download with a Hugging Face token, if one is logged in..."
    if PYANNOTE_METRICS_ENABLED=0 "$VENV/bin/python3" -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL')"; then
        echo "Downloaded."
    else
        fail "model missing. Follow INSTALL.md \"Speaker labels\" (accept the terms at https://huggingface.co/$MODEL,
       then run 'sudo HF_HOME=$HF_HOME $PREFIX/venv/bin/hf auth login'), then re-run this script - or use --model-from"
    fi
fi
chown -R root:root "$PREFIX"
chmod -R go-w,a+rX "$PREFIX"

echo "== Offline check (inside the network-less sandbox) =="
cd /tmp
PYANNOTE_METRICS_ENABLED=0 HF_HUB_OFFLINE=1 "${SANDBOX[@]}" "$VENV/bin/python3" -c \
    "from pyannote.audio import Pipeline; Pipeline.from_pretrained('$MODEL'); print('pyannote loads offline: OK')" 2>&1 \
    | grep -v -i warn | tail -1

echo
echo "Done. From each user's next captions session (Meta+Shift+H) on, the call audio is saved next to"
echo "the transcript and a '-speakers.txt' version follows a few minutes after they stop."
echo "To turn it off for one user: CAPTION_SPEAKER_LABELS=0 in their ~/.config/voice-dictation.env"
echo "To delete call audio once labelled: CAPTION_KEEP_AUDIO=0 in the same file"
