# Quick task 261002-7wk: Correct response-format failure

Gathered: 2026-10-02
Status: Ready for planning

## Task boundary

DATA_START
Correct produces: malformed response: expected the "FORMAL:" tag at the start of a line, found "W".
DATA_END

## Decisions and assumptions

- Restore the existing CAP-4 three-variant correction flow while retaining real streaming, cancellation, statelessness, and inline failures.
- User confirmed OpenRouter / OpenAI-compatible with the default prompt and model nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free.
- User selected automatic app-enforced response-format instructions. Preserve their editable grammar prompt and append protocol requirements in the tagged adapters.
- Optional questions were initially unanswered and work began under a stated assumption; the later explicit answers confirm format enforcement and narrow the transport investigation to OpenRouter reasoning.
- OpenRouter requests disable optional thinking and exclude reasoning output using the documented gateway controls. Other compatible hosts receive neither vendor field. Decoder continues to ignore separate reasoning fields.
- Preserve the exact saved grammar prompt and its paired model. Add protocol instructions only in the two tagged provider adapters; neither the domain port nor the history shape changes.
- Keep strict parsing: plain prose, missing variants, and truncated responses remain failures. Do not invent variants, discard arbitrary prose, or switch providers.
- No live provider credentials or user draft are needed. Automated reproduction uses a request-aware loopback fixture and a sidecar stub.

## Canonical references

- SPEC.md: CAP-3, CAP-4, CAP-5, CAP-8, CAP-13.
- llm-provider-contract.md: prompt/model pairing, structured response, one provider, stateless sessions.
- ARCHITECTURE-SPINE.md: AD-16 tagged format belongs to the adapter; AD-19 sidecar boundary.
- AGENTS.md and PLAN.md.

Research, planning, plan checking, implementation, review, and verification run inline under the gsd-quick adapter's no-automatic-spawn rule.
