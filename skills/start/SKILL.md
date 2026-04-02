---
name: start
description: Initialize a SuperTask session — create PLAN.md with a seed mission and initial tasks. Use this to begin a new autonomous loop.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: <mission description>
---

# SuperTask: Initialize

The user wants to start a new autonomous loop. Their mission: "$ARGUMENTS"

## Your job:

1. **Check if PLAN.md already exists** in the current directory.
   - If it exists, read it and ask the user if they want to overwrite or append to it.
   - If it doesn't exist, create it fresh.

2. **Create PLAN.md** using this exact structure:

```markdown
# Autonomous Plan

## Mission
[The user's mission from $ARGUMENTS — write it as a clear, actionable objective]

## Context
[Scan the current directory. Read any CLAUDE.md, README.md, or key config files. Write 5-15 bullet points of key facts: project structure, important file paths, tech stack, constraints, credentials, anything Claude needs to know in future iterations.]

## Active Tasks (Priority Order)
[Generate 5-8 concrete, actionable tasks based on the mission. Each should be completable in ~30 minutes. Be specific — not "improve X" but "analyze X and implement Y based on findings".]
1. [ ] First task
2. [ ] Second task
3. [ ] Third task
4. [ ] Fourth task
5. [ ] Fifth task

## Completed
(none yet)

## Discoveries
(none yet)

## Meta
- Iterations: 0
- Tasks completed: 0
- Last updated: [current timestamp]
- Mission started: [current timestamp]
```

3. **Create the `autoloop-logs/` directory** if it doesn't exist.

4. **Tell the user** how to run the loop:

   **Interactive (one iteration at a time):**
   ```
   /autoloop:next
   ```

   **Autonomous (runs forever):**
   ```
   bash ~/.claude/plugins/autoloop/scripts/loop.sh
   ```

   **In tmux (persistent, survives terminal close):**
   ```
   tmux new-session -d -s autoloop 'bash ~/.claude/plugins/autoloop/scripts/loop.sh'
   ```

5. **Do the actual context-gathering work.** Read project files, understand the codebase, write thorough Context and Tasks sections. Don't be lazy — the quality of this initial plan determines how well the loop runs.
