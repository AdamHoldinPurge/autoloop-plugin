#!/bin/bash
# SuperTask™ + Ralph — Two-Phase Autonomous Loop
#
# Phase 1 (RALPH): Execute all tasks in PLAN.md until done
# Phase 2 (REPLAN): Review what was accomplished, generate a brand new plan
# Repeat forever.
#
# Supports:
#   AUTOLOOP_MODE="Website Builder" — adds Playwright verification to every task
#   AUTOLOOP_NUM_VARIANTS=1|2|3 — round-robin creative variations
#   Graceful stop via STOP_SIGNAL file — finishes current work, polishes, exits

set -euo pipefail

# Configuration
WORK_DIR="${AUTOLOOP_DIR:-$(pwd)}"
INTERVAL="${AUTOLOOP_INTERVAL:-30}"
REPLAN_PAUSE="${AUTOLOOP_REPLAN_PAUSE:-60}"
TIMEOUT="${AUTOLOOP_TIMEOUT:-1800}"
REPLAN_TIMEOUT="${AUTOLOOP_REPLAN_TIMEOUT:-900}"
MODEL="${AUTOLOOP_MODEL:-opus}"
MAX_CYCLES="${AUTOLOOP_MAX_CYCLES:-0}"
MAX_ITERS="${AUTOLOOP_MAX_ITERS:-0}"
MODE="${AUTOLOOP_MODE:-General}"
WEBSITE_BRIEF="${AUTOLOOP_WEBSITE_BRIEF:-}"
TIME_LIMIT="${AUTOLOOP_TIME_LIMIT:-0}"
NUM_VARIANTS="${AUTOLOOP_NUM_VARIANTS:-1}"
START_TIME=$(date +%s)

# Root log directory (always at work_dir level)
ROOT_LOG_DIR="$WORK_DIR/autoloop-logs"
LOCKFILE="/tmp/autoloop-$(echo "$WORK_DIR" | md5sum | cut -c1-8).lock"
STOP_SIGNAL="$ROOT_LOG_DIR/STOP_SIGNAL"
STATUS_FILE="$ROOT_LOG_DIR/STATUS"
set_status() { echo "$1" > "$STATUS_FILE"; }

# Source creative presets
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/presets.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }
phase() { echo -e "${MAGENTA}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }
stoplog() { echo -e "${CYAN}[autoloop $(date '+%H:%M:%S')]${NC} $1"; }

mkdir -p "$ROOT_LOG_DIR"

# Write session info for monitor FIRST — so END_TIME can always be written on exit
{
    echo "START_TIME=$START_TIME"
    echo "TIME_LIMIT=$TIME_LIMIT"
    echo "NUM_VARIANTS=$NUM_VARIANTS"
    echo "VARIANT_1_PRESET=${AUTOLOOP_VARIANT_1_PRESET:-Faithful}"
    echo "VARIANT_2_PRESET=${AUTOLOOP_VARIANT_2_PRESET:-}"
    echo "VARIANT_3_PRESET=${AUTOLOOP_VARIANT_3_PRESET:-}"
    echo "ACCOUNT=${AUTOLOOP_ACCOUNT:-}"
    echo "CONFIG_DIR=${CLAUDE_CONFIG_DIR:-}"
} > "$ROOT_LOG_DIR/SESSION"

# ─── VARIANT PATH HELPERS ───
# For single variant: paths point to WORK_DIR (flat, unchanged behavior)
# For multiple variants: paths point to WORK_DIR/variant_N/
get_variant_dir() {
    local V="$1"
    if [ "$NUM_VARIANTS" -eq 1 ]; then
        echo "$WORK_DIR"
    else
        echo "$WORK_DIR/variant_$V"
    fi
}

get_variant_plan() {
    echo "$(get_variant_dir "$1")/PLAN.md"
}

get_variant_logs() {
    if [ "$NUM_VARIANTS" -eq 1 ]; then
        echo "$ROOT_LOG_DIR"
    else
        echo "$(get_variant_dir "$1")/autoloop-logs"
    fi
}

get_variant_preset() {
    local V="$1"
    case "$V" in
        1) echo "${AUTOLOOP_VARIANT_1_PRESET:-Faithful}" ;;
        2) echo "${AUTOLOOP_VARIANT_2_PRESET:-}" ;;
        3) echo "${AUTOLOOP_VARIANT_3_PRESET:-}" ;;
    esac
}

