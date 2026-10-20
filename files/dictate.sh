#!/bin/bash
# Starts dictate.py (dictation, or live captions with --caption) for the user running it.
# The program, its Python environment and the speech model are shared, read-only, in the
# Hearside folder this script lives in (normally /opt/hearside); logs and settings are per user.
APP="$(dirname "$(readlink -f "$0")")"
STATE="$HOME/.local/share/hearside"
mkdir -p "$STATE"
LOG="$STATE/debug.log"
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 1000000 ]; then
    mv -f "$LOG" "$LOG.1"
fi
# Machine-wide settings (written by the installer), then this user's own overrides.
for CONF in "$APP/hearside.env" "$HOME/.config/voice-dictation.env"; do
    if [ -f "$CONF" ]; then
        set -a
        . "$CONF"
        set +a
    fi
done
# The models are already in the shared cache; stop anything from contacting huggingface.co.
export HF_HOME="$APP/hf" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
exec "$APP/venv/bin/python3" "$APP/dictate.py" "$@" >> "$LOG" 2>&1
