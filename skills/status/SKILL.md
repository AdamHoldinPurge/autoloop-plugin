---
name: status
description: Check the current state of the SuperTask session — how many tasks done, what's active, iteration count, last update.
user-invocable: true
allowed-tools: Read, Glob
---

# SuperTask: Status Check

Read `PLAN.md` in the current directory and provide a concise status report:

1. **Mission** — one line
2. **Iterations completed** — from Meta section
3. **Tasks completed** — count of `[x]` items
4. **Active tasks** — count and list the top 3
5. **Last updated** — from Meta section
6. **Recent discoveries** — last 3 bullet points from Discoveries
7. **Health check:**
   - Is Active Tasks non-empty? (should always be)
   - Is the plan well-structured? (all sections present?)
   - Are tasks specific and actionable? (not vague?)

If PLAN.md doesn't exist, tell the user to run `/autoloop:start` first.

Also check if `autoloop-logs/latest.md` exists and show the last iteration summary.
