#!/bin/bash
# SuperTask™ Desktop Launcher
# Double-click friendly GUI that configures and starts the autonomous loop.
# The loop runs headless in the background; a GTK monitor app shows status.
# Supports 1-3 creative variations with round-robin execution.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ICON="/home/adam/.claude/plugins/autoloop/icon.png"

# Source creative presets
source "$SCRIPT_DIR/presets.sh"

# ─── CHECK FOR EXISTING RUNNING LOOP ───
for lockfile in /tmp/autoloop-*.lock; do
    [ -f "$lockfile" ] || continue
    PID=$(cat "$lockfile" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        EXISTING_DIR=$(cat "${lockfile}.dir" 2>/dev/null || echo "")
        if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
            zenity --question \
                --title="SuperTask™" \
                --width=450 \
                --window-icon="$ICON" \
                --text="A session is already running:\n<b>$EXISTING_DIR</b>\n\nOpen that session?" \
                --ok-label="Open" \
                --cancel-label="Start New" \
                2>/dev/null
            if [ $? -eq 0 ]; then
                exec python3 "$SCRIPT_DIR/monitor.py" "$EXISTING_DIR" "$PID"
            fi
        fi
    fi
done

# ─── GTK3 CONFIG DIALOG ───
# Replaces zenity --forms with a proper reactive dialog.
# Handles account management, conditional fields, and validation.
# Outputs: account_label|config_dir|mission|work_dir|variations|v2_preset|v3_preset|
#          max_cycles|max_iters|model|mode|time_limit
CONFIG=$(python3 "$SCRIPT_DIR/config_dialog.py" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CONFIG" ]; then
    exit 0
fi

# Parse all fields from the GTK3 dialog
IFS='|' read -r ACCOUNT_LABEL SELECTED_CONFIG_DIR MISSION WORK_DIR NUM_VARIANTS V2_PRESET_RAW V3_PRESET_RAW MAX_CYCLES MAX_ITERS MODEL MODE TIME_LIMIT_STR WEBSITE_BRIEF_TMPFILE <<< "$CONFIG"

# ─── DEFAULTS ───
NUM_VARIANTS="${NUM_VARIANTS:-1}"
MODEL="${MODEL:-opus}"
MODE="${MODE:-General}"
TIMEOUT=1800
INTERVAL=30

if [ "$MAX_CYCLES" = "Infinite" ] || [ -z "$MAX_CYCLES" ]; then
    MAX_CYCLES=0
fi

if [ "$MAX_ITERS" = "Infinite" ] || [ -z "$MAX_ITERS" ]; then
    MAX_ITERS=0
fi

# Parse time limit to seconds
case "$TIME_LIMIT_STR" in
    "30 minutes") TIME_LIMIT_SECS=1800 ;;
    "1 hour")     TIME_LIMIT_SECS=3600 ;;
    "2 hours")    TIME_LIMIT_SECS=7200 ;;
    "4 hours")    TIME_LIMIT_SECS=14400 ;;
    "8 hours")    TIME_LIMIT_SECS=28800 ;;
    "12 hours")   TIME_LIMIT_SECS=43200 ;;
    "24 hours")   TIME_LIMIT_SECS=86400 ;;
    *)            TIME_LIMIT_SECS=0 ;;
esac

# ─── VARIANT PRESETS ───
VARIANT_1_PRESET="Faithful"
VARIANT_2_PRESET="${V2_PRESET_RAW:-N/A}"
VARIANT_3_PRESET="${V3_PRESET_RAW:-N/A}"

# Treat empty or "N/A" as unused
[ "$VARIANT_2_PRESET" = "N/A" ] || [ -z "$VARIANT_2_PRESET" ] && VARIANT_2_PRESET=""
[ "$VARIANT_3_PRESET" = "N/A" ] || [ -z "$VARIANT_3_PRESET" ] && VARIANT_3_PRESET=""

