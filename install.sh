#!/bin/bash
# Hearside - one-step installer. Run as your normal user (NOT with sudo):
#     ./install.sh
# It asks for your password once, for the system part. Options:
#     --int8           8-bit speech model: about 2x faster, for slow CPUs (Intel N100 and similar)
#     --threads N      CPU cores the live speech recognition may use (default 4)
#     --speakers       also set up speaker-labelled transcripts without asking
#     --no-speakers    skip speaker-labelled transcripts without asking
# Safe to re-run: it repairs or upgrades an existing install.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/dictation"
PYANNOTE_MODEL="pyannote/speaker-diarization-community-1"
SPEAKER_CACHE="$HOME/.cache/huggingface/hub/models--pyannote--speaker-diarization-community-1"

user_args=()
speakers=ask
while [ $# -gt 0 ]; do
    case "$1" in
        --int8) user_args+=(--int8) ;;
        --threads) user_args+=(--threads "${2:?--threads needs a number}"); shift ;;
        --speakers) speakers=yes ;;
        --no-speakers) speakers=no ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (see ./install.sh --help)" >&2; exit 1 ;;
    esac
    shift
done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask() { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }

[ "$(id -u)" -ne 0 ] || { echo "Run ./install.sh as your normal user, not with sudo - it asks for your password when needed." >&2; exit 1; }

bold "Hearside installer"
echo "Offline voice dictation (Win+H), live captions (Meta+Shift+H) and, optionally,"
echo "speaker-labelled transcripts. Everything runs on this computer; internet is only"
echo "needed now, to download software and the speech model (~4 GB in total)."
desktop="${XDG_CURRENT_DESKTOP:-unknown}"
if [[ "$desktop" != *KDE* ]]; then
    echo
    echo "NOTE: this desktop is '$desktop', not KDE Plasma. The speech engine, captions and transcripts"
    echo "will work, but the Win+H / Meta+Shift+H hotkeys and the caption window's 'stay on top'"
    echo "behaviour are KDE-only. See INSTALL.md, 'Other desktops'."
    ask "Continue anyway?" || exit 0
fi

# Slow CPUs need the 8-bit model to keep up with speech (it gives the same words in testing).
if [ ${#user_args[@]} -eq 0 ] && [ ! -f "$HOME/.config/voice-dictation.env" ] && [ "$(nproc)" -le 4 ]; then
    cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    if [[ "$cpu" =~ N[0-9]{2,3}|Celeron|Atom|Pentium ]]; then
        echo
        echo "This CPU ($cpu) is on the slow side for live speech recognition."
        ask "Use the faster 8-bit model and leave one core free? (recommended here)" \
            && user_args=(--int8 --threads "$(( $(nproc) - 1 ))")
    fi
fi

bold "Step 1 of 3: system packages (asks for your password)"
sudo bash "$HERE/install-system.sh"

if ! id -nG | grep -qw input; then
    bold "Almost there: log out and back in"
    echo "You were just added to the 'input' group (needed to type dictated text)."
    echo "Log out of the desktop and back in - on some systems a reboot is needed - then run"
    echo "    $HERE/install.sh"
    echo "again to finish. It will skip what's already done."
    exit 0
fi

bold "Step 2 of 3: dictation and live captions"
bash "$HERE/install-user.sh" "${user_args[@]}"

bold "Step 3 of 3: speaker-labelled transcripts (optional)"
if [ "$speakers" = ask ]; then
    echo "After each captions session this can write a second transcript that says who spoke:"
    echo "    [14:02:25] Speaker 2: Sure, so about the files..."
    echo "It runs offline in a no-network sandbox. It needs about 1.5 GB more disk and, once,"
    echo "a free Hugging Face account to download the model (INSTALL.md walks you through it)."
    ask "Set up speaker-labelled transcripts?" && speakers=yes || speakers=no
fi
if [ "$speakers" = yes ]; then
    if ! ls "$SPEAKER_CACHE"/snapshots/*/config.yaml >/dev/null 2>&1; then
        echo
        echo "The speaker model needs a one-time download with your Hugging Face account:"
        echo "  1. Sign in at https://huggingface.co (create a free account if needed)."
        echo "  2. Open https://huggingface.co/$PYANNOTE_MODEL , fill in the two"
        echo "     required fields (Company/university, Use case) and click 'Agree and access repository'."
        echo "  3. At https://huggingface.co/settings/tokens create a token of type 'Read' and copy it."
        echo "  4. Paste it below (it won't show as you paste). Answer 'n' if asked about git credentials."
        echo
        read -r -p "Press Enter when steps 1-3 are done... " _
        "$DEST/venv/bin/hf" auth login
        logged_in=yes
    fi
    if bash "$HERE/install-speakers.sh"; then
        if [ "${logged_in:-no}" = yes ]; then
            "$DEST/venv/bin/hf" auth logout >/dev/null 2>&1 || true
            echo "Logged this computer out of Hugging Face again - the token is no longer stored here."
            echo "(You can also delete the token at https://huggingface.co/settings/tokens.)"
        fi
    else
        echo "Speaker labels weren't set up - dictation and captions work without them."
        echo "Fix the problem shown above, then run: $HERE/install-speakers.sh"
    fi
else
    echo "Skipped. To add it later: $HERE/install-speakers.sh (see INSTALL.md)"
fi

bold "All done"
echo "  Win+H        start/stop dictation into the focused text field (any key also stops it)"
echo "  Meta+Shift+H start/stop live captions (or 'Live Captions (Hearside)' in the app menu)"
echo "  Transcripts  ~/Transcripts/"
echo "  Uninstall    $HERE/uninstall.sh"
