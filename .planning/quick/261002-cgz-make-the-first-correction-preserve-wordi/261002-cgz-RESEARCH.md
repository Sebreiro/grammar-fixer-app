# Research — Suggestion order and tone

## Findings

- `RegisterTaggedPrompt.compose` is shared by Claude Agent SDK and OpenAI-compatible adapters. Its appended format currently asks for a formal first variant; changing only fresh-install defaults would leave existing presets formal.
- `DefaultAppConfig.shippedSystemPrompt` separately repeats the old formal instruction. Reuse the shared response contract in the seeded default to avoid drift.
- `SuggestionRegister` declaration order already defines keys 1/2/3 and panel order. Enum names are persisted by the history repository and translated to strict FORMAL/CASUAL/SHORTER tags by the stream parser. Renaming them would require a migration unrelated to this task.
- `SuggestionCard` derives all labels, accessibility names, and copy tooltips from enum names. Introduce a readable label on the enum while keeping its stable identity.
- Existing prompt-file migration and settings synchronization preserve exact user text. Append the required variant instructions at request time, explicitly overriding conflicting legacy register instructions without rewriting saved files.

## Implementation

Use existing pure Dart prompt composition, a stable-identity enum label getter, and presentation updates. No libraries, network research, transport changes, database changes, or new provider interfaces are needed.

## Validation

Test the generated variant instructions after both current defaults and legacy/custom prompts. Check captured requests from both adapters, and verify actual panel labels, order, key hints, selection and copying. Run Dart analysis, focused Dart suites, panel widget suites, and the deliberate live smoke when its dependencies are available.

Baseline: 16 focused prompt/configuration tests passed before changes.
