#!/bin/bash

OLD_DB="your_old_db_path_opencode.db"
NEW_DB="/your_new_db_path/.local/share/opencode/opencode.db"
LIST_FILE="$HOME/.session-list.tmp"

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not found"; exit 1; }
[ -f "$OLD_DB" ] || { echo "Old database not found: $OLD_DB"; exit 1; }
[ -f "$NEW_DB" ] || { echo "New database not found: $NEW_DB"; exit 1; }

sqlite3 -separator "|" "$OLD_DB" "SELECT id, title, IFNULL(directory,''), datetime(time_updated/1000,'unixepoch') FROM session ORDER BY time_updated 
DESC;" > "$LIST_FILE"

TOTAL=$(wc -l < "$LIST_FILE")
[ "$TOTAL" -eq 0 ] && { rm -f "$LIST_FILE"; echo "No sessions found in old database"; exit 1; }

echo "=============================================="
echo "  OpenCode Session Exporter"
echo "=============================================="
echo ""

n=0
while IFS='|' read -r SID TITLE SDIR SDATE; do
    n=$((n+1))
    printf "%3d) %s\n     %s\n     %s\n\n" "$n" "$TITLE" "$SDATE" "$SDIR"
done < "$LIST_FILE"

echo "=============================================="

read -rp "Enter session number to export (q to quit): " CHOICE
rm -f "$LIST_FILE"

[[ "$CHOICE" == "q" ]] && { echo "Aborted"; exit 0; }

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$TOTAL" ]; then
    echo "Invalid selection: $CHOICE"
    exit 1
fi

SELECTED=$(sed -n "${CHOICE}p" "$HOME/.session-list.tmp")
IFS='|' read -r SID TITLE SDIR SDATE <<< "$(sqlite3 -separator "|" "$OLD_DB" "SELECT id, title, IFNULL(directory,''), 
datetime(time_updated/1000,'unixepoch') FROM session ORDER BY time_updated DESC LIMIT 1 OFFSET $((CHOICE-1));")"

echo ""
echo "Selected: $TITLE"
echo "Session: $SID"
echo ""

CHECK=$(sqlite3 "$NEW_DB" "SELECT COUNT(*) FROM session WHERE id='$SID';")
if [ "$CHECK" -gt 0 ]; then
    read -rp "Session already exists in new DB. Re-run anyway? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo "Aborted"; exit 0; }
fi

read -rp "Proceed with export? (y/N): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo "Aborted"; exit 0; }

sqlite3 "$NEW_DB" "ATTACH '$OLD_DB' AS old; PRAGMA foreign_keys=OFF; BEGIN; INSERT OR IGNORE INTO project SELECT * FROM old.project WHERE id IN 
(SELECT project_id FROM old.session WHERE id='$SID'); INSERT OR IGNORE INTO workspace SELECT * FROM old.workspace WHERE id IN (SELECT workspace_id 
FROM old.session WHERE id='$SID'); INSERT OR IGNORE INTO session SELECT * FROM old.session WHERE id='$SID'; INSERT OR IGNORE INTO message SELECT * 
FROM old.message WHERE session_id='$SID'; INSERT OR IGNORE INTO part SELECT * FROM old.part WHERE session_id='$SID'; COMMIT; DETACH old; PRAGMA 
foreign_keys=ON;"

RESULT=$(sqlite3 "$NEW_DB" "SELECT COUNT(*) FROM session WHERE id='$SID';")
if [ "$RESULT" -gt 0 ]; then
    MSGS=$(sqlite3 "$NEW_DB" "SELECT COUNT(*) FROM message WHERE session_id='$SID';")
    echo ""
    echo "Export OK: $MSGS messages copied"
    if [ -n "$SDIR" ]; then
        echo ""
        echo "To view it, run:"
        echo "  cd $SDIR && opencode"
    fi
else
    echo ""
    echo "Export FAILED"
    exit 1
fi
