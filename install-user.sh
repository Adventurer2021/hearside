#!/bin/bash
# Hearside, part 2 (normal user, no sudo; install.sh runs this for you): copies the scripts,
# builds the Python environment, downloads the speech model (~2.5 GB, one
# time), and enables the Win+H listener. Safe to re-run to upgrade/repair.
#
# Options (for slow CPUs such as the Intel N100 - see README):
#   --int8        use an 8-bit model (~2x faster, same words in testing)
#   --threads N   CPU cores dictation may use (default 4)
# Without options, an existing ~/.config/voice-dictation.env is left as-is.
set -euo pipefail

int8=""
threads=""
while [ $# -gt 0 ]; do
    case "$1" in
        --int8) int8=1 ;;
        --threads) threads="${2:?--threads needs a number}"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

MODEL_ID="nvidia/nemotron-speech-streaming-en-0.6b"
CONF="$HOME/.config/voice-dictation.env"
TORCH_VERSION="2.14.1"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/dictation"
UNIT_DIR="$HOME/.config/systemd/user"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

[ "$(id -u)" -ne 0 ] || fail "run this as your normal user, not root/sudo"

echo "== Pre-flight checks =="
for cmd in ydotool ydotoold parecord notify-send busctl python3; do
    command -v "$cmd" >/dev/null || fail "'$cmd' not found - run 'sudo bash $HERE/install-system.sh' first"
done
id -nG | grep -qw input || fail "this login session isn't in the 'input' group yet - log out and back in after install-system.sh"
[ -w /dev/uinput ] || fail "/dev/uinput isn't writable - check /etc/udev/rules.d/99-uinput.rules, then reboot"
[ "${XDG_SESSION_TYPE:-}" = "wayland" ] || warn "session type is '${XDG_SESSION_TYPE:-unknown}', not wayland - only tested on KDE Plasma Wayland"
busctl --user list 2>/dev/null | grep -q "org.kde.kglobalaccel" \
    || warn "KDE's global shortcut service (kglobalaccel) not found - Win+H needs KDE Plasma"
pactl info >/dev/null 2>&1 || warn "no PulseAudio/PipeWire sound server answering - the microphone may not work"
{ command -v pipewire >/dev/null && ls /usr/lib*/*/spa-0.2/aec/libspa-aec-webrtc.so /usr/lib*/spa-0.2/aec/libspa-aec-webrtc.so >/dev/null 2>&1; } \
    || warn "PipeWire's WebRTC echo canceller not found - captions will mix computer audio with the plain mic (echo possible)"
/usr/bin/python3 "$HERE/files/indicator.py" --check >/dev/null 2>&1 \
    || warn "gtk4-layer-shell not available - the floating 'Listening' bar will be skipped (tray icon still works)"

echo "== Copying files to $DEST =="
mkdir -p "$DEST" "$UNIT_DIR" "$ICON_DIR"
install -m 644 "$HERE/files/dictate.py" "$HERE/files/hotkey_listener.py" "$HERE/files/indicator.py" "$HERE/files/indicator_x11.py" "$HERE/files/captions.py" "$DEST/"
install -m 755 "$HERE/files/dictate.sh" "$HERE/files/setup-caption-window-rule.sh" "$DEST/"
install -m 644 "$HERE/files/captions-echo-cancel.conf" "$DEST/"
install -m 644 "$HERE/files/icon-idle.svg" "$ICON_DIR/dictation-idle.svg"
install -m 644 "$HERE/files/icon-listening.svg" "$ICON_DIR/dictation-listening.svg"
install -m 644 "$HERE/files/ydotoold.service" "$HERE/files/dictation-hotkey.service" "$UNIT_DIR/"

echo "== Python environment (CPU-only torch; first run downloads ~1 GB) =="
# A venv built for another Python (e.g. after a distro upgrade) can't be reused.
want_py="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
if [ -d "$DEST/venv" ] && [ ! -d "$DEST/venv/lib/python$want_py" ]; then
    echo "Existing environment was built for a different Python - rebuilding it for $want_py"
    rm -rf "$DEST/venv"
fi
[ -x "$DEST/venv/bin/python3" ] || python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install --upgrade pip
"$DEST/venv/bin/pip" install "torch==$TORCH_VERSION" --index-url https://download.pytorch.org/whl/cpu
"$DEST/venv/bin/pip" install -r "$HERE/requirements.txt"

echo "== Speech model (first run downloads ~2.5 GB; dictation itself runs offline) =="
# Only the transformers weights + configs; the repo also carries ~3 GB of .nemo/.gguf copies we don't use.
"$DEST/venv/bin/python3" -c "from huggingface_hub import snapshot_download; print(snapshot_download('$MODEL_ID', allow_patterns=['*.json', 'model.safetensors']))"

if [ -n "$int8$threads" ]; then
    mkdir -p "$(dirname "$CONF")"
    {
        echo "# Voice dictation per-machine settings (written by install-user.sh)"
        if [ -n "$int8" ]; then echo "DICTATION_INT8=1"; fi
        if [ -n "$threads" ]; then echo "DICTATION_THREADS=$threads"; fi
    } > "$CONF"
fi
if [ -f "$CONF" ]; then
    echo "== Machine settings ($CONF) =="
    grep -v "^#" "$CONF"
    if grep -q "^DICTATION_INT8=1" "$CONF"; then
        echo "Preparing the 8-bit model once (can take ~10-20 s on a slow CPU)..."
        (set -a; . "$CONF"; set +a; HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
            "$DEST/venv/bin/python3" "$DEST/dictate.py" --prepare-model)
    fi
fi

echo "== Caption launcher entry (also names the caption window's app ID for KDE) =="
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/hearside-captions.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Live Captions (Hearside)
Comment=Live captions from the microphone, saved to ~/Transcripts. Same as Meta+Shift+H.
Exec=$DEST/dictate.sh --caption
Icon=dictation-listening
Categories=Utility;Accessibility;
StartupNotify=false
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "== Caption window rule (keep above, never focused, remember position/size) =="
bash "$DEST/setup-caption-window-rule.sh"

echo "== Enabling services =="
systemctl --user daemon-reload
systemctl --user enable --now ydotoold.service
systemctl --user enable dictation-hotkey.service
systemctl --user restart dictation-hotkey.service
sleep 3

echo
echo "== Status =="
systemctl --user is-active ydotoold.service dictation-hotkey.service || true
[ -S "/run/user/$(id -u)/.ydotool_socket" ] && echo "ydotool socket: OK" || warn "ydotool socket missing - check: systemctl --user status ydotoold"
grep "\[listener\]" "$DEST/timeline.log" 2>/dev/null | tail -2 || true
echo
echo "Done. Click into any text field and press Win+H to start dictating;"
echo "press Win+H again or any key to stop."
echo "Press Meta+Shift+H for live captions (typing doesn't stop them; Meta+Shift+H"
echo "again, the tray icon or closing the caption window does). Move and resize the"
echo "window freely; A-/A+ change the text size. Transcripts are saved in ~/Transcripts."
