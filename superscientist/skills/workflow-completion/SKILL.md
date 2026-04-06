---
name: workflow-completion
description: Use when all workflow stages are completed and verified — generates summary report, archives results, and commits
---

# Workflow Completion

## Overview

Wrap up a completed workflow with a summary report and clean archival.

**Core principle:** A workflow is not done until it's documented and committed.

## Process

### Step 1: Verify All Stages Completed

Read `workflow-state.json`. Every stage must have `status: "completed"` (or `skipped`). If any stage is not completed, do NOT proceed — invoke `superscientist:executing-workflows` instead.

### Step 2: Generate Summary Report

Save to `docs/superscientist/reports/YYYY-MM-DD-<topic>-report.md`:

```markdown
# [Topic] Workflow Report

**Workflow ID:** [workflow_id]
**Completed:** [timestamp]
**Total sessions:** [count from progress.log]
**Amendments:** [count]

## Objective
[From experiment design doc]

## Results Summary

### Stage N: [Name]
- **Status:** completed
- **Key result:** [1-2 sentence summary of output]
- **Output files:** [paths]

## Issues Encountered
[Any failed stages, retries, amendments — summarized from progress.log]

## Key Outputs
[List of final deliverables with paths]
```

### Step 3: Update `workflow-state.json`

Add top-level field: `"workflow_status": "completed"` and update `"updated"` timestamp.

### Step 4: Final Log Entry

Append to `progress.log` via Bash tool:
```bash
echo "[$(date -Iseconds)] Workflow completed. All N stages verified. Report: docs/superscientist/reports/..." >> progress.log
```

### Step 5: Commit

```bash
git add workflow-state.json progress.log docs/superscientist/reports/
git commit -m "feat: complete workflow <workflow_id>"
```

### Step 6: Announce

Tell the user: workflow is complete, where to find the report, and list the key output files.
