#!/bin/bash
DIR="$HOME/.local/share/dictation"
LOG="$DIR/debug.log"
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 1000000 ]; then
    mv -f "$LOG" "$LOG.1"
fi
CONF="$HOME/.config/voice-dictation.env"
if [ -f "$CONF" ]; then
    set -a
    . "$CONF"
    set +a
fi
# Model is already cached; stop transformers from contacting huggingface.co on every load.
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
exec "$DIR/venv/bin/python3" "$DIR/dictate.py" "$@" >> "$LOG" 2>&1
