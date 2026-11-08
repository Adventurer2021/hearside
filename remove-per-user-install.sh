#!/bin/bash
# HearSide - remove an OLDER per-user install (1.0.x, in ~/.local/share/dictation) from your own
# account. Run as yourself, not with sudo:   ./remove-per-user-install.sh
# Use it after the shared install (sudo ./install.sh, 1.1.0 or newer) is on this computer: once your
# own copy is gone, the shared one takes over at your next login, and about 7 GB is freed.
# Your transcripts in ~/Transcripts are KEPT. Nothing system-wide is touched.
set -uo pipefail

OLD="$HOME/.local/share/dictation"
UNITS="$HOME/.config/systemd/user"
M="$HOME/.cache/huggingface/hub"
ask() { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }

[ "$(id -u)" -ne 0 ] || { echo "Run it as yourself, not with sudo." >&2; exit 1; }
[ -f /opt/hearside/dictate.py ] || { echo "The shared HearSide isn't installed here yet - run 'sudo ./install.sh' first." >&2; exit 1; }
[ -d "$OLD" ] || [ -f "$UNITS/dictation-hotkey.service" ] || { echo "No older per-user install found for '$USER'."; exit 0; }
echo "This removes the older HearSide copy from '$USER' ($(du -sh "$OLD" 2>/dev/null | cut -f1) in $OLD)."
echo "Your transcripts in ~/Transcripts are kept. The shared install takes over at your next login."
ask "Continue?" || exit 0

echo "== Stopping and removing the old services =="
pkill -f "$OLD/dictate.py" 2>/dev/null || true
pkill -f "$OLD/speakers.sh" 2>/dev/null || true
systemctl --user disable --now dictation-hotkey.service ydotoold.service 2>/dev/null || true
rm -f "$UNITS/dictation-hotkey.service" "$UNITS/ydotoold.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "== Old files =="
# Keep the old logs next to the new ones, in case they are wanted later.
mkdir -p "$HOME/.local/share/hearside/old-logs"
cp -p "$OLD"/*.log "$OLD"/*.log.1 "$HOME/.local/share/hearside/old-logs/" 2>/dev/null || true
# Menu entries that start the old copy (including ones from before it was called HearSide).
grep -l -F "$OLD/" "$HOME"/.local/share/applications/*.desktop 2>/dev/null | while read -r entry; do
    echo "removing old menu entry $(basename "$entry")"
    rm -f "$entry"
done
rm -rf "$OLD"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/dictation-idle.svg" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/dictation-listening.svg" \
      "$HOME/.local/share/applications/hearside-captions.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
if [ -f "$HOME/.config/voice-dictation.env" ]; then
    echo "Kept your personal settings ~/.config/voice-dictation.env (they override the machine's):"
    sed 's/^/    /' "$HOME/.config/voice-dictation.env"
fi

if ls -d "$M"/models--nvidia--nemotron-speech-streaming-en-0.6b "$M"/models--pyannote--speaker-diarization-community-1 \
        >/dev/null 2>&1; then
    echo
    echo "Your own copies of the speech models (~2.5 GB) are in $M; the shared install has its own."
    if ask "Remove your copies?"; then
        # Newer huggingface_hub versions keep the real files in a shared store ($M/blobs) and only link
        # to them from the model folders; note those files first, and delete each once nothing links to it.
        mapfile -t targets < <(find "$M"/models--nvidia--nemotron-speech-streaming-en-0.6b \
            "$M"/models--pyannote--speaker-diarization-community-1 -type l -exec readlink -f {} + 2>/dev/null \
            | grep -F "$M/blobs/" | sort -u)
        rm -rf "$M"/models--nvidia--nemotron-speech-streaming-en-0.6b "$M"/models--pyannote--speaker-diarization-community-1
        for t in "${targets[@]}"; do
            name="$(basename "$t")"
            [ -f "$t" ] && [ -z "$(find "$M" -lname "*$name" -print -quit 2>/dev/null)" ] && rm -f "$t"
        done
        find "$M/blobs" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        echo "removed (other Hugging Face models, if any, were left alone)"
    fi
fi

echo "== Starting the shared HearSide for '$USER' =="
# At this login the shared services stood aside for the old copy; start them now rather than
# relying on a logout (a lingering user session, e.g. an open SSH connection, would skip them).
systemctl --user daemon-reload 2>/dev/null || true
if id -nG | grep -qw input; then
    systemctl --user start hearside-ydotoold.service hearside-hotkey.service 2>/dev/null || true
    systemctl --user is-active hearside-ydotoold.service hearside-hotkey.service | paste -sd' ' \
        | sed 's/^/typing helper, hotkeys: /'
else
    echo "'$USER' isn't in the 'input' group yet (ask whoever installed HearSide to re-run sudo ./install.sh),"
    echo "then log out and back in."
fi

echo
echo "Done. Win+H and Meta+Shift+H now use the shared HearSide (after a logout/login if anything above"
echo "isn't 'active')."
