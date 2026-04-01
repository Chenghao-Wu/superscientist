---
name: systematic-debugging
description: Use when any workflow stage fails — simulation, analysis, plotting, post-processing, or environment setup — before proposing fixes
---

# Systematic Debugging

## Overview

Random fixes waste time. Investigate root cause first.

**Core principle:** ALWAYS find root cause before attempting fixes.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

## Phase 1: Gather Evidence

1. **Read error output** — Read the failed stage's output and error files completely. Don't skip.
2. **Read progress.log** — What was attempted? What happened before the failure?
3. **Read stage spec** — What was this stage supposed to do? What are the inputs, parameters, success criteria?
4. **Reproduce** — Can you trigger the failure again with the same inputs?

## Phase 2: Diagnose Failure Category

| Category | Symptoms | Common Causes |
|---|---|---|
| **Input error** | Missing files, wrong format, bad parameters | Typo in paths, wrong output from prior stage |
| **Convergence failure** | SCF not converging, geometry stuck | Bad initial guess, too tight criteria, wrong method |
| **Numerical instability** | NaN energies, exploding forces, negative T | Too-large timestep, overlapping atoms, bad geometry |
| **Resource limit** | OOM, timeout, disk full | System too large, too many k-points, long trajectory |
| **Wrong results** | Converged but physically wrong answer | Wrong functional, missing dispersion, bad pseudopotential |
| **Analysis/plotting error** | Missing data, wrong column, library issue | Wrong file format, missing dependency, encoding |
| **Environment issue** | Missing binary, wrong version, import error | Wrong conda env, missing package, version mismatch |
| **Dependency conflict** | Software missing feature, incompatible libs | LAMMPS missing package, VASP without SOC, wrong MPI |

## Phase 3: Hypothesis and Test

1. **Form single hypothesis** — "I think X is the root cause because Y"
2. **Test minimally** — Smallest possible change. One variable at a time.
3. **Verify** — Did it work? Yes → Phase 4. No → new hypothesis.
4. **If 3+ fixes failed** — STOP. Question whether the approach is fundamentally wrong. Discuss with user before continuing.

## Phase 4: Fix and Retry

1. Apply the fix
2. Update `progress.log` with diagnosis and fix applied
3. Never remove the failed attempt from the log — append the retry
4. Retry the stage via `superscientist:executing-workflows`
5. `retry_count` is incremented in `workflow-state.json`

## Wrong Results: The Hardest Category

When the calculation converges and files look correct, but the answer is physically wrong:

1. Check against known reference values (published data, databases)
2. Check physical bounds (positive bulk modulus, band gap in expected range)
3. Check internal consistency (forces match energy surface, equation of state makes sense)
4. If no reference exists — propose a validation calculation against a well-known system as a new stage (via amendment protocol)

## Red Flags

| Thought | Reality |
|---------|---------|
| "I know what's wrong" | Investigate first. You might be wrong. |
| "Quick fix, let me try" | Root cause first. Phase 1 → 2 → 3 → 4. |
| "Let me try one more fix" (after 2+) | Stop. Question the approach. Talk to user. |
| "Results look close enough" | Check against reference. "Close" might be wrong. |
