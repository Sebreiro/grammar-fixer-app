# Focused research: required correction response format

## Findings

- RegisterTaggedStreamParser fails as soon as a character cannot start the expected tag. A first content chunk beginning with W reproduces the reported error; it is not evidence of the remainder of the model response.
- Both OpenAiCompatibleCorrectionProvider._requestBody and ClaudeAgentSdkCorrectionProvider.correct forward preset.systemPrompt unchanged. The parser requires FORMAL:, CASUAL:, SHORTER:, END regardless of editable prompt content.
- The shipped prompt already requests this format, so changing only the shipped defaults would not repair existing/custom prompts. JsonConfigStore deliberately preserves saved prompt contents. Add a shared pure formatter at the adapter boundary and leave persisted prompts alone.
- AD-16 explicitly makes tagged formatting an adapter concern. Domain Preset still carries the user's prompt and model together; structured CorrectionEvents and stored Suggestions remain untouched.
- ChatCompletionSseDecoder forwards only delta.content. Separate reasoning/reasoning_content fields must remain ignored; add regression evidence without changing transport behavior speculatively.
- OpenRouter's official reasoning docs confirm reasoning is separate from response content, and excluding it does not remove its token-budget cost: https://openrouter.ai/docs/guides/best-practices/reasoning-tokens . The reported W alone cannot establish a reasoning-specific defect.
- Later user clarification identified nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free. Its official model page explicitly supports extended thinking via reasoning.enabled: https://openrouter.ai/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free . Disable optional thinking and set reasoning.exclude=true only for the exact openrouter.ai host. This addresses answer-channel compatibility and the existing 512-token budget without choosing a different model, expanding the provider port, or stripping arbitrary prose.

## Implementation

Use RegisterTaggedPrompt under infrastructure/correction/shared. Preserve the full original prompt as a prefix and append explicit four-line protocol instructions referencing the parser's END constant. Apply identically at both tagged adapters. Keep shipped defaults unchanged, update Settings help and README, and verify request payloads against a loopback server and actual sidecar stdin.

## Baseline

- 44 focused parser/default/config-prompt-flow tests pass.
- dart analyze --fatal-infos passes.
- Prior prompt task completed during inspection; current working tree is clean. Do not modify its artifacts.

## Limits

The actual provider/model is known, but the full failing response has not been supplied. Request contract tests prove the missing-format path, model-specific request mapping, and boundary wiring; they cannot guarantee compliance by every live model or establish the exact contents after the first W.

## Later live finding: OpenRouter usage frames

The user-requested mistralai/ministral-8b-2512 probe streamed all three registers but failed at transport completion. Curl with the exact request builder payload returned valid tags and DONE, with two content-free stop frames: the second carried usage. OpenRouter's [official streaming reference](https://openrouter.ai/docs/api_reference/streaming) explicitly documents this repeated finish reason in the final accounting frame. ChatCompletionSseDecoder's unconditional duplicate-stop rejection is therefore a confirmed wire-decoding defect, distinct from the original W report. Allow that frame only when usage is an object and no content follows the stop; preserve the required DONE marker, response bounds, domain event shape, and strict tagged parser.