# Build creative direction text for a variant (empty string for Faithful)
get_creative_injection() {
    local V="$1"
    local PRESET
    PRESET=$(get_variant_preset "$V")
    if [ "$PRESET" = "Faithful" ] || [ -z "$PRESET" ]; then
        echo ""
        return
    fi
    local DESC
    DESC=$(get_preset_description "$PRESET")
    # If no preset match, the user typed custom text — use it directly
    if [ -z "$DESC" ]; then
        DESC="CREATIVE DIRECTION (CUSTOM): $PRESET"
    fi
    echo "
CREATIVE DIRECTION FOR THIS VARIANT ($PRESET):
$DESC

All your work MUST follow this creative direction. Every design decision — colors, typography,
layout, animations, imagery, copy tone — must reflect this direction. This is non-negotiable.

"
}

# Lockfile — set up early so trap can clean it
if [ -f "$LOCKFILE" ]; then
    OLD_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        error "Another autoloop is already running (PID $OLD_PID)"
        echo "END_TIME=$(date +%s)" >> "$ROOT_LOG_DIR/SESSION"
        echo "Stopped" > "$ROOT_LOG_DIR/STATUS"
        exit 1
    fi
    warn "Stale lockfile found, removing"
fi
echo $$ > "$LOCKFILE"
echo "$WORK_DIR" > "${LOCKFILE}.dir"

# Trap MUST be set before any exit that the monitor could misinterpret
trap "rm -f '$LOCKFILE' '${LOCKFILE}.dir'; echo 'Stopped' > '$ROOT_LOG_DIR/STATUS'; echo \"END_TIME=\$(date +%s)\" >> '$ROOT_LOG_DIR/SESSION'; log 'SuperTask™ stopped.'" EXIT

# Check for PLAN.md(s)
for V in $(seq 1 "$NUM_VARIANTS"); do
    V_PLAN=$(get_variant_plan "$V")
    if [ ! -f "$V_PLAN" ]; then
        error "No PLAN.md found at $V_PLAN"
        error "Run the launcher to create one first."
        exit 1
    fi
done

# Clean up old logs (keep last 48 hours)
find "$ROOT_LOG_DIR" -maxdepth 1 -name "*.log" -not -name "loop.log" -not -name "history.log" -not -name "terminal.log" -mmin +2880 -delete 2>/dev/null || true

# Banner
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   SUPERTASK™                   ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Mode:        ${CYAN}$MODE${NC}"
echo -e "${GREEN}║${NC}  Directory:   $WORK_DIR"
echo -e "${GREEN}║${NC}  Model:       $MODEL"
echo -e "${GREEN}║${NC}  Variants:    $NUM_VARIANTS"
if [ "$NUM_VARIANTS" -gt 1 ]; then
    for V in $(seq 1 "$NUM_VARIANTS"); do
        echo -e "${GREEN}║${NC}    V$V:        $(get_variant_preset "$V")"
    done
fi
echo -e "${GREEN}║${NC}  Max cycles:  $([ "$MAX_CYCLES" = "0" ] && echo "infinite" || echo "$MAX_CYCLES")"
echo -e "${GREEN}║${NC}  Max iters:   $([ "$MAX_ITERS" = "0" ] && echo "infinite" || echo "$MAX_ITERS")"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""

# ─── WEBSITE BUILDER MODE ADDON ───
WEBSITE_BUILDER_ADDON=""
if [ "$MODE" = "Website Builder" ]; then
    WEBSITE_BUILDER_ADDON='

WEBSITE BUILDER MODE — LOCAL DEVELOPMENT:
You are building a website. EVERYTHING runs on localhost on the users computer. This is non-negotiable.

STEP 0 — DEV SERVER (do this FIRST, before any other task):
1. Detect the project type by checking for: package.json (Vite, Next.js, React, Vue, Astro, etc.), index.html (static site), or nothing (new project).
2. If no project exists yet, initialize one. Pick the best framework for the mission (Vite for most sites, Next.js if SSR/routing needed, plain HTML+CSS for simple pages). Install dependencies.
3. Start the local dev server in the background. Common commands:
   - Vite/React/Vue/Astro: npm run dev (usually port 5173)
   - Next.js: npm run dev (usually port 3000)
   - Static HTML: npx serve . -p 8080 or python3 -m http.server 8080
