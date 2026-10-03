#!/bin/bash

DB="${1:-$HOME/.local/share/opencode/opencode.db}"
TMP_FILE="$HOME/.opencode-sessions.tmp"
CHOICE_TMP="$HOME/.opencode-choice.tmp"

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not found"; exit 1; }
[ -f "$DB" ] || { echo "Database not found: $DB"; exit 1; }

pgrep -u "$USER" opencode >/dev/null 2>&1 && { echo "Close OpenCode first"; exit 1; }

detect_schema() {
    if sqlite3 "$1" ".tables" 2>/dev/null | grep -qw "session_v2"; then
        echo "v2"
    elif sqlite3 "$1" ".tables" 2>/dev/null | grep -qw "session"; then
        echo "v1"
    else
        echo ""
    fi
}

session_table() {
    [ "$1" == "v2" ] && echo "session_v2" || echo "session"
}

msg_table() {
    [ "$1" == "v2" ] && echo "session_message" || echo "message"
}

list_sessions() {
    local dbfile="$1" schema="$2"
    if [ "$schema" == "v2" ]; then
        sqlite3 -separator '|' "$dbfile" "SELECT id, IFNULL(title,'(untitled)'), IFNULL(directory,'') FROM session_v2 ORDER BY time_updated DESC;"
    else
        sqlite3 -separator '|' "$dbfile" "SELECT id, title, IFNULL(directory,'') FROM session ORDER BY time_updated DESC;"
    fi
}

load_sessions() {
    local dbfile="$1" schema="$2"
    L_IDS=()
    L_TITLES=()
    L_DIRS=()
    list_sessions "$dbfile" "$schema" > "$TMP_FILE"
    while IFS='|' read -r sid stitle sdir; do
        L_IDS+=("$sid")
        L_TITLES+=("$stitle")
        L_DIRS+=("$sdir")
    done < "$TMP_FILE"
    rm -f "$TMP_FILE"
}

expand_path() {
    eval "echo $1"
}

delete_session_sql() {
    local sid="$1"
    if [ "$SCHEMA" == "v2" ]; then
        sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM session_message WHERE session_id='$sid'; DELETE FROM session_v2 WHERE id='$sid';"
    else
        sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM part WHERE session_id='$sid'; DELETE FROM message WHERE session_id='$sid'; DELETE FROM session WHERE id='$sid';"
    fi
}

SCHEMA=$(detect_schema "$DB")
[ -z "$SCHEMA" ] && { echo "Unsupported database schema"; exit 1; }

TO_DELETE=()
OP=""
PICKED_SID=""

show_menu() {
    if command -v dialog >/dev/null 2>&1; then
        dialog --backtitle "OpenCode Session Manager ($SCHEMA)" \
               --title "Main Menu" \
               --menu "Select Operation" 0 0 0 \
               "1" "Cleanup/Delete Sessions" \
               "2" "Import session from old DB" \
               "3" "Backup session to file" 2>"$CHOICE_TMP"
        STATUS=$?
        clear
        [ $STATUS -ne 0 ] && { rm -f "$CHOICE_TMP"; exit 0; }
        OP=$(cat "$CHOICE_TMP")
        rm -f "$CHOICE_TMP"
    else
        echo "=============================================="
        echo "  OpenCode Session Manager ($SCHEMA)"
        echo "=============================================="
        echo "  1) Cleanup/Delete Sessions"
        echo "  2) Import session from old DB"
        echo "  3) Backup session to file"
        echo "  q) Quit"
        echo "=============================================="
        read -rp "Select operation: " OP
    fi
}

