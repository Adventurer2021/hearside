#!/bin/bash
# Adds (or refreshes) a KWin window rule for the live-caption window: keep it
# above other windows, never give it keyboard focus (typing always reaches the
# app being worked in), keep it out of the task switcher, and remember where
# it was moved and how big it was made. Other rules in kwinrulesrc are left
# alone. Safe to re-run. Normal user, no sudo.
set -euo pipefail

RULE_ID="8c1e5b7a-2f94-4d3e-a6b1-0e9c7d42f5a3"   # fixed, so re-runs update rather than duplicate
APP_ID="hearside-captions"
RC="kwinrulesrc"
FILE="$HOME/.config/$RC"

if command -v kwriteconfig6 >/dev/null; then W=kwriteconfig6; R=kreadconfig6
elif command -v kwriteconfig5 >/dev/null; then W=kwriteconfig5; R=kreadconfig5
else echo "kwriteconfig not found - skipping the caption window rule (window still works, just not pinned above)" >&2; exit 0
fi

[ -f "$FILE" ] && cp -p "$FILE" "$FILE.bak-$(date +%Y%m%d-%H%M%S)"

w() { "$W" --file "$RC" --group "$RULE_ID" --key "$1" "$2"; }
w Description "Live Captions (Hearside)"
w wmclass "$APP_ID"
w wmclassmatch 1          # exact match
w wmclasscomplete false
w above true;        w aboverule 2          # 2 = Force
w acceptfocus false; w acceptfocusrule 2
w skipswitcher true; w skipswitcherrule 2
w skippager true;    w skippagerrule 2
w positionrule 4                             # 4 = Remember
w sizerule 4

rules="$("$R" --file "$RC" --group General --key rules)"
case ",$rules," in
    *",$RULE_ID,"*) ;;
    *) rules="${rules:+$rules,}$RULE_ID" ;;
esac
"$W" --file "$RC" --group General --key rules "$rules"
count=$(tr ',' '\n' <<<"$rules" | grep -c .)
"$W" --file "$RC" --group General --key count "$count"

if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
elif command -v qdbus >/dev/null; then qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
else dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
fi
echo "KWin rule for the caption window is in place ($count rule(s) total in $RC)"
