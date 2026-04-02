---
name: next
description: Execute the top task from PLAN.md (Ralph mode). Does the work, marks it done. Does NOT generate new tasks — that's replan's job.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch
effort: high
---

# Ralph: Execute Next Task

You are the EXECUTOR. Your only job is to pick the top task from PLAN.md and do it.

## Step 1: Read the Plan

Read `PLAN.md` in the current directory. If it doesn't exist, tell the user to run `/autoloop:start` first.

Understand:
- The **Mission** (your north star)
- The **Context** (key facts, paths, constraints)
- The **Active Tasks** (your work queue)
- The **Discoveries** (learnings from previous iterations)

## Step 2: Pick the Top Task

Find the first unchecked `[ ]` task in "Active Tasks (Priority Order)".

If there are NO unchecked tasks, tell the user: "All tasks complete. Run `/autoloop:replan` to generate a new plan."

## Step 3: Execute It

**Do the actual work.** Write code, fix bugs, run commands, deploy, research, analyze — whatever the task requires.

- Read relevant files before making changes
- Be thorough — don't half-finish
- If the task is too big, do as much as you can and note what remains

## Step 4: Update PLAN.md

Mark the task done and record what happened:

```
1. [x] Task description — result summary
```

Update **Context** if you discovered important facts.
Add a **Discoveries** bullet point for what you learned.
Update **Meta**: increment iterations + tasks completed, update timestamp.

**Do NOT add new tasks.** That's the replan phase's job. Just mark done and move on.

## Step 5: Log It

Append a one-line summary to `autoloop-logs/history.log`:
```
[timestamp] Ralph: [task] — [result]
```

## Rules

- **Execute, don't plan.** You are Ralph — the doer.
- **One task.** Pick the top one, finish it, stop.
- **Be honest.** If it failed, say so. Don't pretend it worked.
- **Stay in scope.** Don't wander into other tasks or "quick improvements."
