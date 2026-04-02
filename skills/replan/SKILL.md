---
name: replan
description: Generate a new plan after Ralph finishes all tasks. Reviews what was accomplished, creates fresh tasks, evolves the strategy. This is the brain of the loop.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch
effort: high
---

# Replan: Generate the Next Plan

Ralph has finished executing all the tasks. You are the STRATEGIC PLANNER. Review what happened and generate a brand new plan.

## Step 1: Read Everything

Read these files:
1. **PLAN.md** — the current plan with completed tasks, context, discoveries
2. **autoloop-logs/history.log** — the execution history
3. **autoloop-logs/latest.md** — the most recent iteration details (if exists)

Understand: what was the mission, what was accomplished, what was discovered, what failed.

## Step 2: Reflect

Before writing the new plan, think about:
- What moved the Mission forward the most?
- What failed and needs a different approach?
- What new opportunities emerged from discoveries?
- Are there diminishing returns in any area? Should focus shift?
- What's the highest-leverage work for the next cycle?
- Is there anything being neglected that could become a problem?

## Step 3: Rewrite PLAN.md

Generate a completely fresh plan. Keep the structure, evolve the content:

### Mission
Keep the original mission unchanged.

### Context
- Keep all existing context that's still true
- Add new facts from the completed work
- Remove anything outdated or wrong
- This section should grow over time — it's institutional memory

### Active Tasks (Priority Order)
Generate **5-10 NEW tasks**. These must be:
- **Novel** — not repeats of already-completed tasks
- **Specific** — "implement X in file Y based on finding Z" not "improve things"
- **Actionable** — completable in one Ralph iteration (~30 min)
- **Prioritized** — most impactful first
- **Diverse** — mix of building, testing, researching, monitoring
- Include at least 1 **research/exploration** task to find new opportunities

### Completed
Add a cycle summary line:
```
- Cycle N complete: [1-sentence summary of what the whole cycle accomplished]
```
Keep the last 20 completed items. Archive older ones or remove them.

### Discoveries
Keep ALL discoveries — this is the system's long-term memory.
Add a cycle-level insight about what worked and what didn't.

### Meta
- Increment "Cycles" by 1
- Keep running totals for iterations and tasks completed
- Update "Last replanned" timestamp

## Step 4: Write Replan Log

Write a summary to `autoloop-logs/replan_N.md` (where N is the cycle number):

```markdown
# Replan — Cycle N → Cycle N+1

## What Was Accomplished
[Summary of completed tasks and their results]

## Key Discoveries
[Most important findings from this cycle]

## Strategic Shifts
[What's changing in the new plan and why]

## New Plan Summary
[List the new tasks and the reasoning behind the priority order]
```

## Step 5: Clean Up

Delete `autoloop-logs/ralph_signal.txt` if it exists (this signals Ralph that a new cycle can begin).

## Rules

- **Think strategically.** You are the brain, not the hands.
- **Be ambitious but realistic.** Each task should be achievable in ~30 minutes.
- **Don't repeat work.** Check Completed before generating tasks.
- **Evolve the approach.** If something failed twice, try a different angle.
- **Never leave Active Tasks empty.** There is always more to do.
- **The plan must serve the Mission.** Every task should connect back to it.