# Validate: if Variations > 1 but V2 not set
if [ "$NUM_VARIANTS" -ge 2 ] && [ -z "$VARIANT_2_PRESET" ]; then
    zenity --error \
        --title="SuperTask™" \
        --width=400 \
        --window-icon="$ICON" \
        --text="You selected <b>$NUM_VARIANTS variations</b> but V2 Preset is N/A.\n\nPlease pick a creative direction for Variant 2." \
        2>/dev/null
    exit 0
fi

if [ "$NUM_VARIANTS" -ge 3 ] && [ -z "$VARIANT_3_PRESET" ]; then
    zenity --error \
        --title="SuperTask™" \
        --width=400 \
        --window-icon="$ICON" \
        --text="You selected <b>3 variations</b> but V3 Preset is N/A.\n\nPlease pick a creative direction for Variant 3." \
        2>/dev/null
    exit 0
fi

# Auto-upgrade variation count if presets were selected
if [ "$NUM_VARIANTS" -eq 1 ] && [ -n "$VARIANT_2_PRESET" ]; then
    NUM_VARIANTS=2
fi
if [ "$NUM_VARIANTS" -le 2 ] && [ -n "$VARIANT_3_PRESET" ]; then
    NUM_VARIANTS=3
fi

# ─── WORKING DIRECTORY ───
if [ -z "$WORK_DIR" ]; then
    WORK_DIR=$(zenity --file-selection \
        --directory \
        --title="Pick your project directory" \
        --filename="$HOME/Desktop/" \
        2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$WORK_DIR" ]; then
        exit 0
    fi
fi

if [ ! -d "$WORK_DIR" ]; then
    zenity --error --text="Directory does not exist: $WORK_DIR" \
        --window-icon="$ICON" 2>/dev/null
    exit 1
fi

# ─── MISSION ───
if [ -z "$MISSION" ]; then
    MISSION=$(zenity --text-info \
        --editable \
        --title="Enter your mission" \
        --width=700 \
        --height=400 \
        --text="Describe what you want Claude to work on autonomously..." \
        2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$MISSION" ]; then
        exit 0
    fi
fi

# ─── MODE LABEL ───
if [ "$MODE" = "Website Builder" ]; then
    MODE_LABEL="Website Builder (Playwright + localhost)"
else
    MODE_LABEL="General"
fi

# ─── VARIANT SUMMARY ───
VARIANT_SUMMARY=""
if [ "$NUM_VARIANTS" -eq 1 ]; then
    VARIANT_SUMMARY="<b>Variations:</b> 1 (Faithful)"
else
    VARIANT_SUMMARY="<b>Variations:</b> $NUM_VARIANTS\n  V1: Faithful to prompt\n  V2: $VARIANT_2_PRESET"
    if [ "$NUM_VARIANTS" -eq 3 ]; then
        VARIANT_SUMMARY="$VARIANT_SUMMARY\n  V3: $VARIANT_3_PRESET"
    fi
fi

# ─── CONFIRM ───
# Truncate mission for display (full text is preserved in $MISSION)
MISSION_PREVIEW="$MISSION"
if [ ${#MISSION_PREVIEW} -gt 200 ]; then
    MISSION_PREVIEW="${MISSION_PREVIEW:0:200}…"
fi
zenity --question \
    --title="SuperTask™" \
    --width=500 \
    --window-icon="$ICON" \
    --text="<b>Account:</b> $ACCOUNT_LABEL\n<b>Mission:</b> $MISSION_PREVIEW\n\n<b>Directory:</b> $WORK_DIR\n<b>Model:</b> $MODEL\n<b>Mode:</b> $MODE_LABEL$([ -n "$WEBSITE_BRIEF_FILE" ] && echo "\n<b>Website Brief:</b> Configured" || true)\n$VARIANT_SUMMARY\n<b>Max cycles:</b> $([ "$MAX_CYCLES" = "0" ] && echo "Infinite" || echo "$MAX_CYCLES")\n<b>Max iterations:</b> $([ "$MAX_ITERS" = "0" ] && echo "Infinite" || echo "$MAX_ITERS")\n<b>Time limit:</b> $([ "$TIME_LIMIT_SECS" = "0" ] && echo "No limit" || echo "$TIME_LIMIT_STR")\n\nReady to launch?" \
    --ok-label="Launch" \
    --cancel-label="Cancel" \
    2>/dev/null

if [ $? -ne 0 ]; then
    exit 0
fi

# ─── ACCOUNT ───
# Export CLAUDE_CONFIG_DIR early so init phase uses the correct account.
export CLAUDE_CONFIG_DIR="$SELECTED_CONFIG_DIR"
export AUTOLOOP_ACCOUNT="$ACCOUNT_LABEL"

# ─── SETUP ───
mkdir -p "$WORK_DIR/autoloop-logs"

# ─── WEBSITE BRIEF ───
WEBSITE_BRIEF_FILE=""
if [ -n "$WEBSITE_BRIEF_TMPFILE" ] && [ -f "$WEBSITE_BRIEF_TMPFILE" ]; then
    mkdir -p "$WORK_DIR/autoloop-logs/assets"
    WEBSITE_BRIEF_FILE="$WORK_DIR/autoloop-logs/website-brief.json"
    python3 - "$WEBSITE_BRIEF_TMPFILE" "$WORK_DIR/autoloop-logs/assets" "$WEBSITE_BRIEF_FILE" <<'PYEOF'
import json, shutil, os, sys
src_file, assets_dir, dst_file = sys.argv[1], sys.argv[2], sys.argv[3]
brief = json.load(open(src_file))
def copy_files(file_list):
    result = []
    for f in file_list:
        if not os.path.isfile(f):
            continue
        base, ext = os.path.splitext(os.path.basename(f))
        dst = os.path.join(assets_dir, f'{base}{ext}')
        counter = 1
        while os.path.exists(dst):
            dst = os.path.join(assets_dir, f'{base}_{counter}{ext}')
            counter += 1
        shutil.copy2(f, dst)
        result.append(dst)
    return result
brief['brand_logos'] = copy_files(brief.get('brand_logos', []))
brief['brand_reference_images'] = copy_files(brief.get('brand_reference_images', []))
brief['inspiration_images'] = copy_files(brief.get('inspiration_images', []))
json.dump(brief, open(dst_file, 'w'), indent=2)
PYEOF
    rm -f "$WEBSITE_BRIEF_TMPFILE"
fi

# ─── ARCHIVE OLD SESSION ───
if [ -n "$MISSION" ]; then
    NEEDS_ARCHIVE=false

    if [ -f "$WORK_DIR/PLAN.md" ]; then
        NEEDS_ARCHIVE=true
    fi

    for vdir in "$WORK_DIR"/variant_*; do
        if [ -d "$vdir" ]; then
            NEEDS_ARCHIVE=true
            break
        fi
    done

    if [ "$NEEDS_ARCHIVE" = true ]; then
        ARCHIVE="$WORK_DIR/autoloop-logs/archive_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$ARCHIVE"
        mv "$WORK_DIR/PLAN.md" "$ARCHIVE/" 2>/dev/null || true
        for vdir in "$WORK_DIR"/variant_*; do
            [ -d "$vdir" ] && mv "$vdir" "$ARCHIVE/" 2>/dev/null || true
        done
        mv "$WORK_DIR/autoloop-logs/history.log" "$ARCHIVE/" 2>/dev/null || true
        mv "$WORK_DIR/autoloop-logs/loop.log" "$ARCHIVE/" 2>/dev/null || true
        rm -f "$WORK_DIR/autoloop-logs/STATUS" "$WORK_DIR/autoloop-logs/SESSION"
        rm -f "$WORK_DIR/autoloop-logs/STOP_SIGNAL" "$WORK_DIR/autoloop-logs/ralph_signal.txt"
        rm -f "$WORK_DIR/autoloop-logs/CURRENT_VARIANT"
    fi
fi

# ─── INIT PLAN.MD(s) ───
init_variant() {
    local V_NUM="$1"
    local V_DIR="$2"
    local V_PRESET="$3"
    local V_PLAN="$V_DIR/PLAN.md"

    if [ -f "$V_PLAN" ]; then
        return 0
    fi

    mkdir -p "$V_DIR/autoloop-logs"

    local CREATIVE_ADDON=""
    if [ "$V_PRESET" != "Faithful" ] && [ -n "$V_PRESET" ]; then
        local PRESET_DESC
        PRESET_DESC=$(get_preset_description "$V_PRESET")
        # If no preset match, the user typed custom text — use it directly
        if [ -z "$PRESET_DESC" ]; then
            PRESET_DESC="CREATIVE DIRECTION (CUSTOM): $V_PRESET"
        fi
        CREATIVE_ADDON="

IMPORTANT — CREATIVE DIRECTION FOR THIS VARIANT:
$PRESET_DESC

You MUST incorporate this creative direction into every aspect of your plan. The tasks you generate
should reflect this creative vision. Every design decision, color choice, layout approach, animation
style, and tone of copy must align with this direction. This is non-negotiable — this variant exists
specifically to explore this creative approach."
    fi

    local BRIEF_ADDON=""
    if [ -n "$WEBSITE_BRIEF_FILE" ] && [ -f "$WEBSITE_BRIEF_FILE" ]; then
        BRIEF_ADDON=$(python3 - "$WEBSITE_BRIEF_FILE" <<'PYEOF'
import json, sys
brief = json.load(open(sys.argv[1]))
parts = []
if brief.get('brand_dna'):
    parts.append(f"BRAND DNA:\n{brief['brand_dna']}")
if brief.get('brand_logos'):
    parts.append("BRAND LOGOS (read these image files with Read tool):\n" + '\n'.join(f"  - {f}" for f in brief['brand_logos']))
if brief.get('brand_reference_images'):
    parts.append("BRAND REFERENCE IMAGES (read these files with Read tool):\n" + '\n'.join(f"  - {f}" for f in brief['brand_reference_images']))
if brief.get('brand_urls'):
    parts.append("BRAND WEBSITES (visit with Playwright for reference):\n" + '\n'.join(f"  - {u}" for u in brief['brand_urls']))
if brief.get('brand_notes'):
    parts.append(f"BRAND NOTES:\n{brief['brand_notes']}")
if brief.get('inspiration_urls'):
    parts.append("INSPIRATION WEBSITES (visit for design reference):\n" + '\n'.join(f"  - {u}" for u in brief['inspiration_urls']))
if brief.get('inspiration_images'):
    parts.append("INSPIRATION REFERENCE IMAGES (read these files with Read tool):\n" + '\n'.join(f"  - {f}" for f in brief['inspiration_images']))
if brief.get('inspiration_notes'):
    parts.append(f"INSPIRATION NOTES:\n{brief['inspiration_notes']}")
if brief.get('master_prompt'):
    parts.append(f"MASTER PROMPT — The client's vision for the website:\n{brief['master_prompt']}")
if parts:
    print("\n\n== WEBSITE BRIEF ==\n" + '\n\n'.join(parts) + "\n\nUse ALL of the above context to inform your plan. The tasks you generate should incorporate the brand identity, draw from the inspirations, and fulfill the master prompt.")
PYEOF
        )
    fi

    local VARIANT_LABEL=""
    if [ "$NUM_VARIANTS" -gt 1 ]; then
        VARIANT_LABEL=" (Variant $V_NUM — $V_PRESET)"
    fi

    (
        cd "$V_DIR"
        claude -p "$(cat <<INITPROMPT
You are initializing an autonomous loop.${VARIANT_LABEL} Mission: "$MISSION"
${CREATIVE_ADDON}${BRIEF_ADDON}

CRITICAL RULE: You MUST write PLAN.md to disk BEFORE doing anything else. Do NOT research,
fetch websites, or explore extensively first. Write the plan file IMMEDIATELY based on what
you already know, then refine it if budget allows.

STEP 1 — WRITE PLAN.md NOW with this structure:

# Autonomous Plan

## Mission
$MISSION

## Creative Direction
$V_PRESET$([ "$V_PRESET" != "Faithful" ] && echo " — See below for detailed direction" || echo " — Execute exactly as described in the mission")

## Context
[Quick scan of the current directory only. Read any CLAUDE.md, README.md, package.json if they exist. Write 5-15 bullet points. Do NOT fetch external URLs — the loop iterations will handle research.]

## Active Tasks (Priority Order)
[Generate 5-8 concrete, specific tasks based on the mission. Each completable in ~30 min. Task 1 should be research/analysis if needed. Do NOT do the research yourself — just plan it as a task.]
1. [ ] First task
2. [ ] Second task
...

## Completed
(none yet)

## Discoveries
(none yet)

## Meta
- Cycles: 0
- Iterations: 0
- Tasks completed: 0
- Variant: $V_NUM of $NUM_VARIANTS ($V_PRESET)
- Last replanned: $(date '+%Y-%m-%d %H:%M:%S')
- Last updated: $(date '+%Y-%m-%d %H:%M:%S')
- Mission started: $(date '+%Y-%m-%d %H:%M:%S')

STEP 2 — Verify PLAN.md exists on disk (read it back).
STEP 3 — Create autoloop-logs/ directory if it doesn't exist.

IMPORTANT: The autonomous loop will handle ALL the actual work. Your ONLY job is to create a
solid starting plan. Do NOT try to execute any tasks. Do NOT fetch external websites. Do NOT
install dependencies. Just write the plan and stop.
INITPROMPT
)" \
            --dangerously-skip-permissions \
            --model "$MODEL" \
            --max-turns 50 \
            > "$V_DIR/autoloop-logs/init.log" 2>&1
    )
}

INIT_NEEDED=false

if [ "$NUM_VARIANTS" -eq 1 ]; then
    if [ ! -f "$WORK_DIR/PLAN.md" ]; then
        INIT_NEEDED=true
    fi
else
    for V in $(seq 1 "$NUM_VARIANTS"); do
        if [ ! -f "$WORK_DIR/variant_$V/PLAN.md" ]; then
            INIT_NEEDED=true
            break
        fi
    done
fi

if [ "$INIT_NEEDED" = true ]; then
    (
        if [ "$NUM_VARIANTS" -eq 1 ]; then
            init_variant 1 "$WORK_DIR" "Faithful"
        else
            for V in $(seq 1 "$NUM_VARIANTS"); do
                case "$V" in
                    1) V_PRESET="$VARIANT_1_PRESET" ;;
                    2) V_PRESET="$VARIANT_2_PRESET" ;;
                    3) V_PRESET="$VARIANT_3_PRESET" ;;
                esac
                V_DIR="$WORK_DIR/variant_$V"
                init_variant "$V" "$V_DIR" "$V_PRESET"
            done
        fi
    ) &
    INIT_PID=$!

    INIT_TEXT="Initializing — scanning project and creating plan..."
    if [ "$NUM_VARIANTS" -gt 1 ]; then
        INIT_TEXT="Initializing $NUM_VARIANTS variants — creating plans..."
    fi

    (
        while kill -0 $INIT_PID 2>/dev/null; do
            echo "# $INIT_TEXT"
            sleep 1
        done
        echo "100"
    ) | zenity --progress \
        --pulsate \
        --auto-close \
        --no-cancel \
        --title="SuperTask™" \
        --text="$INIT_TEXT" \
        --window-icon="$ICON" \
        2>/dev/null

    wait $INIT_PID

    MISSING_PLANS=""
    if [ "$NUM_VARIANTS" -eq 1 ]; then
        if [ ! -f "$WORK_DIR/PLAN.md" ]; then
            MISSING_PLANS="PLAN.md"
        fi
    else
        for V in $(seq 1 "$NUM_VARIANTS"); do
            if [ ! -f "$WORK_DIR/variant_$V/PLAN.md" ]; then
                MISSING_PLANS="$MISSING_PLANS variant_$V/PLAN.md"
            fi
        done
    fi

    if [ -n "$MISSING_PLANS" ]; then
        INIT_LOG=""
        if [ "$NUM_VARIANTS" -eq 1 ]; then
            INIT_LOG="$WORK_DIR/autoloop-logs/init.log"
        else
            for V in $(seq 1 "$NUM_VARIANTS"); do
                if [ ! -f "$WORK_DIR/variant_$V/PLAN.md" ]; then
                    INIT_LOG="$WORK_DIR/variant_$V/autoloop-logs/init.log"
                    break
                fi
            done
        fi

        TAIL_LOG=""
        if [ -n "$INIT_LOG" ] && [ -f "$INIT_LOG" ]; then
            TAIL_LOG=$(tail -20 "$INIT_LOG" 2>/dev/null | head -15)
        fi

        zenity --error \
            --title="SuperTask™ — Init Failed" \
            --width=600 \
            --window-icon="$ICON" \
            --text="Plan(s) not created:$MISSING_PLANS\n\nClaude may have had an issue during initialization.\n\n<b>Init log (last lines):</b>\n<tt>$TAIL_LOG</tt>\n\nCheck the full log at:\n$INIT_LOG" \
            2>/dev/null
        exit 1
    fi
