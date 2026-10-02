---
quick_id: 261002-7wk
checked: 2026-10-02
status: mixed
models:
  - nvidia/riva-translate-4b-instruct-v2
  - deepseek-ai/deepseek-v4.1-flash
  - google/gemma-4-26b-a4b-it:free
  - mistralai/ministral-8b-2512
endpoints:
  - https://integrate.api.nvidia.com/v1
  - https://openrouter.ai/api/v1
gemma_openrouter_status: rate_limited
ministral_openrouter_status: passed_after_decoder_fix
---

# Live provider verification

The user explicitly supplied a NVIDIA credential, model, and endpoint for the initial live check. The key was passed through terminal stdin with echo disabled, kept in process memory, and never written to code, config, artifacts, or logs. The initial three requests used synthetic text and the supplied NVIDIA endpoint. No fallback or app-settings mutation was performed. Later probes tested additional models only at the user's request.

## Observations

| Probe | Request | Observed result |
|---|---|---|
| Actual OpenAiCompatibleCorrectionProvider | Shipped grammar prompt plus RegisterTaggedPrompt; input `i has a apple yesterday`; configured Riva model | 0 suggestion deltas; CorrectionFailed(malformedResponse): expected FORMAL: at the start of a line, found J; 321 ms |
| Full response using actual ChatCompletionRequest mapping | Same prompt, model, and synthetic input; observed complete stream before parsing | HTTP 200, text/event-stream, 10 content chunks; response `Jeg har ätit äpple igår`; stop and DONE validated; 571 ms |
| Documented translation control | System prompt `en-fr`; input `I went to the store yesterday.`; same model and endpoint | HTTP 200, text/event-stream, 7 content chunks; response `Je suis allé au magasin hier.`; stop and DONE validated; 355 ms |

## Result

Authentication and streaming passed against the supplied endpoint. The model did not honor the required three-register correction format even with the appended protocol instructions. The actual adapter correctly rejected the untagged response rather than displaying or persisting invented suggestions.

