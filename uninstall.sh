#!/bin/bash
# Hearside - uninstaller for the shared install (1.1.0 or newer). Run:   sudo ./uninstall.sh
# Removes /opt/hearside (programs, Python environments, models), the services, menu entries,
# icons, ydotool and the /dev/uinput rule. Every user's transcripts in ~/Transcripts are KEPT.
# Small per-user leftovers (logs in ~/.local/share/hearside, the two KWin window rules and the
# shortcut entries in System Settings) are listed at the end; they do nothing without Hearside.
# (An older per-user install is removed with remove-per-user-install.sh instead.)
set -uo pipefail

PREFIX=/opt/hearside
ask() { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }

[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo $0" >&2; exit 1; }
echo "This removes Hearside for every user of this computer. Transcripts in ~/Transcripts are kept."
ask "Continue?" || exit 0

echo "== Stopping it for everyone logged in =="
pkill -f "$PREFIX/dictate.py" 2>/dev/null || true
pkill -f "$PREFIX/speakers.sh" 2>/dev/null || true
for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
    systemctl --user -M "$(id -nu "$uid")@" stop hearside-hotkey.service hearside-ydotoold.service 2>/dev/null || true
done
systemctl --global disable hearside-hotkey.service hearside-ydotoold.service 2>/dev/null || true
rm -f /usr/lib/systemd/user/hearside-hotkey.service /usr/lib/systemd/user/hearside-ydotoold.service

echo "== Files =="
rm -rf "$PREFIX"
rm -f /usr/share/applications/hearside-captions.desktop /usr/share/applications/hearside-dictation.desktop \
      /usr/share/icons/hicolor/scalable/apps/dictation-idle.svg /usr/share/icons/hicolor/scalable/apps/dictation-listening.svg
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true

echo
echo "ydotool (/usr/local/bin) and the /dev/uinput rule may be used by an older per-user install too."
if ask "Remove them?"; then
    rm -f /usr/local/bin/ydotool /usr/local/bin/ydotoold /etc/udev/rules.d/99-uinput.rules
    udevadm control --reload-rules 2>/dev/null || true
fi
members="$(getent group input | cut -d: -f4)"
if [ -n "$members" ] && ask "Remove these accounts from the 'input' group ($members)? (only if nothing else needs it)"; then
    for u in ${members//,/ }; do gpasswd -d "$u" input >/dev/null && echo "  $u removed"; done
fi

echo
echo "Hearside removed. Per-user leftovers that do nothing on their own (each user may delete them):"
echo "  ~/.local/share/hearside (logs), the 'Hearside' rules in System Settings > Window Rules,"
echo "  and 'Voice Dictation' in System Settings > Shortcuts. Transcripts stay in ~/Transcripts."
