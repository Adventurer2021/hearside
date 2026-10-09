#!/bin/bash
# Hearside, part 1 (needs root): system packages, ydotool,
# /dev/uinput access, and the floating-bar library. Supports apt (Debian/
# Ubuntu) and dnf (AlmaLinux/RHEL/Fedora). Run as:  sudo bash install-system.sh
# Then log out and back in if told to, and run install-user.sh as your normal user.
set -euo pipefail

YDOTOOL_URL="https://github.com/ReimuNotMoe/ydotool/releases/download/v1.0.4"
YDOTOOL_SHA256="daa83507a596d6839b7467540382dbdc6e4bf64ebfa4f7d6416e877d9a522c0c"
YDOTOOLD_SHA256="3f14f96308935214c0fb154507360f7632e7deda1935dc2d538259fd9986ed36"
# Same checksum as Debian's gtk4-layer-shell_1.0.4.orig.tar.gz.
LAYER_SHELL_URL="https://github.com/wmww/gtk4-layer-shell/archive/refs/tags/v1.0.4.tar.gz"
LAYER_SHELL_SHA256="7fe327dc3740e4b6f5edfd855e23f84b1ac1ec6854b731047b95df7feb46498b"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with: sudo bash $0" >&2
    exit 1
fi
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Run this via sudo from the account that will use the tools (so it knows which user to set up)." >&2
    exit 1
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
chmod 755 "$tmp"
trap 'rm -rf "$tmp"' EXIT

echo "== Setting up Hearside for '$TARGET_USER' on $(. /etc/os-release && echo "$PRETTY_NAME") =="

# The floating bar needs a Wayland session (layer-shell); on X11-only machines skip it.
if compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null; then
    layer_shell=build
else
    layer_shell=skip
fi

if command -v apt-get >/dev/null; then
    apt-get update
    pkgs=(python3-venv python3-pip python3-dev gcc linux-libc-dev pulseaudio-utils libnotify-bin curl python3-gi pipewire-bin libspa-0.2-modules bubblewrap)
    if [ "$layer_shell" = skip ]; then
        :
    elif apt-cache show gir1.2-gtk4layershell-1.0 >/dev/null 2>&1; then
        pkgs+=(gir1.2-gtk-4.0 gir1.2-gtk4layershell-1.0 libgtk4-layer-shell0)
        layer_shell=packaged
    else
        pkgs+=(gir1.2-gtk-4.0 meson ninja-build libgtk-4-dev libwayland-dev wayland-protocols libgirepository1.0-dev)
    fi
    apt-get install "${pkgs[@]}"
elif command -v dnf >/dev/null; then
    pkgs=(python3-devel python3-pip gcc kernel-headers pulseaudio-utils libnotify curl python3-gobject gtk4 pipewire pipewire-libs bubblewrap)
    repo_args=()
    if [ "$layer_shell" = skip ]; then
        :
    elif dnf -q repoquery --latest-limit 1 gtk4-layer-shell 2>/dev/null | grep -q .; then
        pkgs+=(gtk4-layer-shell)
        layer_shell=packaged
    else
        pkgs+=(meson ninja-build gtk4-devel wayland-devel wayland-protocols-devel gobject-introspection-devel)
        # meson/ninja live in CRB on RHEL-family systems.
        if dnf repolist --all 2>/dev/null | grep -q "^crb "; then
            repo_args=(--enablerepo=crb)
        fi
    fi
    dnf install "${repo_args[@]}" "${pkgs[@]}"
else
    echo "Neither apt-get nor dnf found - unsupported distro." >&2
    exit 1
fi

echo "== Installing ydotool v1.0.4 (checksum-verified) =="
curl -fsSL -o "$tmp/ydotool" "$YDOTOOL_URL/ydotool-release-ubuntu-latest"
curl -fsSL -o "$tmp/ydotoold" "$YDOTOOL_URL/ydotoold-release-ubuntu-latest"
echo "$YDOTOOL_SHA256  $tmp/ydotool" | sha256sum -c -
echo "$YDOTOOLD_SHA256  $tmp/ydotoold" | sha256sum -c -
install -m 755 "$tmp/ydotool" /usr/local/bin/ydotool
install -m 755 "$tmp/ydotoold" /usr/local/bin/ydotoold
command -v restorecon >/dev/null && restorecon /usr/local/bin/ydotool /usr/local/bin/ydotoold

if [ "$layer_shell" = build ]; then
    echo "== Building gtk4-layer-shell 1.0.4 from source (checksum-verified) into /usr/local =="
    curl -fsSL -o "$tmp/gls.tar.gz" "$LAYER_SHELL_URL"
    echo "$LAYER_SHELL_SHA256  $tmp/gls.tar.gz" | sha256sum -c -
    chown -R "$TARGET_USER" "$tmp"
    # Configure and compile as the normal user; only the final install runs as root.
    sudo -u "$TARGET_USER" bash -c "cd '$tmp' && tar xzf gls.tar.gz && cd gtk4-layer-shell-1.0.4 \
        && meson setup build --prefix=/usr/local -Dintrospection=true -Dvapi=false \
           -Dexamples=false -Dtests=false -Dsmoke-tests=false -Ddocs=false \
        && ninja -C build"
    ninja -C "$tmp/gtk4-layer-shell-1.0.4/build" install
    ldconfig
    command -v restorecon >/dev/null && restorecon -R /usr/local/lib64 /usr/local/lib 2>/dev/null || true
fi

echo "== Allowing the input group to use /dev/uinput (needed to type text) =="
install -m 644 "$HERE/files/99-uinput.rules" /etc/udev/rules.d/99-uinput.rules
udevadm control --reload-rules
udevadm trigger --name-match=uinput || true

if id -nG "$TARGET_USER" | grep -qw input; then
    echo "'$TARGET_USER' is already in the input group."
    relogin=no
else
    usermod -aG input "$TARGET_USER"
    echo "Added '$TARGET_USER' to the input group."
    relogin=yes
fi

echo
echo "== Done =="
ls -l /usr/local/bin/ydotool /usr/local/bin/ydotoold /dev/uinput
if [ "$layer_shell" = skip ]; then
    echo "NOTE: no Wayland session installed - floating bar skipped; the tray icon shows dictation status."
else
    sudo -u "$TARGET_USER" /usr/bin/python3 "$HERE/files/indicator.py" --check 2>/dev/null \
        || echo "NOTE: floating-bar check failed - dictation will still work, with the tray icon only."
fi
if [ "$relogin" = yes ]; then
    echo "NEXT: log out and back in (group change), then run:  bash $HERE/install-user.sh"
else
    echo "NEXT: run as your normal user:  bash $HERE/install-user.sh"
fi