NVIDIA describes Riva-Translate as a translation model and documents language-pair system prompts such as en-fr/en-zh-cn. The observed behavior is consistent with that specialization. [NVIDIA model card](https://build.nvidia.com/nvidia/riva-translate-4b-instruct-v2/modelcard), [NVIDIA inference reference](https://docs.api.nvidia.com/nim/re/reference/nvidia-riva-translate-4b-instruct-v2-infer).

This is a failed live correction check for the supplied Riva model. It does not verify the original OpenRouter nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free incident or its gateway-only reasoning controls: the NVIDIA key was used solely on the NVIDIA endpoint. No production code changed as a result of these probes.

## Follow-up: DeepSeek V4.1 Flash

The user explicitly requested deepseek-ai/deepseek-v4.1-flash on the same NVIDIA endpoint. Reused the supplied key through hidden stdin and tested the actual OpenAiCompatibleCorrectionProvider with the shipped grammar prompt, appended tagged format, input `i has a apple yesterday`, and the existing 60-second timeout. No NVIDIA-specific thinking override or larger token budget was added; this reflects the app's current request mapping.

| Attempt | Suggestion deltas | First suggestion | Terminal | Elapsed |
|---|---|---|---|---|
| Initial request | 0 | None | CorrectionFailed(timeout): The provider took too long. Retry the correction. | 60,018 ms |
| One manual retry, same model/settings | 0 | None | Same timeout failure | 60,018 ms |

Result: live correction did not complete under current app settings. No completed response, suggestion text, or HTTP status was observed by the probe. This does not establish whether the model can obey the required register tags, nor whether queueing, model generation, or connection delay caused the timeout. The real adapter produced a modeled timeout instead of hanging indefinitely.

NVIDIA's [inference reference](https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer) documents this exact model ID and endpoint, but its availability in two timed-out requests is not a successful integration claim. The original OpenRouter/Nemotron live check remains pending. No production source or app settings changed; the temporary credential-free probe script was removed after recording results.

## Follow-up: direct curl with the exact app prompts

The user requested a curl test using the same prompts. Generated the JSON payload directly with ChatCompletionRequest.encode and DefaultAppConfig.shippedSystemPrompt, preserving the appended RegisterTaggedPrompt instructions. Model, synthetic input, stream=true, temperature=0.2, n=1, and max_tokens=512 match the prior adapter attempts. The sole diagnostic change was a 180-second curl deadline instead of the app's 60 seconds. Curl used HTTP/1.1, application/json and text/event-stream headers, and the same NVIDIA endpoint/key. Authorization was supplied via curl's stdin config, not arguments or disk.

Observed: curl exit 28 after 180.001963 seconds; zero response bytes; zero HTTP response headers, content chunks, or SSE frames; no finish reason or DONE. Curl's reported HTTP code 000 means no HTTP response status was received, not a server status code. Error: `Operation timed out after 180001 milliseconds with 0 bytes received`.

This reproduces the timeout independently of Flutter and the correction adapter. It does not identify the remote-side cause or establish model output compatibility, because no response arrived.

Saved exact credential-free payload: [CURL-REQUEST.json](./261002-7wk-CURL-REQUEST.json). To reproduce from bash, enter the NVIDIA key interactively and use this payload:

```bash
read -r -s -p 'NVIDIA API key: ' nvidia_api_key
printf '\n'
printf 'header = "Authorization: Bearer %s"\n' "$nvidia_api_key" |
  curl --config - --silent --show-error --no-buffer --http1.1 \
    --include --connect-timeout 20 --max-time 180 \
    --request POST 'https://integrate.api.nvidia.com/v1/chat/completions' \
    --header 'Content-Type: application/json' \
    --header 'Accept: text/event-stream' \
    --data-binary '@.planning/quick/261002-7wk-fix-malformed-response-when-pressing-cor/261002-7wk-CURL-REQUEST.json' \
    --write-out '\nHTTP %{http_code}; first byte %{time_starttransfer}s; total %{time_total}s; bytes %{size_download}\n'
unset nvidia_api_key
```

## Follow-up: Gemma 4 on OpenRouter

The user requested google/gemma-4-26b-a4b-it:free and supplied an OpenRouter credential. Tested the actual OpenAiCompatibleCorrectionProvider against https://openrouter.ai/api/v1 using the shipped grammar prompt, appended tagged response format, and synthetic input `i has a apple yesterday`. The request retained the app's stream=true, temperature=0.2, n=1, max_tokens=512, and OpenRouter reasoning.enabled=false / reasoning.exclude=true settings. The OpenRouter key was passed through hidden stdin, used only on OpenRouter, and never saved.

| Attempt | HTTP status | Suggestion deltas | Terminal | Elapsed |
|---|---|---|---|---|
| Initial request | 429 | 0 | CorrectionFailed(providerError) | 435 ms |
| One manual retry, same model/settings | 429 | 0 | CorrectionFailed(providerError) | 316 ms |

Both error responses identified Google AI Studio as the upstream provider and upstream_provider_shared_pool as the limit source. OpenRouter reported that the selected free Gemma model was temporarily rate-limited upstream. The adapter rendered its modeled HTTP 429 failure. Neither request returned model text or a successful completion, so tag-format compatibility remains unverified. This observed limit is separate from the original malformed FORMAL/W response.

No production source or user config changed. The temporary credential-free probe was removed after recording the results. The original OpenRouter/Nemotron model was not tested with this credential; the requested Gemma model was used for both attempts.

## Follow-up: Ministral 8B on OpenRouter

The user requested mistralai/ministral-8b-2512 on OpenRouter. Reused the authorized OpenRouter key through hidden stdin. Each request used the same shipped grammar prompt, appended response-format instructions, synthetic sentence `i has a apple yesterday`, and existing generation settings. No app-settings change or model fallback was performed.

| Probe | Observed result |
|---|---|
| Actual adapter before repair | 17 suggestion deltas across all three registers; first partial 568 ms; failed at 979 ms with CorrectionFailed(providerError): invalid or interrupted stream |
| Direct curl with the exact app payload | HTTP 200; exit 0; 29 content chunks in 31 JSON frames, followed by DONE; first byte 0.611116 s; total 0.889647 s |
| Actual adapter after source commit 466be28 | 17 suggestion deltas across all three registers; first partial 519 ms; CorrectionCompleted at 733 ms; three nonempty suggestions; no failure diagnostics |

The raw curl response was:

```text
FORMAL: I had an apple yesterday.
CASUAL: I ate an apple yesterday.
SHORTER: I ate one yesterday.
END
```

Its last two JSON frames both carried finish_reason=stop and empty delta.content. The second also carried a usage object. This is OpenRouter's [documented final accounting frame](https://openrouter.ai/docs/api_reference/streaming), not a second generated answer. The decoder previously rejected all repeated stop reasons, causing the observed adapter failure despite valid tagged text and DONE.

Source commit 466be28 permits a repeated stop only when the frame has a usage object and no nonempty content. Generic duplicate stops, late content, changed finish reasons, invalid metadata, missing DONE, and existing frame/body limits still reject invalid streams. The regression reproduced both the pure decoder failure and the actual loopback-provider failure before the fix; afterward 41 focused provider/prompt/integration tests passed, with clean dart analyze --fatal-infos and formatting/whitespace checks.

The subsequent live adapter request completed with the same three suggestions shown above. This passes the requested Ministral integration check on the updated source. It does not verify the original Nemotron model or correction quality across other inputs. Rebuild/restart the app to include the decoder repair.

Saved exact credential-free curl payload: [MINISTRAL-CURL-REQUEST.json](./261002-7wk-MINISTRAL-CURL-REQUEST.json). The temporary probe scripts and raw capture were removed after recording these observations. The API key was never saved to disk or logs.
