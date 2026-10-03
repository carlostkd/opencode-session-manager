#!/bin/bash

DB="$HOME/.local/share/opencode/opencode.db"
LIST_FILE="$HOME/.clean-sessions.tmp"

command -v dialog >/dev/null 2>&1 || { echo "dialog not installed"; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not found"; exit 1; }
[ -f "$DB" ] || { echo "Database not found: $DB"; exit 1; }

sqlite3 -separator '|' "$DB" "SELECT id, title, datetime(time_updated/1000,'unixepoch') FROM session ORDER BY time_updated DESC;" > "$LIST_FILE"

[ -s "$LIST_FILE" ] || { rm -f "$LIST_FILE"; echo "No sessions found"; exit 0; }

IDS=()
TAGS=()
n=0
while IFS='|' read -r SID TITLE SDATE; do
    n=$((n+1))
    IDS+=("$SID")
    TAGS+=("$n" "[$TITLE] $SDATE" "off")
done < "$LIST_FILE"
rm -f "$LIST_FILE"

dialog --backtitle "OpenCode Session Cleanup" \
       --title "Select sessions to DELETE" \
       --checklist "Space = toggle, Enter = confirm" 0 100 0 \
       "${TAGS[@]}" 2>/tmp/.clean-choice.tmp

STATUS=$?
clear
[ $STATUS -ne 0 ] && { rm -f /tmp/.clean-choice.tmp; echo "Cancelled"; exit 0; }

SELECTED=$(cat /tmp/.clean-choice.tmp)
rm -f /tmp/.clean-choice.tmp
[ -z "$SELECTED" ] && { echo "Nothing selected"; exit 0; }

echo "Sessions to delete:"
for num in $SELECTED; do
    idx=$((num-1))
    echo "  ${IDS[$idx]}"
done

read -rp "Delete these sessions? Type YES to confirm: " CONFIRM
until [ "$CONFIRM" = "YES" ]; do
    read -rp "Must be uppercase YES to proceed (or type Q to abort): " CONFIRM
    [ "$CONFIRM" = "Q" ] && { echo "Aborted"; exit 0; }
done
LEFT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM session;")
echo "Done. $LEFT sessions remaining."
