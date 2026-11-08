#!/bin/bash
# HearSide, part 1 (root): system packages, ydotool, /dev/uinput access, and the
# "input" group for every account that will use HearSide. Supports apt (Debian/Ubuntu)
# and dnf (AlmaLinux/RHEL/Fedora). Normally run by install.sh; on its own:
#     sudo bash install-system.sh [--yes] [user ...]   (default: every regular account)
#     bash install-system.sh --list-missing             (no sudo; lists what would be installed)
# It lists the system packages that are missing and asks before installing them
# (--yes answers yes); packages already installed are left alone.
set -euo pipefail

YDOTOOL_URL="https://github.com/ReimuNotMoe/ydotool/releases/download/v1.0.4"
YDOTOOL_SHA256="daa83507a596d6839b7467540382dbdc6e4bf64ebfa4f7d6416e877d9a522c0c"
YDOTOOLD_SHA256="3f14f96308935214c0fb154507360f7632e7deda1935dc2d538259fd9986ed36"

APT_PACKAGES=(python3-venv python3-pip python3-dev gcc linux-libc-dev pulseaudio-utils libnotify-bin
    curl pipewire-bin libspa-0.2-modules bubblewrap libxcb-cursor0)
DNF_PACKAGES=(python3-devel python3-pip gcc kernel-headers pulseaudio-utils libnotify curl pipewire
    pipewire-libs bubblewrap xcb-util-cursor)

if command -v apt-get >/dev/null; then manager=apt; packages=("${APT_PACKAGES[@]}")
elif command -v dnf >/dev/null; then manager=dnf; packages=("${DNF_PACKAGES[@]}")
else manager=none; packages=()
fi

# System packages from the list above that aren't installed yet (one per line).
missing_packages() {
    local p
    for p in "${packages[@]}"; do
        case "$manager" in
            apt) dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || echo "$p" ;;
            dnf) rpm -q --whatprovides "$p" >/dev/null 2>&1 || echo "$p" ;;
        esac
    done
}

# True when /usr/local/bin has the checksum-verified ydotool 1.0.4 already.
ydotool_ok() {
    echo "$YDOTOOL_SHA256  /usr/local/bin/ydotool" | sha256sum -c --status - 2>/dev/null &&
        echo "$YDOTOOLD_SHA256  /usr/local/bin/ydotoold" | sha256sum -c --status - 2>/dev/null
}

assume_yes=no
list_only=no
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) assume_yes=yes ;;
        --list-missing) list_only=yes ;;
        *) break ;;
    esac
    shift
done

if [ "$manager" = none ]; then
    echo "Neither apt-get nor dnf found - unsupported distro." >&2
    exit 1
fi
mapfile -t missing < <(missing_packages)

if [ "$list_only" = yes ]; then
    if [ ${#missing[@]} -eq 0 ]; then
        echo "All the system packages HearSide needs are already installed."
    else
        echo "The installer will add these system packages (${#missing[@]}):"
        echo "  ${missing[*]}"
    fi
    if ydotool_ok; then echo "ydotool 1.0.4 (types the dictated text) is already in /usr/local/bin."
    else echo "It will also download ydotool 1.0.4 (types the dictated text) into /usr/local/bin."
    fi
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with: sudo bash $0" >&2
    exit 1
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
chmod 755 "$tmp"
trap 'rm -rf "$tmp"' EXIT

# Regular login accounts: UID 1000-59999, a real shell, a home folder that exists.
regular_users() {
    getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1 ":" $6}' \
        | while IFS=: read -r name home; do [ -d "$home" ] && echo "$name"; done
}
if [ $# -gt 0 ]; then users=("$@"); else mapfile -t users < <(regular_users); fi
[ ${#users[@]} -gt 0 ] || { echo "No user accounts found to set up." >&2; exit 1; }
for u in "${users[@]}"; do id "$u" >/dev/null 2>&1 || { echo "No such user: $u" >&2; exit 1; }; done

echo "== System packages on $(. /etc/os-release && echo "$PRETTY_NAME") =="
if [ ${#missing[@]} -eq 0 ]; then
    echo "All needed system packages are already installed."
else
    echo "HearSide needs these system packages, which aren't installed yet:"
    echo "  ${missing[*]}"
    if [ "$assume_yes" != yes ]; then
        read -r -p "Install them now? [Y/n] " reply
        if [[ "$reply" =~ ^[Nn] ]]; then
            echo "Nothing was installed. HearSide can't run without them; install them yourself" >&2
            echo "or run the installer again and answer yes." >&2
            exit 1
        fi
    fi
    case "$manager" in
        apt) apt-get update && apt-get install -y "${missing[@]}" ;;
        dnf) dnf install -y "${missing[@]}" ;;
    esac
fi

echo "== ydotool v1.0.4 (types the dictated text; checksum-verified) =="
if ydotool_ok; then
    echo "Already installed."
else
curl -fsSL -o "$tmp/ydotool" "$YDOTOOL_URL/ydotool-release-ubuntu-latest"
curl -fsSL -o "$tmp/ydotoold" "$YDOTOOL_URL/ydotoold-release-ubuntu-latest"
echo "$YDOTOOL_SHA256  $tmp/ydotool" | sha256sum -c -
echo "$YDOTOOLD_SHA256  $tmp/ydotoold" | sha256sum -c -
install -m 755 "$tmp/ydotool" /usr/local/bin/ydotool
install -m 755 "$tmp/ydotoold" /usr/local/bin/ydotoold
if command -v restorecon >/dev/null; then restorecon /usr/local/bin/ydotool /usr/local/bin/ydotoold; fi
fi

echo "== Allowing the input group to use /dev/uinput (needed to type text) =="
install -m 644 "$HERE/files/99-uinput.rules" /etc/udev/rules.d/99-uinput.rules
udevadm control --reload-rules
udevadm trigger --name-match=uinput || true

echo "== Accounts that can use HearSide (added to the 'input' group) =="
# The input group lets an account type through /dev/uinput and see key presses (dictation stops
# when you type). Only accounts listed here get it.
for u in "${users[@]}"; do
    if id -nG "$u" | grep -qw input; then
        echo "  $u: already set up"
    else
        usermod -aG input "$u"
        echo "  $u: added (takes effect at their next login)"
    fi
done
ls -l /usr/local/bin/ydotool /usr/local/bin/ydotoold /dev/uinput
