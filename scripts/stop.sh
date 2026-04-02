#!/bin/bash
# SuperTask™ Graceful Stop
# Finds the running autoloop and signals it to finish up, polish, and exit.

ICON="/home/adam/.claude/plugins/autoloop/icon.png"

# Find all autoloop-logs directories that have a running loop
CANDIDATES=()
for lockfile in /tmp/autoloop-*.lock; do
    [ -f "$lockfile" ] || continue
    PID=$(cat "$lockfile" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # Read work dir from sidecar file
        WORK_DIR=$(cat "${lockfile}.dir" 2>/dev/null || echo "")
        if [ -n "$WORK_DIR" ]; then
            CANDIDATES+=("$WORK_DIR")
        fi
    fi
done

if [ ${#CANDIDATES[@]} -eq 0 ]; then
    zenity --info \
        --title="SuperTask™" \
        --text="No running SuperTask™ sessions found." \
        --window-icon="$ICON" \
        2>/dev/null
    exit 0
fi

# If multiple, let user pick. If one, use it directly.
if [ ${#CANDIDATES[@]} -eq 1 ]; then
    TARGET="${CANDIDATES[0]}"
else
    TARGET=$(printf '%s\n' "${CANDIDATES[@]}" | zenity --list \
        --title="SuperTask™ — Stop Which Session?" \
        --column="Working Directory" \
        --window-icon="$ICON" \
        2>/dev/null)
    [ -z "$TARGET" ] && exit 0
fi

# Confirm
zenity --question \
    --title="SuperTask™" \
    --width=450 \
    --window-icon="$ICON" \
    --text="Stop SuperTask™ gracefully?\n\n<b>Directory:</b> $TARGET\n\nClaude will finish its current task, polish everything, clean up, and exit." \
    --ok-label="Stop Gracefully" \
    --cancel-label="Cancel" \
    2>/dev/null

if [ $? -ne 0 ]; then
    exit 0
fi

# Write the stop signal
echo "STOP requested at $(date '+%Y-%m-%d %H:%M:%S')" > "$TARGET/autoloop-logs/STOP_SIGNAL"

zenity --info \
    --title="SuperTask™" \
    --text="Stop signal sent. Claude will finish its current task, polish everything, and exit.\n\nThis may take a few minutes." \
    --window-icon="$ICON" \
    2>/dev/null
