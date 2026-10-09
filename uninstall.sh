#!/bin/bash
# Hearside - uninstaller. Run as your normal user:   ./uninstall.sh
# Removes the programs, Python environments, hotkeys, services, launcher entry
# and caption window rule. Your transcripts in ~/Transcripts are KEPT.
# It asks before removing the downloaded speech models and before the
# system-level parts (sudo).
set -uo pipefail

DEST="$HOME/.local/share/dictation"
UNITS="$HOME/.config/systemd/user"
RULE_ID="8c1e5b7a-2f94-4d3e-a6b1-0e9c7d42f5a3"
ask() { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }

[ "$(id -u)" -ne 0 ] || { echo "Run ./uninstall.sh as your normal user, not with sudo." >&2; exit 1; }
echo "This removes Hearside for '$USER'. Your transcripts in ~/Transcripts are kept."
ask "Continue?" || exit 0

echo "== Stopping anything running =="
pkill -f "$DEST/dictate.py" 2>/dev/null || true
pkill -f "$DEST/speakers.sh" 2>/dev/null || true
systemctl --user disable --now dictation-hotkey.service ydotoold.service 2>/dev/null || true
rm -f "$UNITS/dictation-hotkey.service" "$UNITS/ydotoold.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "== Hotkeys =="
# The listener marks its shortcuts inactive when it stops; remove them from KDE's list too.
for action in toggle-dictation toggle-captions; do
    busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel unregister ss voice-dictation "$action" \
        >/dev/null 2>&1 || true
done

echo "== Files =="
rm -rf "$DEST"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/dictation-idle.svg" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/dictation-listening.svg" \
      "$HOME/.local/share/applications/hearside-captions.desktop" \
      "$HOME/.config/voice-dictation.env" "$HOME/.config/voice-captions.json"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "== Caption window rule =="
RC="$HOME/.config/kwinrulesrc"
if [ -f "$RC" ] && grep -q "^\[$RULE_ID\]" "$RC"; then
    cp -p "$RC" "$RC.bak-$(date +%Y%m%d-%H%M%S)"
    python3 - "$RC" "$RULE_ID" <<'EOF'
import sys
path, rule = sys.argv[1], sys.argv[2]
out, skip, count = [], False, None
for line in open(path).read().splitlines():
    if line.startswith("["):
        skip = line.strip() == f"[{rule}]"
    if skip:
        continue
    if line.startswith("rules="):
        ids = [r for r in line[6:].split(",") if r and r != rule]
        line = "rules=" + ",".join(ids)
        count = len(ids)
    out.append(line)
text = "\n".join(out) + "\n"
if count is not None:
    import re
    text = re.sub(r"^count=\d+$", f"count={count}", text, flags=re.M)
open(path, "w").write(text)
EOF
    (qdbus6 org.kde.KWin /KWin reconfigure || qdbus org.kde.KWin /KWin reconfigure) >/dev/null 2>&1 || true
    echo "removed (backup of kwinrulesrc kept next to it)"
fi

M="$HOME/.cache/huggingface/hub"
if ls -d "$M"/models--nvidia--nemotron-speech-streaming-en-0.6b "$M"/models--pyannote--speaker-diarization-community-1 >/dev/null 2>&1; then
    echo
    echo "The downloaded speech models (~2.5 GB) are in $M."
    if ask "Remove them too?"; then
        rm -rf "$M"/models--nvidia--nemotron-speech-streaming-en-0.6b "$M"/models--pyannote--speaker-diarization-community-1
        echo "models removed (other Hugging Face models, if any, were left alone)"
    fi
fi

echo
echo "System-level parts: ydotool in /usr/local/bin, the /dev/uinput rule, and your 'input' group"
echo "membership. Distribution packages that were installed are left in place (other programs may use them)."
if ask "Remove the system-level parts too? (asks for your password)"; then
    sudo rm -f /usr/local/bin/ydotool /usr/local/bin/ydotoold /etc/udev/rules.d/99-uinput.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    if ask "Also remove '$USER' from the 'input' group? (only if nothing else of yours needs it)"; then
        sudo gpasswd -d "$USER" input
    fi
    echo "Note: if gtk4-layer-shell was built from source (Fedora/RHEL family), it remains under /usr/local."
fi

echo
echo "Hearside removed. Your transcripts are still in ~/Transcripts."
