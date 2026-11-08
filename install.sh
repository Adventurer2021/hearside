#!/bin/bash
# HearSide - installer for KDE Plasma (5.27 or newer, Wayland or X11). Installs once for every
# user of this computer, like the built-in Win+H on Windows:
#     sudo ./install.sh
# Options:
#     --int8           8-bit speech model: about 2x faster, for slow CPUs (asked automatically on them)
#     --threads N      CPU cores the live speech recognition may use (default 4)
#     --users "a b"    only set up these accounts (default: every regular account on this computer)
#     --speakers       also set up speaker-labelled transcripts without asking
#     --no-speakers    skip speaker-labelled transcripts without asking
#     --speaker-model-from DIR   copy the speaker model from DIR instead of downloading it
#     --check          only check this computer meets the requirements and list the system
#                      packages that would be installed; install nothing
#     --yes            install missing system packages without asking
# Safe to re-run: it repairs or upgrades an existing install, and sets up accounts added since.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX=/opt/hearside

app_args=()
system_args=()
users=()
speakers=ask
speaker_from=""
check_only=no
while [ $# -gt 0 ]; do
    case "$1" in
        --int8) app_args+=(--int8) ;;
        --threads) app_args+=(--threads "${2:?--threads needs a number}"); shift ;;
        --users) read -r -a users <<<"${2:?--users needs a list}"; shift ;;
        --speakers) speakers=yes ;;
        --no-speakers) speakers=no ;;
        --speaker-model-from) speaker_from="${2:?--speaker-model-from needs a folder}"; speakers=yes; shift ;;
        --check) check_only=yes ;;
        --yes) system_args+=(--yes) ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (see ./install.sh --help)" >&2; exit 1 ;;
    esac
    shift
done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask() { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }
# For a recommended "yes": Enter alone answers yes.
ask_yes() { local reply; read -r -p "$1 [Y/n] " reply; [[ ! "$reply" =~ ^[Nn] ]]; }
stop() { printf '\nCannot install: %s\n' "$1" >&2; shift; for line in "$@"; do echo "  $line" >&2; done; exit 1; }

# ---- 1. KDE Plasma is required - check that before anything else ------------------------------
plasma_version="$(grep -h '^X-KDE-PluginInfo-Version=' /usr/share/wayland-sessions/plasma*.desktop \
    /usr/share/xsessions/plasma*.desktop 2>/dev/null | head -1 | cut -d= -f2 || true)"
if [ -z "$plasma_version" ] && command -v plasmashell >/dev/null; then
    plasma_version="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)"
fi
[ -n "$plasma_version" ] || stop "HearSide needs the KDE Plasma desktop, and it isn't installed here." \
    "Requirements: KDE Plasma 5.27 or newer (see INSTALL.md)."
IFS=. read -r plasma_major plasma_minor _ <<<"$plasma_version"
if [ "${plasma_major:-0}" -lt 5 ] || { [ "$plasma_major" -eq 5 ] && [ "${plasma_minor:-0}" -lt 27 ]; }; then
    stop "KDE Plasma $plasma_version is too old; HearSide needs 5.27 or newer."
fi
if [ "$check_only" = yes ]; then
    echo "OK: KDE Plasma $plasma_version. This computer can run HearSide."
    bash "$HERE/install-system.sh" --list-missing
    exit 0
fi
[ "$(id -u)" -eq 0 ] || stop "run it with sudo:  sudo $0" "It installs once, for every user of this computer."

bold "HearSide installer"
echo "KDE Plasma $plasma_version detected."
echo "Offline voice dictation (Win+H), live captions (Meta+Shift+H) and, optionally,"
echo "speaker-labelled transcripts, for every user of this computer. Everything runs here;"
echo "internet is only needed now, to download software and the speech model (~4 GB, once)."

