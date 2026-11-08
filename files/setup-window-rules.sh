#!/bin/bash
# KWin window rules for HearSide's two windows, for the user running it:
#   - live captions (hearside-captions): kept above, never focused, remembers position and size
#   - dictation bar (hearside-bar): kept above, never focused, not in the task bar or switcher,
#     remembers where it was dragged
# "Never focused" is what lets you click their buttons while the cursor stays in the app you
# are typing or dictating into. Other rules in kwinrulesrc are left alone.
# Run by the HearSide hotkey service at every login; it only writes when a rule is missing or
# older than this script (RULES_VERSION), so it is cheap and makes no backups otherwise.
# Normal user, no sudo. Safe to re-run.
set -euo pipefail

RULES_VERSION=2
RC="kwinrulesrc"
FILE="$HOME/.config/$RC"
CAPTIONS_RULE="8c1e5b7a-2f94-4d3e-a6b1-0e9c7d42f5a3"   # fixed IDs, so re-runs update rather than duplicate
BAR_RULE="3f6d2c9e-71b4-4a8e-9d05-b2e4c8a17f60"

if command -v kwriteconfig6 >/dev/null; then W=kwriteconfig6; R=kreadconfig6
elif command -v kwriteconfig5 >/dev/null; then W=kwriteconfig5; R=kreadconfig5
else echo "kwriteconfig not found - skipping window rules (windows still work, just not pinned above)" >&2; exit 0
fi

current() { "$R" --file "$RC" --group "$1" --key hearsideRulesVersion 2>/dev/null || true; }
if [ "${1:-}" != "--force" ] && [ "$(current "$CAPTIONS_RULE")" = "$RULES_VERSION" ] \
        && [ "$(current "$BAR_RULE")" = "$RULES_VERSION" ]; then
    exit 0
fi

[ -f "$FILE" ] && cp -p "$FILE" "$FILE.bak-$(date +%Y%m%d-%H%M%S)"

rule() {  # rule <id> <description> <app id> <remember size: yes/no> <skip task bar: yes/no>
    local id=$1
    w() { "$W" --file "$RC" --group "$id" --key "$1" "$2"; }
    w Description "$2"
    w wmclass "$3"
    w wmclassmatch 1          # exact match
    w wmclasscomplete false
    w above true;        w aboverule 2          # 2 = Force
    w acceptfocus false; w acceptfocusrule 2
    w skipswitcher true; w skipswitcherrule 2
    w skippager true;    w skippagerrule 2
    w positionrule 4                             # 4 = Remember
    if [ "$4" = yes ]; then w sizerule 4; fi
    if [ "$5" = yes ]; then w skiptaskbar true; w skiptaskbarrule 2; fi
    w hearsideRulesVersion "$RULES_VERSION"
}
rule "$CAPTIONS_RULE" "Live Captions (HearSide)" hearside-captions yes no
rule "$BAR_RULE" "Dictation bar (HearSide)" hearside-bar no yes

rules="$("$R" --file "$RC" --group General --key rules)"
for id in "$CAPTIONS_RULE" "$BAR_RULE"; do
    case ",$rules," in
        *",$id,"*) ;;
        *) rules="${rules:+$rules,}$id" ;;
    esac
done
"$W" --file "$RC" --group General --key rules "$rules"
count=$(tr ',' '\n' <<<"$rules" | grep -c .)
"$W" --file "$RC" --group General --key count "$count"

if command -v qdbus6 >/dev/null; then qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
elif command -v qdbus >/dev/null; then qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
else dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
fi
echo "KWin rules for the HearSide windows are in place ($count rule(s) total in $RC)"
