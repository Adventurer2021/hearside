#!/bin/bash
# Hearside, part 2 (root): the program itself, installed once for every user of this computer.
#   /opt/hearside            program files (read-only for users)
#   /opt/hearside/venv       Python environment with CPU-only PyTorch (~4 GB)
#   /opt/hearside/hf         the speech model (~2.5 GB), shared by everyone
#   /opt/hearside/hearside.env   machine settings (8-bit model, CPU threads)
#   /usr/lib/systemd/user    hotkey + typing services, started at every user's login
#   /usr/share/applications, /usr/share/icons   menu entry and icons
# Per user (made automatically at login): ~/.local/share/hearside (logs), ~/Transcripts,
# KWin rules for the two Hearside windows, the Win+H / Meta+Shift+H shortcuts.
# Normally run by install.sh. Options: --int8, --threads N (written to hearside.env).
set -euo pipefail

PREFIX=/opt/hearside
MODEL_ID="nvidia/nemotron-speech-streaming-en-0.6b"
TORCH_VERSION="2.14.1"
UNIT_DIR=/usr/lib/systemd/user
HERE="$(cd "$(dirname "$0")" && pwd)"

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

[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0" >&2; exit 1; }
umask 022

echo "== Program files -> $PREFIX =="
install -d -m 755 "$PREFIX"
install -m 644 "$HERE"/files/{dictate.py,hotkey_listener.py,bar.py,captions.py,captions-echo-cancel.conf} "$PREFIX/"
install -m 644 "$HERE"/files/{diarize.py,label_speakers.py} "$PREFIX/"
install -m 755 "$HERE"/files/{dictate.sh,speakers.sh,setup-window-rules.sh} "$PREFIX/"
install -m 644 "$HERE/VERSION" "$PREFIX/VERSION"

echo "== Python environment (CPU-only PyTorch; first install downloads ~1 GB) =="
# A venv built for another Python (e.g. after a distribution upgrade) can't be reused.
want_py="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
if [ -d "$PREFIX/venv" ] && [ ! -d "$PREFIX/venv/lib/python$want_py" ]; then
    echo "Existing environment was built for a different Python - rebuilding it for $want_py"
    rm -rf "$PREFIX/venv"
fi
[ -x "$PREFIX/venv/bin/python3" ] || python3 -m venv "$PREFIX/venv"
"$PREFIX/venv/bin/pip" install -q --upgrade pip
"$PREFIX/venv/bin/pip" install -q "torch==$TORCH_VERSION" --index-url https://download.pytorch.org/whl/cpu
"$PREFIX/venv/bin/pip" install -q -r "$HERE/requirements.txt"
echo "Python environment ready."

echo "== Speech model (first install downloads ~2.5 GB; dictation itself runs offline) =="
# Only the transformers weights + configs; the repo also carries ~3 GB of .nemo/.gguf copies we don't use.
HF_HOME="$PREFIX/hf" "$PREFIX/venv/bin/python3" -c \
    "from huggingface_hub import snapshot_download; print(snapshot_download('$MODEL_ID', allow_patterns=['*.json', 'model.safetensors']))"

echo "== Machine settings ($PREFIX/hearside.env) =="
if [ -n "$int8$threads" ] || [ ! -f "$PREFIX/hearside.env" ]; then
    {
        echo "# Hearside machine settings, for every user (written by the installer)."
        echo "# A user can override them in ~/.config/voice-dictation.env."
        if [ -n "$int8" ]; then echo "DICTATION_INT8=1"; fi
        if [ -n "$threads" ]; then echo "DICTATION_THREADS=$threads"; fi
    } > "$PREFIX/hearside.env"
fi
grep -v '^#' "$PREFIX/hearside.env" || echo "(defaults: full-precision model, 4 threads)"
if grep -q '^DICTATION_INT8=1' "$PREFIX/hearside.env"; then
    echo "Preparing the shared 8-bit model once (can take ~10-30 s on a slow CPU)..."
    rm -f "$PREFIX/model-int8.pt"
    (set -a; . "$PREFIX/hearside.env"; set +a; HF_HOME="$PREFIX/hf" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
        "$PREFIX/venv/bin/python3" "$PREFIX/dictate.py" --prepare-model)
    chmod 644 "$PREFIX/model-int8.pt"
else
    rm -f "$PREFIX/model-int8.pt"
fi
# Everything under /opt/hearside is root-owned and read-only for users.
chown -R root:root "$PREFIX"
chmod -R go-w "$PREFIX"

echo "== Services for every user (start at login) =="
install -m 644 "$HERE"/files/{hearside-hotkey.service,hearside-ydotoold.service} "$UNIT_DIR/"
systemctl --global enable hearside-ydotoold.service hearside-hotkey.service

echo "== Menu entry and icons =="
install -m 644 "$HERE/files/icon-idle.svg" /usr/share/icons/hicolor/scalable/apps/dictation-idle.svg
install -m 644 "$HERE/files/icon-listening.svg" /usr/share/icons/hicolor/scalable/apps/dictation-listening.svg
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
cat > /usr/share/applications/hearside-captions.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Live Captions (Hearside)
Comment=Live captions from the microphone, saved to ~/Transcripts. Same as Meta+Shift+H.
Exec=$PREFIX/dictate.sh --caption
Icon=dictation-listening
Categories=Utility;Accessibility;
StartupNotify=false
EOF
cat > /usr/share/applications/hearside-dictation.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Dictation (Hearside)
Comment=Opens the dictation bar: type by voice into any app. Same as Win+H.
Exec=$PREFIX/dictate.sh
Icon=dictation-idle
Categories=Utility;Accessibility;
StartupNotify=false
EOF
update-desktop-database -q /usr/share/applications 2>/dev/null || true

echo "== Installed =="
du -sh "$PREFIX" | sed 's/^/size: /'
echo "version: $(cat "$PREFIX/VERSION")"