4. Confirm the server is running — curl localhost:<port> and check for a 200 response.
5. Record the localhost URL (e.g. http://localhost:5173) in PLAN.md under Context.
6. If the dev server dies at any point during the session, restart it immediately before continuing work.

ALL development, testing, and verification happens against this localhost URL. Never deploy to a remote server during the build phase.

MANDATORY VERIFICATION (after EVERY task that changes UI, pages, styles, or functionality):
You MUST verify your work using Playwright against localhost before marking the task complete.

VERIFICATION CHECKLIST:
1. NAVIGATE: Open every page/route on localhost. Confirm they load without errors.
2. CLICK EVERYTHING: Click every button, link, nav item, dropdown, toggle, and interactive element. Confirm each one does what it should. If something does nothing or errors, fix it before moving on.
3. FORMS: Fill out and submit every form. Test with valid and invalid input. Confirm validation messages appear. Confirm successful submissions work end-to-end.
4. RESPONSIVE: Check the site at mobile (375px), tablet (768px), and desktop (1440px) widths. Fix any layout breaks, overflow, or unreadable text.
5. VISUAL: Take screenshots of key pages. Check for: overlapping elements, text cut off, broken images, missing styles, inconsistent spacing, ugly defaults.
6. CONSOLE: Check browser console for JavaScript errors, failed network requests, or 404s. Fix any you find.
7. ASSETS: Confirm all images, fonts, icons, and static files load. No broken images or missing resources.
8. CROSS-PAGE: Test navigation flows — click through the site the way a real user would. Home → about → contact → back. Confirm no dead ends.

If ANY check fails, fix it immediately. Do not mark the task done until all checks pass.
Log verification results in your history entry: "Verified: [N] pages, [N] clicks, [N] forms, [pass/fail] @ localhost:<port>"'
fi

# ─── WEBSITE BRIEF ADDON ───
WEBSITE_BRIEF_ADDON=""
if [ -n "$WEBSITE_BRIEF" ] && [ -f "$WEBSITE_BRIEF" ]; then
    WEBSITE_BRIEF_ADDON=$(python3 - "$WEBSITE_BRIEF" <<'PYEOF'
import json, sys
brief = json.load(open(sys.argv[1]))
parts = []
if brief.get('brand_dna'):
    parts.append(f"BRAND DNA:\n{brief['brand_dna']}")
if brief.get('brand_logos'):
    parts.append("BRAND LOGOS (read these files for visual reference):\n" + '\n'.join(f"  - {f}" for f in brief['brand_logos']))
if brief.get('brand_reference_images'):
    parts.append("BRAND REFERENCE IMAGES (read these files):\n" + '\n'.join(f"  - {f}" for f in brief['brand_reference_images']))
if brief.get('brand_urls'):
    parts.append("BRAND WEBSITES (visit for reference):\n" + '\n'.join(f"  - {u}" for u in brief['brand_urls']))
if brief.get('brand_notes'):
    parts.append(f"BRAND NOTES:\n{brief['brand_notes']}")
if brief.get('inspiration_urls'):
    parts.append("INSPIRATION WEBSITES (visit for design reference):\n" + '\n'.join(f"  - {u}" for u in brief['inspiration_urls']))
if brief.get('inspiration_images'):
    parts.append("INSPIRATION REFERENCE IMAGES (read these files):\n" + '\n'.join(f"  - {f}" for f in brief['inspiration_images']))
if brief.get('inspiration_notes'):
    parts.append(f"INSPIRATION NOTES:\n{brief['inspiration_notes']}")
if brief.get('master_prompt'):
    parts.append(f"MASTER PROMPT — What the website should be:\n{brief['master_prompt']}")
if parts:
    print("\n\n== WEBSITE BRIEF ==\n" + '\n\n'.join(parts) + "\n\nUse ALL of the above brand context to inform your work — design decisions, color choices, typography, imagery, layout, and overall aesthetic. This is the client's brand — respect and embody it.")
PYEOF
    )
fi

# ─── BASE PROMPTS (variant-agnostic) ───
# Creative direction gets prepended per-variant at runtime

BASE_RALPH_PROMPT="You are the EXECUTOR inside an autonomous Ralph loop.

READ PLAN.md NOW. Then:

1. Look at \"Active Tasks (Priority Order)\" — find the FIRST unchecked [ ] task
2. EXECUTE it. Write code, run commands, deploy, research, analyze. Do the actual work.
3. When done, update PLAN.md:
   - Mark the task [x] with a brief result note
   - Update Context if you discovered important facts
   - Add a Discoveries bullet point for what you learned
   - Increment \"Iterations\" and \"Tasks completed\" in Meta
   - Update \"Last updated\" timestamp
4. Append a one-line summary to autoloop-logs/history.log:
   [timestamp] Ralph iteration: [task] — [result]

IMPORTANT:
- Do NOT generate new tasks. That is the Replan phase's job.
- Do NOT rewrite the plan. Just mark your task done and update context.
- Focus entirely on EXECUTING the single top task well.
- If the task is too big, do as much as you can and note what remains.
- Be honest about failures — note them clearly in the task result.
- If there are NO unchecked tasks remaining, write \"ALL_TASKS_COMPLETE\" to autoloop-logs/ralph_signal.txt and stop.${WEBSITE_BUILDER_ADDON}"

BASE_REPLAN_PROMPT="You are the STRATEGIC PLANNER inside an autonomous loop.

Ralph just finished executing all the tasks in PLAN.md. Your job is to review what happened and generate a BRAND NEW plan.

READ PLAN.md NOW — especially the Completed section and Discoveries.

Then REWRITE PLAN.md with:

## Mission
[Keep the original mission — never change this]

## Creative Direction
[Keep the original creative direction — never change this]

## Context
[Keep existing context. Add any new facts from the completed work. Remove anything outdated.]

## Active Tasks (Priority Order)
[Generate 5-10 NEW, specific, actionable tasks. These should be:]
- Based on what was accomplished and discovered in the previous cycle
- The logical next steps toward the Mission
- A mix of: building/implementing, testing/validating, researching/exploring, monitoring/maintaining
- Specific enough to execute in ~30 minutes each (\"implement X in file Y\" not \"improve Z\")
- Prioritized: most impactful first
- Consider: what failed and needs fixing? What succeeded and can be built on? What new opportunities emerged?

## Completed
[Move the PREVIOUS completed items to an archive section or keep only the last 20. Add a cycle summary line:]
- Cycle N complete: [1-line summary of what the whole cycle accomplished]

## Discoveries
[Keep all discoveries — this is institutional memory. Add a cycle-level insight.]

## Meta
- Cycles: [increment by 1]
- Iterations: [keep running total from Ralph]
- Tasks completed: [keep running total]
- Last replanned: [current timestamp]
- Last updated: [current timestamp]

RULES:
- Active Tasks must have 5-10 items. Never fewer.
- Tasks must be NOVEL — do not repeat tasks that were already completed.
- Think strategically: what moves the Mission forward fastest?
- Consider diminishing returns — if one area is well-optimized, shift focus elsewhere.
- Include at least 1 research/exploration task to discover new opportunities.
- Write the plan, then write a replan summary to autoloop-logs/replan_N.md

After writing PLAN.md, also delete autoloop-logs/ralph_signal.txt if it exists."

BASE_POLISH_PROMPT="You are finishing up an autonomous loop. The user has requested a GRACEFUL STOP.

READ PLAN.md NOW.

Your job is to POLISH and FINALIZE everything:

1. Review all recent changes — read autoloop-logs/history.log to see what was done.
2. Fix any loose ends: incomplete implementations, TODO comments, missing error handling.
3. Clean up: remove debug logs, temp files, commented-out code.
4. If this is a website (check the project files and PLAN.md Context for localhost URL):
   - Make sure the dev server is still running on localhost. If not, restart it.
   - Run a FULL Playwright verification of the entire site against localhost — every page, every button, every form, responsive checks at 375/768/1440px, console errors, asset loading.
   - Fix any broken links, missing images, layout issues.
   - Ensure all pages load cleanly with no console errors.
   - Note the localhost URL and how to start the dev server in the final summary so the user can pick up where you left off.
5. Update PLAN.md:
   - Mark any in-progress tasks with their current state
   - Add a final section: \"## Session Summary\" with what was accomplished across all cycles
   - Note anything the user should review or that needs manual attention
   - If website: include the localhost URL and dev server start command
6. Write a final summary to autoloop-logs/final_summary.md:
   - What was built/changed
   - What works
   - What needs attention
   - Recommended next steps
   - If website: localhost URL, dev server command, and how to view the site

This is the LAST iteration. Make everything clean, polished, and ready for the user to pick up."

# Append website brief context to all prompts so every phase has brand awareness
if [ -n "$WEBSITE_BRIEF_ADDON" ]; then
    BASE_RALPH_PROMPT="${BASE_RALPH_PROMPT}${WEBSITE_BRIEF_ADDON}"
    BASE_REPLAN_PROMPT="${BASE_REPLAN_PROMPT}${WEBSITE_BRIEF_ADDON}"
    BASE_POLISH_PROMPT="${BASE_POLISH_PROMPT}${WEBSITE_BRIEF_ADDON}"
fi

# ─── Helpers ───
variant_ralph_is_done() {
    local V_DIR="$1"
    local V_PLAN="$V_DIR/PLAN.md"
    local V_LOGS
    if [ "$NUM_VARIANTS" -eq 1 ]; then
        V_LOGS="$ROOT_LOG_DIR"
    else
        V_LOGS="$V_DIR/autoloop-logs"
    fi

    if [ -f "$V_LOGS/ralph_signal.txt" ]; then
        return 0
    fi
    if ! grep -q '^\s*[0-9]*\.\s*\[ \]' "$V_PLAN" 2>/dev/null; then
        return 0
    fi
    return 1
}

check_stop_signal() {
    if [ -f "$STOP_SIGNAL" ]; then
        return 0
    fi
    return 1
}

check_time_limit() {
    [ "$TIME_LIMIT" = "0" ] && return 1
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    [ "$elapsed" -ge "$TIME_LIMIT" ]
}

get_time_context() {
    if [ "$TIME_LIMIT" = "0" ]; then
        echo "TIME: You have unlimited time in this session. "
        return
    fi
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    local remaining=$((TIME_LIMIT - elapsed))
    if [ "$remaining" -le 0 ]; then
        echo "TIME: Session time is up. Finish your current task cleanly and stop. "
        return
    fi
    local hours=$((remaining / 3600))
    local mins=$(( (remaining % 3600) / 60 ))
    if [ "$hours" -gt 0 ]; then
        echo "TIME: You have approximately ${hours}h ${mins}m remaining in this session. "
    elif [ "$mins" -gt 15 ]; then
        echo "TIME: You have approximately ${mins} minutes remaining. "
    else
        echo "TIME: Only ${mins} minutes remaining. Focus on completing and polishing your current task. "
    fi
}

# Run polish for a single variant
run_polish_variant() {
    local V="$1"
    local V_DIR
    V_DIR=$(get_variant_dir "$V")
    local V_LOGS
    V_LOGS=$(get_variant_logs "$V")
    local V_PRESET
    V_PRESET=$(get_variant_preset "$V")

    local CREATIVE_TEXT
    CREATIVE_TEXT=$(get_creative_injection "$V")

    local VARIANT_LABEL=""
    if [ "$NUM_VARIANTS" -gt 1 ]; then
        VARIANT_LABEL="You are working on Variant $V ($V_PRESET). "
    fi

    local TIMESTAMP
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local POLISH_LOG="$V_LOGS/polish_${TIMESTAMP}.log"

    mkdir -p "$V_LOGS"
    timeout "$TIMEOUT" claude \
        -p "${VARIANT_LABEL}${CREATIVE_TEXT}${BASE_POLISH_PROMPT}" \
        --dangerously-skip-permissions \
        --model "$MODEL" \
        --max-turns 100 \
        --output-format json \
        > "$POLISH_LOG" 2>&1 || true
}

# Run polish for ALL variants
run_polish_all() {
    for V in $(seq 1 "$NUM_VARIANTS"); do
        local V_DIR
        V_DIR=$(get_variant_dir "$V")
        if [ "$NUM_VARIANTS" -gt 1 ]; then
            stoplog "Polishing variant $V ($(get_variant_preset "$V"))..."
            echo "$V" > "$ROOT_LOG_DIR/CURRENT_VARIANT"
        fi
        (cd "$V_DIR" && run_polish_variant "$V")
    done
}

# ─── MAIN LOOP ───
CYCLE=0
TOTAL_ITERS=0

while true; do
    CYCLE=$((CYCLE + 1))

    # ═══════════════════════════════════════
    # CHECK TIME LIMIT
    # ═══════════════════════════════════════
    if check_time_limit; then
        set_status "Time limit reached — finishing up"
        stoplog "═══ TIME LIMIT REACHED ═══"
        echo "STOP requested (time limit) at $(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_SIGNAL"
    fi

    # ═══════════════════════════════════════
    # CHECK FOR GRACEFUL STOP before starting a new cycle
    # ═══════════════════════════════════════
    if check_stop_signal; then
        set_status "Polishing and finalizing"
        stoplog "═══ GRACEFUL STOP SIGNAL RECEIVED ═══"
        stoplog "Running final polish phase..."
        run_polish_all
        rm -f "$STOP_SIGNAL"
        success "Polish complete. SuperTask™ finished gracefully."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] GRACEFUL STOP — polish complete" >> "$ROOT_LOG_DIR/loop.log"
        break
    fi

    # ═══════════════════════════════════════
    # ITERATE OVER VARIANTS (round-robin)
    # ═══════════════════════════════════════
    for CURRENT_V in $(seq 1 "$NUM_VARIANTS"); do
        V_DIR=$(get_variant_dir "$CURRENT_V")
        V_PLAN=$(get_variant_plan "$CURRENT_V")
        V_LOGS=$(get_variant_logs "$CURRENT_V")
        V_PRESET=$(get_variant_preset "$CURRENT_V")
        CREATIVE_TEXT=$(get_creative_injection "$CURRENT_V")

        # Write current variant for monitor
        if [ "$NUM_VARIANTS" -gt 1 ]; then
            echo "$CURRENT_V" > "$ROOT_LOG_DIR/CURRENT_VARIANT"
        fi

        mkdir -p "$V_LOGS"

        # Check stop/time before each variant
        if check_time_limit; then
            set_status "Time limit reached — finishing up"
            echo "STOP requested (time limit) at $(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_SIGNAL"
        fi
        if check_stop_signal; then
            break
        fi

        # ═══════════════════════════════════════
        # PHASE 1: RALPH — Execute all tasks for this variant
        # ═══════════════════════════════════════
        VARIANT_LABEL=""
        if [ "$NUM_VARIANTS" -gt 1 ]; then
            VARIANT_LABEL="[V$CURRENT_V/$NUM_VARIANTS $V_PRESET] "
            phase "═══ CYCLE $CYCLE — ${VARIANT_LABEL}PHASE 1: RALPH (executing tasks) ═══"
        else
            phase "═══ CYCLE $CYCLE — PHASE 1: RALPH (executing tasks) ═══"
        fi

        RALPH_ITER=0
        while true; do
            # Check time limit
            if check_time_limit; then
                set_status "Time limit reached — finishing up"
                echo "STOP requested (time limit) at $(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_SIGNAL"
            fi

            # Check for graceful stop mid-cycle
            if check_stop_signal; then
                stoplog "Stop signal received mid-cycle — finishing up after this iteration"
                break
            fi

            if variant_ralph_is_done "$V_DIR"; then
                set_status "${VARIANT_LABEL}All tasks complete — preparing to replan"
                success "${VARIANT_LABEL}All tasks complete — Ralph is done for this cycle"
                break
            fi

            RALPH_ITER=$((RALPH_ITER + 1))
            TOTAL_ITERS=$((TOTAL_ITERS + 1))
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            ITER_LOG="$V_LOGS/ralph_c${CYCLE}_i${RALPH_ITER}_${TIMESTAMP}.log"

            if [ "$NUM_VARIANTS" -gt 1 ]; then
                set_status "${VARIANT_LABEL}Executing task (cycle $CYCLE, iter $RALPH_ITER, total $TOTAL_ITERS)"
                log "${VARIANT_LABEL}Ralph iteration $RALPH_ITER (cycle $CYCLE, total $TOTAL_ITERS)"
            else
                set_status "Executing task (cycle $CYCLE, iteration $RALPH_ITER, total $TOTAL_ITERS)"
                log "Ralph iteration $RALPH_ITER (cycle $CYCLE, total $TOTAL_ITERS)"
            fi

            TIME_CTX=$(get_time_context)

            VARIANT_CTX=""
            if [ "$NUM_VARIANTS" -gt 1 ]; then
                VARIANT_CTX="You are working on Variant $CURRENT_V of $NUM_VARIANTS ($V_PRESET). "
            fi

            EXIT_CODE=0
            if (cd "$V_DIR" && timeout "$TIMEOUT" claude \
                -p "${TIME_CTX}${VARIANT_CTX}${CREATIVE_TEXT}${BASE_RALPH_PROMPT}" \
                --dangerously-skip-permissions \
                --model "$MODEL" \
                --max-turns 100 \
                --output-format json \
                > "$ITER_LOG" 2>&1); then
                success "${VARIANT_LABEL}Ralph iteration $RALPH_ITER complete"
            else
                EXIT_CODE=$?
                if [ "$EXIT_CODE" = "124" ]; then
                    warn "${VARIANT_LABEL}Ralph iteration $RALPH_ITER timed out after ${TIMEOUT}s"
                else
                    warn "${VARIANT_LABEL}Ralph iteration $RALPH_ITER exited with code $EXIT_CODE"
                fi
            fi

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${VARIANT_LABEL}Cycle $CYCLE, Ralph iter $RALPH_ITER (exit: $EXIT_CODE)" >> "$ROOT_LOG_DIR/loop.log"

            set_status "${VARIANT_LABEL}Waiting between iterations..."

            if [ "$RALPH_ITER" -ge 50 ]; then
                warn "${VARIANT_LABEL}Ralph hit 50 iterations this cycle — forcing replan"
                break
            fi

            # Check total iteration limit
            if [ "$MAX_ITERS" != "0" ] && [ "$TOTAL_ITERS" -ge "$MAX_ITERS" ]; then
                log "Reached max iterations ($MAX_ITERS). Stopping gracefully."
                echo "STOP requested (iteration limit) at $(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_SIGNAL"
                break
            fi

            sleep "$INTERVAL"
        done

        # If stop signal came during Ralph, break out of variant loop to run polish
        if check_stop_signal; then
            break
        fi

        # ═══════════════════════════════════════
        # PHASE 2: REPLAN — Generate new plan for this variant
        # ═══════════════════════════════════════
        if [ "$NUM_VARIANTS" -gt 1 ]; then
            phase "═══ CYCLE $CYCLE — ${VARIANT_LABEL}PHASE 2: REPLAN (generating new plan) ═══"
        else
            phase "═══ CYCLE $CYCLE — PHASE 2: REPLAN (generating new plan) ═══"
        fi

        set_status "${VARIANT_LABEL}Pausing before replan..."
        log "${VARIANT_LABEL}Pausing ${REPLAN_PAUSE}s before replanning..."
        sleep "$REPLAN_PAUSE"

        set_status "${VARIANT_LABEL}Planning next cycle (cycle $CYCLE)"

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        REPLAN_LOG="$V_LOGS/replan_c${CYCLE}_${TIMESTAMP}.log"

        TIME_CTX=$(get_time_context)

        VARIANT_CTX=""
        if [ "$NUM_VARIANTS" -gt 1 ]; then
            VARIANT_CTX="You are working on Variant $CURRENT_V of $NUM_VARIANTS ($V_PRESET). "
        fi

        EXIT_CODE=0
        if (cd "$V_DIR" && timeout "$REPLAN_TIMEOUT" claude \
            -p "${TIME_CTX}${VARIANT_CTX}${CREATIVE_TEXT}${BASE_REPLAN_PROMPT}" \
            --dangerously-skip-permissions \
            --model "$MODEL" \
            --max-turns 100 \
            --output-format json \
            > "$REPLAN_LOG" 2>&1); then
            success "${VARIANT_LABEL}Replan complete — new plan generated for cycle $((CYCLE + 1))"
        else
            EXIT_CODE=$?
            if [ "$EXIT_CODE" = "124" ]; then
                warn "${VARIANT_LABEL}Replan timed out after ${REPLAN_TIMEOUT}s"
            else
                warn "${VARIANT_LABEL}Replan exited with code $EXIT_CODE"
            fi
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${VARIANT_LABEL}Cycle $CYCLE REPLAN (exit: $EXIT_CODE)" >> "$ROOT_LOG_DIR/loop.log"

    done  # end variant loop

    # If stop signal came during variant loop, run polish and exit
    if check_stop_signal; then
        set_status "Polishing and finalizing"
        stoplog "═══ GRACEFUL STOP — Running final polish ═══"
        run_polish_all
        rm -f "$STOP_SIGNAL"
        success "Polish complete. SuperTask™ finished gracefully."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] GRACEFUL STOP — polish complete" >> "$ROOT_LOG_DIR/loop.log"
        break
    fi

    # Check max cycles
    if [ "$MAX_CYCLES" != "0" ] && [ "$CYCLE" -ge "$MAX_CYCLES" ]; then
        log "Reached max cycles ($MAX_CYCLES). Stopping."
        break
    fi

    set_status "Cycle $CYCLE complete — starting next"
    success "Cycle $CYCLE complete. Starting cycle $((CYCLE + 1))..."
    echo ""
done