fi

# ─── CLEAN STALE SIGNALS ───
rm -f "$WORK_DIR/autoloop-logs/STOP_SIGNAL"
rm -f "$WORK_DIR/autoloop-logs/ralph_signal.txt"
rm -f "$WORK_DIR/autoloop-logs/CURRENT_VARIANT"

if [ "$NUM_VARIANTS" -gt 1 ]; then
    for V in $(seq 1 "$NUM_VARIANTS"); do
        rm -f "$WORK_DIR/variant_$V/autoloop-logs/ralph_signal.txt"
    done
fi

echo "Starting..." > "$WORK_DIR/autoloop-logs/STATUS"

# ─── START LOOP IN BACKGROUND ───
export AUTOLOOP_DIR="$WORK_DIR"
export AUTOLOOP_INTERVAL="$INTERVAL"
export AUTOLOOP_TIMEOUT="$TIMEOUT"
export AUTOLOOP_MODEL="$MODEL"
export AUTOLOOP_MAX_CYCLES="$MAX_CYCLES"
export AUTOLOOP_MAX_ITERS="$MAX_ITERS"
export AUTOLOOP_MODE="$MODE"
export AUTOLOOP_WEBSITE_BRIEF="$WEBSITE_BRIEF_FILE"
export AUTOLOOP_TIME_LIMIT="$TIME_LIMIT_SECS"
export AUTOLOOP_NUM_VARIANTS="$NUM_VARIANTS"
export AUTOLOOP_VARIANT_1_PRESET="$VARIANT_1_PRESET"
export AUTOLOOP_VARIANT_2_PRESET="$VARIANT_2_PRESET"
export AUTOLOOP_VARIANT_3_PRESET="$VARIANT_3_PRESET"
export PATH="/home/adam/.local/bin:$PATH"

nohup bash "$PLUGIN_DIR/scripts/loop.sh" \
    > "$WORK_DIR/autoloop-logs/terminal.log" 2>&1 &
LOOP_PID=$!
disown $LOOP_PID

sleep 1

# ─── LAUNCH MONITOR ───
exec python3 "$SCRIPT_DIR/monitor.py" "$WORK_DIR" "$LOOP_PID"