# Slow CPUs need the 8-bit model to keep up with speech (it gives the same words in testing).
if [ ${#app_args[@]} -eq 0 ] && ! grep -qs '^DICTATION_' "$PREFIX/hearside.env" && [ "$(nproc)" -le 4 ]; then
    cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    echo
    echo "This CPU ($cpu, $(nproc) threads) is on the slow side for live speech recognition."
    if ask_yes "Use the faster 8-bit model and leave one core free? (recommended here)"; then
        app_args=(--int8 --threads "$(( $(nproc) - 1 ))")
    fi
fi

bold "Step 1 of 3: system packages and user accounts"
bash "$HERE/install-system.sh" "${system_args[@]}" "${users[@]}"

bold "Step 2 of 3: dictation and live captions (shared, in $PREFIX)"
bash "$HERE/install-app.sh" "${app_args[@]}"

bold "Step 3 of 3: speaker-labelled transcripts (optional)"
if [ "$speakers" = ask ]; then
    echo "After each captions session this can write a second transcript that says who spoke:"
    echo "    [14:02:25] Speaker 2: Sure, so about the files..."
    echo "It runs offline in a no-network sandbox. It needs about 1.5 GB more disk and, once,"
    echo "a free Hugging Face account to download the model (INSTALL.md walks you through it)."
    ask "Set up speaker-labelled transcripts?" && speakers=yes || speakers=no
fi
if [ "$speakers" = yes ]; then
    speaker_args=()
    [ -n "$speaker_from" ] && speaker_args=(--model-from "$speaker_from")
    cache="$PREFIX/hf/hub/models--pyannote--speaker-diarization-community-1"
    if [ -z "$speaker_from" ] && ! ls "$cache"/snapshots/*/config.yaml >/dev/null 2>&1; then
        echo
        echo "The speaker model needs a one-time download with a Hugging Face account:"
        echo "  1. Sign in at https://huggingface.co (create a free account if needed)."
        echo "  2. Open https://huggingface.co/pyannote/speaker-diarization-community-1 , fill in the two"
        echo "     required fields (Company/university, Use case) and click 'Agree and access repository'."
        echo "  3. At https://huggingface.co/settings/tokens create a token of type 'Read' and copy it."
        echo "  4. Paste it below (it won't show as you paste). Answer 'n' if asked about git credentials."
        echo
        read -r -p "Press Enter when steps 1-3 are done... " _
        HF_HOME="$PREFIX/hf" "$PREFIX/venv/bin/hf" auth login
        logged_in=yes
    fi
    if ! bash "$HERE/install-speakers.sh" "${speaker_args[@]}"; then
        echo "Speaker labels weren't set up - dictation and captions work without them."
        echo "Fix the problem shown above, then run: sudo bash $HERE/install-speakers.sh"
    fi
    if [ "${logged_in:-no}" = yes ]; then
        HF_HOME="$PREFIX/hf" "$PREFIX/venv/bin/hf" auth logout >/dev/null 2>&1 || true
        echo "Logged this computer out of Hugging Face again - the token is no longer stored here."
    fi
else
    echo "Skipped. To add it later: sudo bash $HERE/install-speakers.sh (see INSTALL.md)"
fi

# The speaker setup ran `hf auth login` as root, which leaves /opt/hearside/hf mode 700
# (root-only) to protect the HF token. The runtime runs as each unprivileged user and
# loads the public dictation model from this shared cache offline (HF_HUB_OFFLINE=1),
# so every user must be able to traverse and read it. `install-speakers.sh` re-opens it
# on success, but if the gated speaker download failed (403) it exits before that point.
# Re-open (if it exists) the shared HF cache so dictation/captions can read model
# artifacts, without exposing credential material. Only directories get traverse
# (x) and only files under hub/ get read (r).
# The runtime runs as unprivileged users and the dictation model is public
# (no HF token needed). Remove any token file from the shared cache: leaving it
# here either exposes it to all users or, if root-only, makes it unreadable and
# crashes the app. Tokens for gated models are used only by the installer (as root).
if [ -d "$PREFIX/hf" ]; then
    find "$PREFIX/hf" -type d -exec chmod a+x {} +
    [ -d "$PREFIX/hf/hub" ] && find -L "$PREFIX/hf/hub" -type f -exec chmod a+r {} + 2>/dev/null || true
    rm -f "$PREFIX/hf/token"
fi

bold "Older per-user installs"
old=()
while IFS=: read -r name home; do
    if [ -d "$home/.local/share/dictation/venv" ]; then old+=("$name"); fi
done < <(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1 ":" $6}')
if [ ${#old[@]} -gt 0 ]; then
    echo "These accounts still have their own older copy (it keeps working, and the shared one stays"
    echo "out of its way): ${old[*]}"
    echo "To switch one over and free its ~7 GB, that user runs:  $HERE/remove-per-user-install.sh"
else
    echo "none"
fi

bold "All done"
echo "Restart the computer (or have each user log out and back in) so the new services and the"
echo "input group take effect. Then, for everyone set up above:"
echo "  Win+H        opens the dictation bar and listens; Win+H or its microphone starts/stops"
echo "               listening, any key stops it, its x closes the bar; drag it anywhere"
echo "  Meta+Shift+H start/stop live captions (or 'Live Captions (HearSide)' in the app menu)"
echo "  Transcripts  ~/Transcripts/ (each user's own)"
echo "  Uninstall    sudo $HERE/uninstall.sh"
