# Spec Document Reviewer Prompt Template

Use this template when dispatching a spec document reviewer subagent.

**Purpose:** Verify the experiment design spec is complete, consistent, and ready for workflow planning.

**Dispatch after:** Spec document is written to docs/superscientist/specs/

```
Task tool (general-purpose):
  description: "Review experiment design spec document"
  prompt: |
    You are a spec document reviewer for computational science experiment designs. Verify this spec is complete and ready for workflow planning.

    **Spec to review:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | TODOs, placeholders, "TBD", incomplete sections |
    | Consistency | Internal contradictions, stages with mismatched inputs/outputs |
    | Clarity | Requirements ambiguous enough to cause a subagent to build the wrong thing |
    | Scope | Focused enough for a single workflow plan |
    | YAGNI | Unrequested features, over-engineering |
    | Parameter rationale | Every adjustable parameter has a stated reason — "standard practice" is fine, missing is not |
    | Method validation | Citation, benchmark result, or explicit validation stage for the method/algorithm choice |
    | Success criteria | Every stage criterion is specific and measurable — "converged" with no number is not acceptable |
    | Pitfall coverage | Every stage has identified failure modes with safeguards |
    | Stage decomposition | No monoliths, no micro-stages, expensive computation isolated, boundaries at natural verification points |
    | HPC verification | If remote backend: binary paths and packages marked verified (with date) or `[UNVERIFIED]` |

    ## Calibration

    **Only flag issues that would cause real problems during workflow planning.**
    A missing section, a contradiction, or a success criterion so vague it could never
    be checked — those are issues. Minor wording improvements, stylistic preferences,
    and "sections less detailed than others" are not.

    Approve unless there are serious gaps that would lead to a flawed workflow.

    ## Output Format

    ## Spec Review

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Section X]: [specific issue] - [why it matters for workflow planning]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Reviewer returns:** Status, Issues (if any), Recommendations
