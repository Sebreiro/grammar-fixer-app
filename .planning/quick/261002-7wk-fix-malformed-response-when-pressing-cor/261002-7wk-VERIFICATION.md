---
quick_id: 261002-7wk
status: human_needed
verified: 2026-10-02
verification_mode: inline
nvidia_live_status: failed
deepseek_live_status: timed_out
deepseek_curl_status: timed_out_no_response
gemma_openrouter_live_status: rate_limited
ministral_openrouter_live_status: passed
ministral_decoder_fix: 466be28
---

# Goal verification

All automated must-haves passed against source commits 322f65b and 07f14ed. The later supplied NVIDIA Riva model failed the live correction check; authentication and streaming passed. The subsequently requested NVIDIA DeepSeek model timed out twice without suggestion text. The requested OpenRouter Gemma model returned HTTP 429 in both attempts, with the upstream shared pool identified as the rate-limit source. The original OpenRouter Nemotron model still requires one runtime retest.

The later requested OpenRouter Ministral model passed a live correction through the actual adapter after decoder repair 466be28. The initial attempt exposed rejection of OpenRouter's documented final usage frame; a raw curl capture and failing regressions confirmed that separate transport defect. Updated source accepts the content-free accounting frame while retaining invalid/truncated response rejection.

| Must-have | Evidence | Result |
|---|---|---|
| Tagged adapters always request the required format | RegisterTaggedPrompt, HTTP request captures, sidecar stdin regression | Passed |
| Edited grammar instructions and paired model reach the next correction | Config file/Settings HTTP integration; whitespace preservation unit test | Passed |
| Default prompt with the selected Nemotron model has explicit tag and thinking controls | ChatCompletionRequest exact-host/default-prompt/model regression | Passed |
| Gateway-specific fields remain at the OpenRouter edge | OpenAI, loopback, lookalike host, and URL-path negative cases | Passed |
| Reasoning never renders as suggestions when separately streamed | Decoder reasoning/reasoning_content/reasoning_details regression; HTTP integration | Passed |
| Genuine suggestion text streams before completion | Held-open server waits for a SuggestionDelta before sending the remaining lines | Passed |
| Untagged W response and incomplete responses remain inline failures | Exact error regression; unchanged parser, truncation, retry, and lifecycle suites | Passed |
| OpenRouter's final usage frame does not invalidate a completed correction | Decoder and held-open loopback regressions; Ministral live CorrectionCompleted after 17 deltas | Passed |

Validation: 161 focused tests; 1,144 broad Dart tests (2 skips); 210 Flutter tests (7 skips); clean analyzer, formatting, and whitespace checks. No native UI or parser timing change was needed.

## Human check

Rebuild and restart the app with this source, keep nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free selected in OpenRouter Settings, enter a short grammar correction, and press Correct. Confirm three labeled suggestions stream without the FORMAL/W error. No prompt-file edit should be necessary. The original OpenRouter check remains unobserved; the later user-supplied NVIDIA credential targets a different endpoint/model and was used only there.

The original failure's full model content was not captured. Thinking leaking into the answer or ordinary format noncompliance remains an inference rather than a proven root cause. The code repair and request mapping are verified independently of that inference.

## Subsequent live check: supplied NVIDIA endpoint

The real correction adapter failed with expected FORMAL: / found J and no suggestion deltas. A full probe of the actual request returned HTTP 200 and `Jeg har ätit äpple igår` across 10 content chunks, with valid stop and DONE. A documented en-fr translation control returned HTTP 200 and `Je suis allé au magasin hier.` across 7 content chunks, also with valid stop and DONE. Therefore the supplied Riva translation model did not satisfy the correction format; the credential and SSE transport worked.

Detailed, credential-free evidence: [LIVE-CHECK.md](./261002-7wk-LIVE-CHECK.md). App settings and production code were unchanged. Overall status remains human_needed for the original OpenRouter/Nemotron retest; the supplied NVIDIA correction result is explicitly failed.

## Follow-up live check: DeepSeek V4.1 Flash on NVIDIA

Tested deepseek-ai/deepseek-v4.1-flash through the actual correction adapter, using the same supplied NVIDIA credential and endpoint, the shipped prompt plus enforced tags, and one synthetic sentence. Both attempts hit the app's default 60-second deadline after 60,018 ms, with zero SuggestionDelta events and CorrectionFailed(timeout). No successful completion, suggestion text, or HTTP status was observed. The timeout path worked; live grammar-format compatibility remains unverified. No production code or config changed. Exact observations are recorded in LIVE-CHECK.md.

## Direct curl control

Using the exact ChatCompletionRequest-generated payload, a direct curl request with a 180-second maximum also failed: exit 28, total 180.001963 seconds, zero bytes, no HTTP status, and no SSE frames. The absence of a response is reproduced outside Flutter. The model remains unverified for correction format; no server-side cause is inferred from the timeout alone. Credential-free payload and curl reproduction are saved with the live-check evidence.

## Follow-up live check: Gemma 4 on OpenRouter

Tested google/gemma-4-26b-a4b-it:free through the actual adapter with the newly supplied OpenRouter credential, the same prompts and synthetic sentence, and current OpenRouter request settings. Both the initial request (435 ms) and one manual retry (316 ms) returned HTTP 429, zero suggestion deltas, and CorrectionFailed(providerError). The provider response explicitly identified Google AI Studio's upstream shared pool as temporarily rate-limited. No model output arrived; grammar-format compliance remains unverified. Neither production code nor app settings changed. The original Nemotron incident remains pending independently of this Gemma availability check.

## Follow-up live check: Ministral 8B on OpenRouter

Initial real-adapter check streamed 17 suggestion deltas before a modeled invalid-stream failure at 979 ms. Direct curl using the exact request returned HTTP 200 and all required tags, followed by a stop frame, a content-free usage frame repeating stop, and DONE. OpenRouter documents this accounting shape. The decoder was rejecting the repeated stop; the new pure and loopback regression both failed before repair.

Commit 466be28 allows a content-free repeated stop only with a usage object. The focused provider, prompt, and config/HTTP integration run passed 41 tests, including rejection of generic duplicate stops, late content, changed finish reasons, invalid usage metadata, missing DONE, malformed tags, and existing cancellation/timeout cases. dart analyze --fatal-infos, formatting, and git diff --check passed.

The subsequent actual Ministral request completed after 733 ms with 17 deltas across formal/casual/shorter and first partial at 519 ms. Suggestions: `I had an apple yesterday.`, `I ate an apple yesterday.`, `I ate one yesterday.`. This is a successful live check of the requested model with current source. User config and credentials were not saved or changed; a rebuild/restart is required to load the source repair. Overall original-model verification remains human_needed for Nemotron, whose model output was not observed.
