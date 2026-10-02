# Quick Task 261002-6ir — Research

## Findings
- AppPaths is the sole XDG resolver. Derive logs/grammmar-corrector.log from the same config home; do not read config from another place.
- StderrLogger already owns JSON line encoding. Reuse it for a file sink in a new Logger adapter that retains stderr, consumes asynchronous sink failures, and flushes/closes before process exit.
- OpenAiCompatibleCorrectionProvider discards non-200 bodies and lacks Logger injection. Inject the existing Logger through ProviderRegistry; capture bounded response bytes and safe response headers before translating the existing failure kind.
- ChatCompletionSseDecoder currently turns structured stream errors into an anonymous FormatException. Add an infrastructure-only callback for error frames before stream failure translation.
- CorrectionController._onFailed persists failures but never logs them. Log ids and failure kind there so every provider terminal failure is covered without exposing vendor-authored messages.
- All explicit exits in main must flush the file; ordinary signal/quit and early startup abort need the same logger lifecycle treatment.

## Pitfalls
- File.openWrite defaults to truncation: use FileMode.append.
- IOSink.done, flush, and close can reject asynchronously; a failed diagnostic sink must not crash or hold shutdown.
- Capture must be byte bounded, cancellable, and covered by the existing request deadline. Keep known HTTP status/body even if reading the body fails.
- OpenRouter errors may appear inside HTTP 200 SSE. Preserve error metadata (including nested raw details) while dropping echoed content and secrets.

## Primary sources
- https://openrouter.ai/docs/api_reference/errors-and-debugging — JSON error envelope, metadata, Retry-After, and HTTP 200 SSE error frames.
- https://api.dart.dev/dart-io/File/openWrite.html — append mode and asynchronous error handling.
- https://api.dart.dev/dart-io/IOSink/done.html — lifecycle completion future.

No new dependencies or provider/domain contract changes are needed.

## User retention decision
Use serialized asynchronous file writes so a byte limit can reset the same file without races or extra archive files. Persist logMaxBytes (default 1048576, minimum 1024); validate only in JsonConfigStore and apply settings/config updates through the existing graph listener.
