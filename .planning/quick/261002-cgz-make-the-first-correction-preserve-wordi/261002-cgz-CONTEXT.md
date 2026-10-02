# Quick Task 261002-cgz — Suggestion order and tone

**Gathered:** 2026-10-02
**Status:** Ready for planning
**Execution:** Inline per the gsd-quick Codex spawn restriction.

<domain>
## Task Boundary

Make suggestion 1 preserve the original wording and tone, fixing grammar and unnatural English; suggestion 2 casual; suggestion 3 short.
</domain>

<decisions>
## Implementation Decisions

- The user's explicit request fixes the three behaviors and their order.
- User confirmed “All clear—use that behavior and those labels” in the full-mode discussion.
- The first correction changes only what grammar and native phrasing require. Already-correct natural wording stays unchanged.
- Casual and short variants preserve the same intended meaning.
- Apply the behaviors to both shipped adapters, including existing configured prompts.
- Retain persisted register identifiers, parser tags, enum order, preset IDs, and prompt filenames for compatibility.

### Labels and Compatibility

- Confirmed display labels: Corrected, Casual, Short.
- Use existing shared prompt composition rather than a new format or schema migration.
</decisions>

<canonical_refs>
## Canonical References

- AGENTS.md, PLAN.md, SPEC.md CAP-4/CAP-5/CAP-7/CAP-8/CAP-9/CAP-11.
- The explicit request supersedes CAP-4's old formal-first wording and the output-quality-tuning non-goal for this narrow task. Generated SPEC.md and its companions are not hand-edited.
</canonical_refs>