pick_single_session() {
    local dbfile="$1" schema="$2" prompt="$3"
    PICKED_SID=""
    load_sessions "$dbfile" "$schema"
    local total=${#L_IDS[@]}
    [ "$total" -eq 0 ] && { echo "No sessions found"; exit 0; }
    local i
    if command -v dialog >/dev/null 2>&1; then
        TAGS=()
        for ((i=0; i<total; i++)); do
            TAGS+=("$((i+1))" "${L_TITLES[$i]} | ${L_DIRS[$i]}")
        done
        dialog --backtitle "OpenCode Session Manager ($schema)" \
               --title "$prompt" \
               --menu "Select ONE session" 0 120 0 \
               "${TAGS[@]}" 2>"$CHOICE_TMP"
        STATUS=$?
        clear
        [ $STATUS -ne 0 ] && { rm -f "$CHOICE_TMP"; exit 0; }
        local num=$(cat "$CHOICE_TMP")
        rm -f "$CHOICE_TMP"
        [ -z "$num" ] && { echo "Nothing selected"; exit 0; }
        PICKED_SID="${L_IDS[$((num-1))]}"
    else
        echo "=============================================="
        echo "  $prompt ($schema)"
        echo "=============================================="
        echo ""
        for ((i=0; i<total; i++)); do
            printf "%3d) %s\n     %s\n\n" $((i+1)) "${L_TITLES[$i]}" "${L_DIRS[$i]}"
        done
        echo "=============================================="
        read -rp "Enter session number: " NUM
        [[ "$NUM" =~ ^[0-9]+$ ]] && [ "$NUM" -ge 1 ] && [ "$NUM" -le "$total" ] || { echo "Invalid selection"; exit 1; }
        PICKED_SID="${L_IDS[$((NUM-1))]}"
    fi
}

do_cleanup() {
    load_sessions "$DB" "$SCHEMA"
    TOTAL=${#L_IDS[@]}
    [ "$TOTAL" -eq 0 ] && { echo "No sessions found"; exit 0; }
    local i
    if command -v dialog >/dev/null 2>&1; then
        TAGS=()
        for ((i=0; i<TOTAL; i++)); do
            TAGS+=("$((i+1))" "${L_TITLES[$i]} | ${L_DIRS[$i]}" "off")
        done
        dialog --backtitle "OpenCode Session Manager ($SCHEMA)" \
               --title "Select sessions to DELETE" \
               --checklist "Space = toggle, Enter = confirm" 0 120 0 \
               "${TAGS[@]}" 2>"$CHOICE_TMP"
        STATUS=$?
        clear
        [ $STATUS -ne 0 ] && { rm -f "$CHOICE_TMP"; echo "Cancelled"; exit 0; }
        local pick=$(cat "$CHOICE_TMP")
        rm -f "$CHOICE_TMP"
        [ -z "$pick" ] && { echo "Nothing selected"; exit 0; }
        for num in $pick; do
            TO_DELETE+=($((num-1)))
        done
    else
        echo "=============================================="
        echo "  Cleanup Sessions ($SCHEMA)"
        echo "=============================================="
        echo ""
        for ((i=0; i<TOTAL; i++)); do
            printf "%3d) %s\n     %s\n\n" $((i+1)) "${L_TITLES[$i]}" "${L_DIRS[$i]}"
        done
        echo "=============================================="
        echo "  3 or 1,3,5 or 2-6 or 1,3-5,8, a=all, q=quit"
        echo "=============================================="
        read -rp "Delete which sessions: " PICK
        [ "$PICK" == "q" ] && { echo "Aborted"; exit 0; }
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
    fi
    [ ${#TO_DELETE[@]} -eq 0 ] && { echo "Nothing selected"; exit 0; }
    TO_DELETE=($(printf '%s\n' "${TO_DELETE[@]}" | sort -un))
    echo ""
    echo "Sessions to DELETE:"
    for idx in "${TO_DELETE[@]}"; do
        echo "  ${L_IDS[$idx]}"
        echo "    ${L_TITLES[$idx]}"
        echo "    ${L_DIRS[$idx]}"
        echo ""
    done
    read -rp "Type YES to confirm: " CONFIRM
    until [ "$CONFIRM" = "YES" ]; do
        read -rp "Must be uppercase YES to proceed (or Q to abort): " CONFIRM
        [ "$CONFIRM" = "Q" ] && { echo "Aborted"; exit 0; }
    done
    for idx in "${TO_DELETE[@]}"; do
        delete_session_sql "${L_IDS[$idx]}"
        echo "Deleted: ${L_TITLES[$idx]}"
    done
    LEFT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $(session_table "$SCHEMA");")
    echo ""
    echo "Done. $LEFT sessions remaining."
}

do_import() {
    read -rp "Path to OLD SOURCE DB: " RAW_SRC
    SRC_DB=$(expand_path "$RAW_SRC")
    [ -z "$SRC_DB" ] && { echo "Aborted"; exit 0; }
    [ ! -f "$SRC_DB" ] && { echo "File not found: $SRC_DB"; exit 1; }
    SRC_SCHEMA=$(detect_schema "$SRC_DB")
    [ -z "$SRC_SCHEMA" ] && { echo "Unsupported source schema"; exit 1; }
    if [ "$SRC_DB" == "$DB" ]; then
        echo "Source is the same as your live DB. This does nothing useful."
        echo "The source must be an OLD or BACKUP opencode.db file."
        exit 1
    fi
    if [ "$SRC_SCHEMA" != "$SCHEMA" ]; then
        echo "Source is $SRC_SCHEMA but live DB is $SCHEMA. Cross version transplant is not supported."
        exit 1
    fi
    pick_single_session "$SRC_DB" "$SRC_SCHEMA" "Import which session"
    SID="$PICKED_SID"
    STBL=$(session_table "$SRC_SCHEMA")
    MTBL=$(msg_table "$SRC_SCHEMA")
    PART_SQL=""
    [ "$SRC_SCHEMA" == "v1" ] && PART_SQL="INSERT OR IGNORE INTO part SELECT * FROM old.part WHERE session_id='$SID';"
    sqlite3 "$DB" "ATTACH '$SRC_DB' AS old; PRAGMA foreign_keys=OFF; BEGIN; INSERT OR IGNORE INTO project SELECT * FROM old.project WHERE id IN (SELECT project_id FROM old.$STBL WHERE id='$SID'); INSERT OR IGNORE INTO workspace SELECT * FROM old.workspace WHERE id IN (SELECT workspace_id FROM old.$STBL WHERE id='$SID'); INSERT OR IGNORE INTO $STBL SELECT * FROM old.$STBL WHERE id='$SID'; INSERT OR IGNORE INTO $MTBL SELECT * FROM old.$MTBL WHERE session_id='$SID'; $PART_SQL COMMIT; DETACH old; PRAGMA foreign_keys=ON;"
    RESULT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $STBL WHERE id='$SID';")
    if [ "$RESULT" -gt 0 ]; then
        MSGS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $MTBL WHERE session_id='$SID';")
        echo "Import OK: $MSGS messages copied into $DB"
    else
        echo "Import FAILED"
        exit 1
    fi
}

do_backup() {
    pick_single_session "$DB" "$SCHEMA" "Backup which session"
    SID="$PICKED_SID"
    read -rp "Output filename for backup (e.g. ~/session-backup.db): " RAW_OUT
    OUT_DB=$(expand_path "$RAW_OUT")
    [ -z "$OUT_DB" ] && { echo "Aborted"; exit 0; }
    if [ -f "$OUT_DB" ]; then
        echo "File already exists: $OUT_DB"
        read -rp "Overwrite? Type YES to confirm: " CONFIRM
        until [ "$CONFIRM" = "YES" ]; do
            read -rp "Must be uppercase YES (or Q to abort): " CONFIRM
            [ "$CONFIRM" = "Q" ] && { echo "Aborted"; exit 0; }
        done
        rm -f "$OUT_DB"
    fi
    STBL=$(session_table "$SCHEMA")
    MTBL=$(msg_table "$SCHEMA")
    PART_SQL=""
    [ "$SCHEMA" == "v1" ] && PART_SQL="INSERT OR IGNORE INTO part SELECT * FROM old.part WHERE session_id='$SID';"
    sqlite3 "$OUT_DB" "ATTACH '$DB' AS old; PRAGMA foreign_keys=OFF; BEGIN; CREATE TABLE IF NOT EXISTS project ($(sqlite3 "$DB" ".schema project" | grep -oP '(?<=CREATE TABLE `project` \().*?(?=\);\n)' | head -1)); COMMIT; DETACH old;"
    sqlite3 "$OUT_DB" "ATTACH '$DB' AS old; PRAGMA foreign_keys=OFF; BEGIN; $(sqlite3 "$DB" ".schema project") $(sqlite3 "$DB" ".schema workspace") $(sqlite3 "$DB" ".schema $STBL" | sed "s/$(session_table "$SCHEMA")/$(session_table "$SCHEMA")/") $(sqlite3 "$DB" ".schema $MTBL") $( [ "$SCHEMA" == "v1" ] && echo "$(sqlite3 "$DB" ".schema message") $(sqlite3 "$DB" ".schema part")") INSERT OR IGNORE INTO project SELECT * FROM old.project WHERE id IN (SELECT project_id FROM old.$STBL WHERE id='$SID'); INSERT OR IGNORE INTO workspace SELECT * FROM old.workspace WHERE id IN (SELECT workspace_id FROM old.$STBL WHERE id='$SID'); INSERT OR IGNORE INTO $STBL SELECT * FROM old.$STBL WHERE id='$SID'; INSERT OR IGNORE INTO $MTBL SELECT * FROM old.$MTBL WHERE session_id='$SID'; $PART_SQL COMMIT; DETACH old; PRAGMA foreign_keys=ON;"
    RESULT=$(sqlite3 "$OUT_DB" "SELECT COUNT(*) FROM $STBL WHERE id='$SID';")
    if [ "$RESULT" -gt 0 ]; then
        MSGS=$(sqlite3 "$OUT_DB" "SELECT COUNT(*) FROM $MTBL WHERE session_id='$SID';")
        SIZE=$(du -h "$OUT_DB" | cut -f1)
        echo "Backup OK: $MSGS messages saved to $OUT_DB ($SIZE)"
        echo "To restore on another machine: opencode-manager.sh, option 2, source $OUT_DB"
    else
        echo "Backup FAILED"
        rm -f "$OUT_DB"
        exit 1
    fi
}

show_menu

case "$OP" in
    1) do_cleanup ;;
    2) do_import ;;
    3) do_backup ;;
    q) echo "Aborted"; exit 0 ;;
    *) echo "Invalid selection"; exit 1 ;;
esac
