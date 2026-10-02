# Focused research: prompt configuration

Performed inline using the live repository; no new library or external API is needed.

- JsonConfigStore already owns decoding, validation, private atomic writes, first-run seeding, directory watching and conflict detection. Keep the prompt codec here.
- DefaultAppConfig already supplies a complete shipped Preset. Changing its prose would be quality tuning outside this task. Seed its existing systemPrompt into plain UTF-8 text, preserving blank lines and trailing newlines exactly.
- Continue decoding string-valued systemPrompt for upgrades. On successful load, migrate inline values to new .txt files and write systemPromptFile references. Keep resolved prompt text inside Preset; file paths remain private store metadata.
- Resolve strings before crossing ConfigStore: Preset remains prompt+model and providers continue receiving precisely the edited string.
- SettingsController already serializes mutations and renders failures; add a prompt mutation with its own failure ownership.
- CompatibleProviderForm is the closest widget analog: controller lifetime outside build, follow external changes when clean, retain unsaved drafts and warn when disk edits conflict. Key the prompt editor by preset id so switching presets cannot leak a draft.
- Validate file references as .txt basenames beside config; reject ambiguity and shared references. Watch the config directory for edits to the config and referenced files. Preserve chosen filenames during Settings writes; avoid filename collisions. Stage all changed files before installation and roll back installed replacements if an installation fails. Reject blank text without validating prose or imposing format at config time.
- Preserve pre-existing uncommitted logging changes. Baselines are saved under /tmp/prompt-config-baseline; commits must stage only this task's deltas.

Baseline evidence: dart analyze --fatal-infos clean; 57 config/default tests passed.
