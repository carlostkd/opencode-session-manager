#!/bin/bash

DB="${1:-$HOME/.local/share/opencode/opencode.db}"
TMP_FILE="$HOME/.sessions-list.tmp"

# Check dependencies
command -v sqlite3 >/dev/null 2>&1 || { echo "Error: sqlite3 not found"; exit 1; }
[ -f "$DB" ] || { echo "Error: Database not found at $DB"; exit 1; }

# Check if OpenCode is running (safer check)
if pgrep -u "$USER" -x opencode >/dev/null 2>&1; then
    echo "Error: OpenCode is currently running. Please close it first."
    exit 1
fi

# Fetch data
sqlite3 -separator '|' "$DB" "SELECT id, title, IFNULL(directory,''), datetime(time_updated/1000,'unixepoch') FROM session ORDER BY time_updated DESC;" > "$TMP_FILE"

TOTAL=$(wc -l < "$TMP_FILE")
[ "$TOTAL" -eq 0 ] && { rm -f "$TMP_FILE"; echo "No sessions found."; exit 0; }

IDS=()
TITLES=()
DIRS=()
DATES=()

while IFS='|' read -r SID TITLE SDIR SDATE; do
    IDS+=("$SID")
    TITLES+=("$TITLE")
    DIRS+=("$SDIR")
    DATES+=("$SDATE")
done < "$TMP_FILE"

rm -f "$TMP_FILE"

TO_DELETE=()

# Function for Dialog Mode
run_dialog_mode() {
    TAGS=()
    for ((i=0; i<TOTAL; i++)); do
        # Combine Title and Path for visibility
        LABEL="${TITLES[$i]} | ${DIRS[$i]}"
        TAGS+=("$((i+1))" "$LABEL" "off")
    done
    
    CHOICE_TMP="$HOME/.clean-choice.tmp"
    
    dialog --backtitle "OpenCode Session Cleanup" \
           --title "Select sessions to DELETE" \
           --checklist "Space = toggle, Enter = confirm" 0 120 0 \
           "${TAGS[@]}" 2>"$CHOICE_TMP"
           
    STATUS=$?
    clear
    
    [ $STATUS -ne 0 ] && { rm -f "$CHOICE_TMP"; echo "Cancelled."; exit 0; }
    
    PICK=$(cat "$CHOICE_TMP")
    rm -f "$CHOICE_TMP"
    
    [ -z "$PICK" ] && { echo "Nothing selected."; exit 0; }
    
    for num in $PICK; do
        TO_DELETE+=($((num-1)))
    done
}

# Function for Plain Text Mode
run_plain_mode() {
    echo "=============================================="
    echo "  OpenCode Session Cleanup"
    echo "=============================================="
    echo ""
    for ((i=0; i<TOTAL; i++)); do
        printf "%3d) %s\n     %s\n     %s\n\n" $((i+1)) "${TITLES[$i]}" "${DIRS[$i]}" "${DATES[$i]}"
    done
    echo "=============================================="
    echo "  Select: single number, comma list (1,3,5),"
    echo "  range (2-6), or mixed (1,3-5,8)"
    echo "  q = quit, a = all"
    echo "=============================================="
    
    read -rp "Delete which sessions: " PICK
    [ "$PICK" == "q" ] && { echo "Aborted."; exit 0; }
    
    if [ "$PICK" == "a" ]; then
        for ((i=0; i<TOTAL; i++)); do
            TO_DELETE+=($i)
        done
    else
        IFS=',' read -ra ITEMS <<< "$PICK"
        for item in "${ITEMS[@]}"; do
            if [[ "$item" == *-* ]]; then
                START="${item%-*}"
                END="${item#*-}"
                if [[ "$START" =~ ^[0-9]+$ ]] && [[ "$END" =~ ^[0-9]+$ ]] && [ "$START" -ge 1 ] && [ "$END" -le "$TOTAL" ] && [ "$START" -le "$END" ]; then
                    for ((n=START; n<=END; n++)); do
                        TO_DELETE+=($((n-1)))
                    done
                else
                    echo "Invalid range: $item"; exit 1
                fi
            elif [[ "$item" =~ ^[0-9]+$ ]] && [ "$item" -ge 1 ] && [ "$item" -le "$TOTAL" ]; then
                TO_DELETE+=($((item-1)))
            else
                echo "Invalid selection: $item"; exit 1
            fi
        done
    fi
}

# Decide Mode
HAS_DIALOG=false
if command -v dialog >/dev/null 2>&1; then
    HAS_DIALOG=true
fi

if [ "$HAS_DIALOG" = true ]; then
    run_dialog_mode
else
    run_plain_mode
fi

# Validation
[ ${#TO_DELETE[@]} -eq 0 ] && { echo "Nothing selected."; exit 0; }

# Sort and Dedupe
TO_DELETE=($(printf '%s\n' "${TO_DELETE[@]}" | sort -un))

# Summary
echo ""
echo "Sessions to DELETE:"
for idx in "${TO_DELETE[@]}"; do
    echo "  ID: ${IDS[$idx]}"
    echo "  Title: ${TITLES[$idx]}"
    echo "  Path: ${DIRS[$idx]}"
    echo ""
done

# Confirmation
read -rp "Type YES to confirm: " CONFIRM
until [ "$CONFIRM" = "YES" ]; do
    read -rp "Must be uppercase YES to proceed (or Q to abort): " CONFIRM
    [ "$CONFIRM" = "Q" ] && { echo "Aborted."; exit 0; }
done

# Execution
for idx in "${TO_DELETE[@]}"; do
    SID="${IDS[$idx]}"
    sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM part WHERE session_id='$SID'; DELETE FROM message WHERE session_id='$SID'; DELETE FROM session WHERE id='$SID';"
    echo "Deleted: ${TITLES[$idx]}"
done

LEFT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM session;")
echo ""
echo "Done. $LEFT sessions remaining."
