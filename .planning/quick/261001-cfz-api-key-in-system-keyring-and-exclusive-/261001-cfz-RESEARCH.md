# Focused research — Provider settings

## Findings

- Active provider is derived from activePresetId. A provider radio must select a whole
  existing preset, rather than introduce a second independent active-provider field.
- Fresh installs describe only Claude. First-time URL setup must create a complete
  preset and provider entry on save, preserving the active prompt and inactive entries.
- JsonConfigStore deliberately strips newly introduced apiKey values. Leave that guard
  intact. Keyring writes go through an owned domain interface and the composition root.
- Existing key lookup attributes are application=hotkey-grammar-corrector and provider
  ID. Writing must use these exact attributes and replace=true to update matching items.
- Secret Service ReadAlias(default), Unlock, OpenSession and Collection.CreateItem
  implement storage. Honor returned prompts and dismissal, bound waits, and close the
  session/client. No errors may include credentials.
- Search existing matches before creation and update them with Item.SetSecret,
  including entries outside the default collection. This keeps later lookup from
  choosing an old duplicate. Combine immediate and prompted unlock results.
- Flutter RadioGroup owns radio selection and keyboard semantics. Use RadioListTile
  children, disabled during settings mutations. TextField obscureText masks key entry.

## Sources

- https://specifications.freedesktop.org/secret-service/latest/org.freedesktop.Secret.Service.html
- https://specifications.freedesktop.org/secret-service/latest/org.freedesktop.Secret.Collection.html
- https://specifications.freedesktop.org/secret-service/latest/org.freedesktop.Secret.Prompt.html
- https://specifications.freedesktop.org/secret-service/latest/org.freedesktop.Secret.Item.html
- https://api.flutter.dev/flutter/widgets/RadioGroup-class.html
- https://api.flutter.dev/flutter/material/TextField/obscureText.html

## Pitfalls and checks

Register prompt signal listeners before Prompt; test immediate completion and timeout.
Never let a failed write claim success. Preserve endpoint drafts on unrelated config
updates and distinguish external provider edits while editing. Test storage on a private
D-Bus service, controllers through fakes, and UI through the existing SettingsHarness.
