---
name: using-superscientist
description: Use when starting any conversation in a computational science project — establishes harness awareness and checks for existing workflow state
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific workflow stage, skip this skill.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a superscientist skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.
</EXTREMELY-IMPORTANT>

# Using Superscientist

## Session Start Protocol

**Before any other work:**

1. Check for `workflow-state.json` in the working directory
   - If found: invoke `superscientist:session-resume` immediately
   - If not found: proceed normally; skills are available on demand

## Available Skills

| Skill | When to invoke |
|---|---|
| `superscientist:checkpoint-management` | Creating, reading, or updating workflow-state.json, progress.log, init.sh |
| `superscientist:session-resume` | Starting a new session when workflow-state.json exists |
| `superscientist:experiment-design` | User wants to set up a new computational experiment |
| `superscientist:workflow-planning` | Experiment design is approved, needs stage-by-stage plan |
| `superscientist:executing-workflows` | Workflow plan exists and stages need execution |
| `superscientist:compute-backend` | Subagent needs to submit a computation to local or HPC backend via DPDispatcher |
| `superscientist:systematic-debugging` | Any workflow stage fails — simulation, analysis, plotting, environment |
| `superscientist:result-verification` | Before marking any stage as completed |
| `superscientist:workflow-completion` | All workflow stages are completed and verified |

## Workflow Chain

```
experiment-design → workflow-planning → executing-workflows → workflow-completion
                                              ↓ (on failure)
                                       systematic-debugging
                                              ↓ (retry)
                                       executing-workflows
```

Cross-session recovery: `session-resume` at every session start when workflow exists.

## The Rule

Invoke relevant skills BEFORE any response or action. Even a 1% chance a skill might apply means invoke it.

## Red Flags

| Thought | Reality |
|---------|---------|
| "Let me just run this calculation quickly" | Invoke experiment-design first. |
| "I'll check the results later" | Invoke result-verification now. |
| "This stage looks done" | Invoke result-verification before marking complete. |
| "I know what went wrong" | Invoke systematic-debugging — investigate before fixing. |
| "I'll remember where we left off" | workflow-state.json remembers. Invoke session-resume. |
