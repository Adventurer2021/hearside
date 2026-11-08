#!/bin/bash
# Runs after a captions session (launched by dictate.py): works out who spoke
# when and writes a speaker-labelled transcript next to the live one, e.g.
#   ~/Transcripts/2026-10-09_14-02-17.txt          live captions
#   ~/Transcripts/2026-10-09_14-02-17-speakers.txt  Speaker 1 / Speaker 2 ...
# Everything runs offline, at low CPU priority, one job at a time, and inside a
# sandbox with no network at all (unshare --net), so nothing can leave the machine.
#
# Usage: speakers.sh call.wav live-transcript.txt
set -uo pipefail

# Programs and models are shared, read-only, in the HearSide folder (normally /opt/hearside);
# the log is per user.
DIR="$(dirname "$(readlink -f "$0")")"
STATE="$HOME/.local/share/hearside"
mkdir -p "$STATE"
LOG="$STATE/speakers.log"
for CONF in "$DIR/hearside.env" "$HOME/.config/voice-dictation.env"; do
    [ -f "$CONF" ] && { set -a; . "$CONF"; set +a; }
done
export HF_HOME="$DIR/hf" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 PYANNOTE_METRICS_ENABLED=0

WAV="$1"
LIVE="$2"
OUT="${LIVE%.txt}-speakers.txt"
SEG="${XDG_RUNTIME_DIR:-/tmp}/speakers-$$.json"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
notify() { notify-send -a HearSide -i dictation-listening "$@" 2>/dev/null || true; }
fail() {
    log "FAILED: $*"
    notify -u critical "Speaker labels failed" "The live transcript is fine. Details: $LOG"
    rm -f "$SEG"
    exit 1
}

if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 1000000 ]; then mv -f "$LOG" "$LOG.1"; fi

# No network inside the sandbox. If neither tool works here, refuse rather than run unsandboxed.
# Ubuntu (apparmor_restrict_unprivileged_userns=1) blocks plain unshare but allows bubblewrap.
if unshare --user --net --map-current-user true 2>/dev/null; then
    SANDBOX=(unshare --user --net --map-current-user)
elif command -v bwrap >/dev/null && bwrap --unshare-net --dev-bind / / true 2>/dev/null; then
    SANDBOX=(bwrap --unshare-net --dev-bind / /)
else
    fail "no network-less sandbox available (tried unshare --user --net and bwrap --unshare-net)"
fi

# Log the start before taking the lock, so we can see sessions that are blocked waiting.
log "start: $(basename "$WAV")"

# One job at a time. Wait up to 5 minutes for the lock; if another instance is stuck,
# give up rather than blocking forever.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/speakers.lock"
if ! flock -w 300 9; then
    log "FAILED: could not acquire speaker labelling lock within 5 minutes"
    exit 1
fi
timeout -k 30 600 nice -n 10 "${SANDBOX[@]}" "$DIR/speakers-venv/bin/python3" "$DIR/diarize.py" "$WAV" "$SEG" >> "$LOG" 2>&1 \
    || fail "diarize.py exited $?"
timeout -k 30 600 nice -n 10 "${SANDBOX[@]}" "$DIR/venv/bin/python3" "$DIR/label_speakers.py" "$WAV" "$SEG" "$LIVE" "$OUT" >> "$LOG" 2>&1 \
    || fail "label_speakers.py exited $?"
rm -f "$SEG"

if [ "${CAPTION_KEEP_AUDIO:-1}" = "0" ]; then
    rm -f "$WAV"
    log "audio deleted (CAPTION_KEEP_AUDIO=0)"
fi
log "done: $(basename "$OUT")"
notify "Speaker-labeled transcript ready" "$OUT"
