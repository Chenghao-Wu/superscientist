---
name: result-verification
description: Use before marking any workflow stage as completed — verify outputs exist, are valid, and meet success criteria defined in workflow-state.json
---

# Result Verification

## Overview

Claiming a stage is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO STAGE MARKED COMPLETED WITHOUT PASSING VERIFICATION
```

If verification fails, the stage is marked `failed` and `superscientist:systematic-debugging` is invoked.

## The Verification Checklist

You MUST complete every check. A single failure = stage is `failed`.

### 1. Output Files Exist and Are Non-Empty

```bash
# For each expected output in workflow-state.json stage.outputs:
test -s "$output_file" || echo "FAIL: $output_file missing or empty"
```

### 2. Output Files Are Parseable

- Try to read/parse the output files
- Check for truncation (incomplete last line, missing footer)
- Check for corruption (binary garbage in text files)

### 3. Success Criteria Met

Read the `success_criteria` from `workflow-state.json` for this stage. Check each criterion against actual output:

| Criterion type | How to verify |
|---|---|
| Convergence metric | Parse output, check final value meets threshold from success_criteria |
| Numerical result | Extract value, compare against target or reference |
| Output file produced | Check file exists, non-empty, and in expected format |
| Visualization | Check image file valid, non-zero size, expected content present |
| Script/process completion | Check exit code is 0 and no fatal errors in logs |

### 4. Sanity Checks

Domain-specific reasonableness checks (derive from experiment design):
- Output values within physically/mathematically reasonable ranges?
- No obviously unphysical values (NaN, infinite, negative where impossible)?
- Results consistent with prior stages or known references?
- For plots: axes labeled, data present, no obvious artifacts?

### 5. No Silent Failures

Check log/output files for:
- Warning messages that indicate problems
- Error messages that were caught but indicate incomplete results
- "WARN", "ERROR", "WARNING", "FAILED" in log files

## Reporting

After verification, report:

**If passed:**
```
Verification PASSED for stage-N ([name]):
- All N output files present and non-empty
- Success criteria met: [specific evidence]
- Sanity checks passed: [brief summary]
→ Marking stage as completed.
```

**If failed:**
```
Verification FAILED for stage-N ([name]):
- Failed check: [which check failed]
- Evidence: [what was found]
- Expected: [what was expected]
→ Marking stage as failed. Invoking systematic-debugging.
```

## Red Flags

| Thought | Reality |
|---------|---------|
| "Output file exists, good enough" | Check it's non-empty and parseable too. |
| "Calculation converged, must be right" | Check the answer is physically reasonable. |
| "No errors in the log" | Check for warnings too. |
| "I'll verify the next stage instead" | Every stage gets verified. No shortcuts. |
| "Results look reasonable" | Compare against success criteria, not intuition. |
