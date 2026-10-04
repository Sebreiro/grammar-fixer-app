"use strict";
(() => {
  const { fixtures, state } = window.UiBaseline;
  const byId = id => document.getElementById(id);
  let panel = state.initialPanel(fixtures.sampleInput);
  let cancelStream = () => {};
  let history = [];
  let config = state.initialConfig();
  let surface = "panel";
  let visibility = "shown";
  let setupProvider = null;
  let pending = null;
  let settingsFailure = null;
  let settingsSuccess = null;
  let settingsCategory = "general";
  let mutationTimer = null;
  let shortcutDraft = config.shortcut;
  let capturing = false;
  const cardNodes = new Map();
  const windowDimensions = new Map();
  const previewSizes = {
    panel: { comfortable: "Standard · 640 × 360", compact: "Compact · 520 × 360", wide: "Wide · 760 × 420" },
    settings: { comfortable: "Standard · 840 × 650", compact: "Compact · 620 × 560", wide: "Wide · 960 × 720" },
  };

  function icon(name) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.classList.add("icon");
    svg.setAttribute("aria-hidden", "true");
    const reference = document.createElementNS("http://www.w3.org/2000/svg", "use");
    reference.setAttribute("href", "#icon-" + name);
    svg.append(reference);
    return svg;
  }

  function announce(id, message) {
    const notice = byId(id);
    if (notice.textContent !== message) notice.textContent = message;
  }
  function makeCard({ register, label, key }) {
    const card = document.createElement("article");
    card.className = "card";
    card.dataset.register = register;
    const heading = makeCardHeading({ label, key });
    const text = document.createElement("p");
    text.className = "suggestion-text";
    const { footer, copy, feedback, copyLabel } = makeCopyFooter({ register, label });
    card.append(heading, text, footer);
    wireCardSelection(card, register);
    card.setAttribute("aria-keyshortcuts", key);
    byId("cards").append(card);
    cardNodes.set(register, { card, text, copy, feedback, copyLabel });
  }
  function makeCardHeading({ label, key }) {
    const heading = document.createElement("div");
    heading.className = "card-header";
    const title = document.createElement("strong");
    title.className = "card-title";
    title.textContent = label;
    const selected = document.createElement("span");
    selected.className = "selection-icon";
    selected.append(icon("check"));
    title.append(selected);
    const shortcut = document.createElement("kbd");
    shortcut.textContent = key;
    shortcut.title = "Press " + key + " with suggestions focused to select";
    heading.append(shortcut, title);
    return heading;
  }
  function makeCopyFooter({ register, label }) {
    const feedback = document.createElement("span");
    feedback.className = "copy-status";
    feedback.setAttribute("role", "status");
    const copy = document.createElement("button");
    copy.className = "copy-action";
    const copyLabel = document.createElement("span");
    copyLabel.textContent = "Copy";
    copy.append(icon("copy"), copyLabel);
    copy.setAttribute("aria-label", "Copy " + label);
    copy.addEventListener("click", event => { event.stopPropagation(); copySuggestion(register); });
    const footer = document.createElement("div");
    footer.className = "card-footer";
    footer.append(feedback, copy);
    return { footer, copy, feedback, copyLabel };
  }
  function wireCardSelection(card, register) {
    card.addEventListener("click", () => selectSuggestion(register));
    card.addEventListener("keydown", event => {
      if (event.target !== card || event.repeat || !["Enter", " "].includes(event.key)) return;
      event.preventDefault(); selectSuggestion(register);
    });
  }
  function renderPanel() {
    byId("correct").disabled = !panel.editor.trim();
    byId("correction-status").textContent = { idle: "Ready", running: "Correcting…", finished: "Complete", failed: "Failed" }[panel.status];
    byId("correction-status").dataset.status = panel.status;
    byId("correction-empty").hidden = panel.status !== "idle";
    byId("cards").hidden = ["idle", "failed"].includes(panel.status);
    byId("correction-error").hidden = panel.status !== "failed";
    byId("error-message").textContent = panel.error;
    announce("correction-announcement", panel.status === "failed" ? panel.error
      : panel.status === "finished" ? "Correction complete." : "");
    for (const [register, nodes] of cardNodes) renderCard(register, nodes);
  }
  function renderCard(register, nodes) {
    const suggestion = panel.suggestions.find(item => item.register === register);
    nodes.card.hidden = ["idle", "failed"].includes(panel.status);
    nodes.card.tabIndex = panel.status === "finished" ? 0 : -1;
    nodes.card.classList.toggle("partial", panel.status === "running");
    nodes.card.classList.toggle("selected", panel.selected === register);
    nodes.card.setAttribute("aria-label", (suggestion?.label || register) +
      (panel.selected === register ? ", selected" : ""));
    if (nodes.text.textContent !== (suggestion?.text || "")) nodes.text.textContent = suggestion?.text || "";
    nodes.copy.disabled = panel.status !== "finished" || !suggestion?.text.trim() ||
      panel.copyStatuses[register] === "Copying…";
    nodes.feedback.textContent = panel.copyStatuses[register] || "";
    nodes.copyLabel.textContent = ["Copying…", "Copied"].includes(nodes.feedback.textContent)
      ? nodes.feedback.textContent : "Copy";
    nodes.feedback.classList.toggle("copy-error", nodes.feedback.textContent.includes("Couldn't copy"));
  }
  function startCorrection(text) {
    runCorrection({ text, outcome: byId("correction-outcome").value });
  }
  function runCorrection({ text, outcome }) {
    if (!text.trim()) return;
    cancelStream();
    panel = state.startCorrection(panel, text, activePair());
    const generation = panel.generation;
    const update = change => {
      if (generation !== panel.generation) return;
      panel = { ...panel, ...change }; renderPanel();
    };
    cancelStream = fixtures.streamSample({
      text, outcome,
      onPartial: suggestions => update({ suggestions }),
      onFinished: suggestions => {
        update({ suggestions, status: "finished" });
        history = [...history, { input: text, suggestions: suggestions.map(({ register, text }) => ({ register, text })) }];
        byId("sample-effects").textContent = history.length + " completed correction(s) in sample history.";
      },
      onFailed: error => update({ status: "failed", error }),
    });
    renderPanel();
    byId("suggestions").focus();
  }
  function activePair() {
    const preset = state.activePreset(config);
    return { provider: preset.provider, model: preset.model, prompt: preset.prompt };
  }
  function selectSuggestion(register) {
    panel = state.selectSuggestion(panel, register);
    renderPanel();
    if (panel.selected === register) cardNodes.get(register).card.scrollIntoView({ block: "nearest", inline: "nearest" });
  }
  function copySuggestion(register) {
    const suggestion = panel.suggestions.find(item => item.register === register);
    if (panel.status !== "finished" || !suggestion?.text.trim()) return;
    const generation = panel.generation;
    panel = { ...panel, copyStatuses: { ...panel.copyStatuses, [register]: "Copying…" } };
    renderPanel();
    fixtures.copySample({ text: suggestion.text, outcome: byId("copy-outcome").value, onResult: result => {
      if (generation !== panel.generation) return;
      panel = { ...panel, copyStatuses: { ...panel.copyStatuses, [register]: result.message } };
      if (result.text !== null) byId("clipboard-output").textContent = result.text;
      renderPanel();
    } });
  }
  function selectedProvider() { return setupProvider || state.activePreset(config).provider; }
  function syncDrafts() {
    const preset = state.activePreset(config);
    byId("prompt").value = preset.prompt;
    byId("base-url").value = config.baseUrl;
    byId("model").value = config.presets.find(item => item.provider === "openai-compatible")?.model || "";
    byId("api-key").value = "";
    byId("key-saved").textContent = "";
    byId("prompt-warning").hidden = true;
    byId("provider-warning").hidden = true;
  }
  function renderPresets() {
    const provider = selectedProvider();
    const available = config.presets.filter(item => item.provider === provider);
    byId("preset-section").hidden = available.length === 0;
    const signature = available.map(item => item.id + item.model).join("|");
    if (byId("preset-choices").dataset.signature === signature) {
      byId("preset-choices").querySelectorAll("input").forEach(input => {
        input.checked = input.value === config.activePreset;
      });
      return;
    }
    byId("preset-choices").dataset.signature = signature;
    byId("preset-choices").replaceChildren();
    for (const preset of available) {
      const label = document.createElement("label");
      label.className = "choice";
      const input = document.createElement("input");
      input.type = "radio"; input.name = "preset"; input.value = preset.id;
      input.checked = preset.id === config.activePreset;
      input.addEventListener("change", () => mutate({ kind: "activePreset", value: preset.id }));
      const text = document.createElement("span");
      const title = document.createElement("strong");
      title.textContent = presetTitle(preset);
      const model = document.createElement("small");
      model.textContent = preset.model + " · prompt included";
      text.append(title, model);
      label.append(input, text); byId("preset-choices").append(label);
    }
  }
  function presetTitle(preset) {
    return { "default-formal-casual-shorter": "Everyday writing", "sample-fast": "Quick correction",
      "sample-compatible": "Connected provider", "sample-custom": "Custom preset" }[preset.id] || preset.id;
  }
  function hotkeyFixture() {
    const scenario = byId("hotkey-scenario").value;
    const effective = scenario === "x11-different" ? "Ctrl+Alt+J" : config.shortcut;
    if (scenario.startsWith("x11")) return { authority: "application", effective,
      message: "In effect: " + effective + (effective !== config.shortcut
        ? "\nThat differs from your preference, " + config.shortcut + "." : "") };
    if (scenario === "wayland") return { authority: "desktop", effective: null,
      message: "Your desktop holds this shortcut and describes it as:\nSuper+G (desktop sample wording)" };
    if (scenario === "wayland-unknown") return { authority: "desktop", effective: null,
      message: "A shortcut is in effect, but nothing was reported about which combination it is, so this app cannot show it." };
    if (scenario === "retained") return { authority: "application", effective: "Ctrl+Shift+G",
      message: "That combination was refused. The previous shortcut is still in effect.\nIn effect: Ctrl+Shift+G" };
    const messages = {
      "not-requested": "No shortcut has been requested yet. The tray menu still opens the panel.",
      unavailable: "Global shortcuts are unavailable to this app right now, so no combination can be registered.\nThe tray menu still opens the panel.\nWhether this app or your desktop would own the shortcut is not known until one is registered.",
      refused: "That combination was refused. Choose a different one and apply it again.\nThe tray menu still opens the panel.",
      revoked: "Your desktop took this shortcut away. Set it again when you want it back.\nNo shortcut is currently in effect.\nThe tray menu still opens the panel.",
    };
    return { authority: null, effective: null, message: messages[scenario] };
  }
  function resetCapture() {
    capturing = false;
    shortcutDraft = hotkeyFixture().effective || config.shortcut;
    byId("capture-feedback").textContent = "Click to record a shortcut.";
  }
  function renderHotkey() {
    const binding = hotkeyFixture();
    byId("hotkey-status").textContent = binding.message;
    byId("hotkey-status").style.whiteSpace = "pre-wrap";
    byId("shortcut-label").textContent = binding.authority === "application" ? "Shortcut"
      : binding.authority === "desktop" ? "Shortcut preference" : "Shortcut to request";
    byId("capture").textContent = capturing ? "Press a shortcut… (Escape to cancel)" : shortcutDraft;
    byId("keep-shortcut").hidden = binding.authority !== "application";
    byId("current-shortcut-hint").hidden = binding.authority !== "application";
    byId("current-shortcut-hint").textContent = "Current shortcut: " +
      (binding.effective || config.shortcut) +
      ". It is already registered, so pressing it summons the panel instead of recording it here. Use Keep current to leave it unchanged.";
  }
  function renderSettings() {
    const provider = selectedProvider();
    byId("settings-controls").disabled = pending !== null;
    byId("settings-pending").hidden = pending === null;
    byId("settings-failure").hidden = settingsFailure === null;
    byId("settings-error-message").textContent = settingsFailure?.message || "";
    announce("settings-announcement", settingsFailure?.message || "");
    byId("settings-retry").hidden = settingsFailure === null;
    byId("settings-retry").disabled = pending !== null;
    byId("custom-provider").hidden = !config.presets.some(item => item.provider === "sample-local");
    byId("close-behavior").value = config.closeBehavior;
    byId("log-size").value = config.logSize;
    byId("custom-log-size").hidden = config.logSize !== "2";
    document.querySelectorAll('input[name="provider"]').forEach(input => { input.checked = input.value === provider; });
    byId("compatible-section").hidden = provider !== "openai-compatible";
    byId("provider-setup-notice").hidden = !setupProvider;
    byId("key-section").hidden = provider !== "openai-compatible";
    byId("sdk-notice").hidden = provider !== "claude-agent-sdk";
    byId("prompt-section").hidden = provider !== state.activePreset(config).provider;
    byId("prompt-unavailable").hidden = !byId("prompt-section").hidden;
    byId("edit-prompt").disabled = byId("prompt-section").hidden;
    const activePreset = state.activePreset(config);
    byId("active-prompt-preset").textContent = "Active preset: " + presetTitle(activePreset) + " · " + activePreset.model;
    renderPresets(); renderHotkey(); renderDraftGuards();
    renderGroupFeedback();
    byId("committed-status").textContent = "Sample committed: " + config.activePreset +
      " · " + config.closeBehavior + " · " + config.logSize + " MiB";
  }
  function renderGroupFeedback() {
    document.querySelectorAll("[data-feedback]").forEach(notice => {
      const kind = notice.dataset.feedback;
      const waiting = pending?.kind === kind;
      const failure = settingsFailure?.action.kind === kind;
      notice.dataset.tone = waiting ? "pending" : failure ? "error" : "success";
      notice.textContent = waiting ? "Applying your change…" : failure ? settingsFailure.message
        : settingsSuccess === kind ? "Saved. Your change is in effect." : "";
    });
  }
  function showCategory(category) {
    settingsCategory = category;
    document.querySelectorAll(".category-tab").forEach(tab => {
      const selected = tab.dataset.category === category;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
      byId("category-" + tab.dataset.category).hidden = !selected;
    });
    byId("settings-category").value = category;
    document.querySelector(".settings-form").scrollTop = 0;
  }
  function renderDraftGuards() {
    const validUrl = state.validBaseUrl(byId("base-url").value.trim());
    byId("save-provider").disabled = pending !== null || !validUrl ||
      !byId("model").value.trim();
    byId("url-error").textContent = !byId("base-url").value.trim() ? "Required" : !validUrl
      ? "Use HTTPS or HTTP loopback, without credentials, query or fragment." : "";
    byId("model-required").hidden = Boolean(byId("model").value.trim());
    byId("save-key").disabled = pending !== null || !byId("api-key").value.trim();
    byId("save-prompt").disabled = pending !== null || !byId("prompt").value.trim() ||
      byId("prompt").value === state.activePreset(config).prompt;
    byId("prompt-required").hidden = Boolean(byId("prompt").value.trim());
  }
  function renderWindow() {
    const shown = visibility === "shown";
    byId("panel").hidden = !shown || surface !== "panel";
    byId("settings").hidden = !shown || surface !== "settings";
    byId("hidden-window").hidden = shown;
    byId("visibility-message").textContent = visibility === "quit"
      ? "Sample app has quit. Use Reset sample to restart."
      : "Sample window is " + visibility + ". Use a sample window action to return.";
    byId("window-status").textContent = visibility + " · " + surface;
    renderWindowDimensions();
  }
  function renderWindowDimensions() {
    const frame = document.querySelector(".window");
    if (frame.dataset.surface !== surface) {
      windowDimensions.set(frame.dataset.surface, { width: frame.style.width, height: frame.style.height });
      const dimensions = windowDimensions.get(surface);
      frame.style.width = dimensions?.width || "";
      frame.style.height = dimensions?.height || "";
      frame.dataset.surface = surface;
    }
    for (const option of byId("preview-size").options) option.textContent = previewSizes[surface][option.value];
  }
  function openSettings() {
    surface = "settings"; capturing = false;
    showCategory(settingsCategory);
    renderSettings(); renderWindow(); byId("back").focus();
  }
  function backToPanel() {
    surface = "panel"; byId("api-key").value = ""; capturing = false;
    renderWindow(); byId("editor").focus();
  }
  function mutate(action) {
    if (pending) return;
    pending = { ...action };
    const outcome = byId("settings-outcome").value;
    renderSettings();
    mutationTimer = fixtures.mutateSample({ outcome, onResult: finishMutation });
  }
  function finishMutation(outcome) {
    if (!pending) return;
    clearTimeout(mutationTimer);
    const action = pending;
    pending = null;
    const stalePrompt = action.kind === "prompt" &&
      (config.activePreset !== action.presetId || state.activePreset(config).prompt !== action.expectedPrompt);
    const refusedShortcut = action.kind === "shortcut" &&
      ["retained", "unavailable", "refused"].includes(byId("hotkey-scenario").value);
    if (outcome === "failure" || stalePrompt || refusedShortcut) {
      settingsFailure = { action, message: stalePrompt
        ? "The active preset or correction prompt changed before saving. Review it and try again."
        : refusedShortcut ? "The shortcut change did not land. The previous preference is unchanged."
          : "Could not save your change. Your previous settings are still in effect." };
      renderSettings(); return;
    }
    config = state.commitChange(config, action);
    settingsSuccess = action.kind;
    if (settingsFailure?.action.kind === action.kind) settingsFailure = null;
    if (action.kind === "key") {
      byId("api-key").value = ""; byId("key-saved").textContent = "API key saved.";
      if (byId("key-source-scenario").value === "None") byId("key-source-scenario").value = "System keyring";
      renderKeySource();
    } else if (["provider", "activePreset", "prompt"].includes(action.kind)) {
      setupProvider = null; syncDrafts();
    }
    if (action.kind === "shortcut") {
      if (["revoked", "not-requested"].includes(byId("hotkey-scenario").value)) byId("hotkey-scenario").value = "wayland";
      resetCapture();
    }
    renderSettings();
  }
  function providerChanged(provider) {
    if (pending || provider === selectedProvider()) return;
    const preset = config.presets.find(item => item.provider === provider);
    setupProvider = preset ? null : provider;
    if (preset) mutate({ kind: "activePreset", value: preset.id });
    else { syncDrafts(); renderSettings(); }
  }
  function externalConfigEdit() {
    const oldPrompt = state.activePreset(config).prompt;
    const promptDirty = byId("prompt").value !== oldPrompt;
    const providerDirty = byId("base-url").value !== config.baseUrl ||
      byId("model").value !== (config.presets.find(item => item.provider === "openai-compatible")?.model || "");
    config = { ...config, version: config.version + 1, baseUrl: "https://sample.invalid/v1",
      presets: config.presets.map(item => ({ ...item,
        prompt: item.id === config.activePreset ? oldPrompt + "\nExternal sample edit." : item.prompt,
        model: item.provider === "openai-compatible" ? "external-sample-model" : item.model })) };
    if (!promptDirty) byId("prompt").value = state.activePreset(config).prompt;
    if (!providerDirty) {
      byId("base-url").value = config.baseUrl;
      byId("model").value = config.presets.find(item => item.provider === "openai-compatible")?.model || "";
    }
    byId("prompt-warning").hidden = !promptDirty;
    byId("provider-warning").hidden = !providerDirty;
    renderSettings();
  }
  function renderKeySource() {
    const source = byId("key-source-scenario").value;
    byId("key-source").textContent = "API key source: " + source;
    byId("key-plaintext").hidden = source !== "Config file";
  }
  function freshSession() {
    cancelStream();
    const text = byId("clipboard-input").value === "text" ? fixtures.sampleInput : "";
    const generation = panel.generation + 1;
    panel = { ...state.initialPanel(text), generation };
    byId("editor").value = text; renderPanel();
  }
  function windowAction(action) {
    if (action === "reset") {
      cancelStream(); clearTimeout(mutationTimer); pending = null; settingsFailure = null; settingsSuccess = null;
      settingsCategory = "general"; showCategory(settingsCategory);
      config = state.initialConfig(); history = []; visibility = "dismissed"; surface = "panel";
      setupProvider = null; syncDrafts(); renderSettings();
      byId("clipboard-output").textContent = "Nothing copied.";
      byId("sample-effects").textContent = "No sample history yet.";
      byId("key-source-scenario").value = "None"; renderKeySource();
      action = "tray";
    }
    if (visibility === "quit") return;
    resetCapture(); renderHotkey(); byId("api-key").value = "";
    if (action === "close") {
      if (config.closeBehavior === "quit") {
        visibility = "quit"; cancelStream(); clearTimeout(mutationTimer); pending = null;
      } else visibility = "dismissed";
    } else if (["summon", "tray"].includes(action)) {
      if (action === "summon" && visibility === "shown" && surface === "panel") visibility = "dismissed";
      else {
        if (visibility === "dismissed") freshSession();
        visibility = "shown"; surface = "panel";
      }
    } else if (action === "restore") visibility = "shown";
    else visibility = action;
    renderWindow();
    if (visibility === "shown" && surface === "panel") byId("editor").focus();
  }
  function previewScene(scene) {
    cancelStream();
    const text = scene === "blank" ? "" : scene === "long" ? fixtures.longInput : fixtures.sampleInput;
    const generation = panel.generation + 1;
    panel = { ...state.initialPanel(text), generation };
    byId("editor").value = text;
    visibility = "shown"; surface = "panel";
    if (["completed", "long", "failed"].includes(scene)) {
      panel = state.startCorrection(panel, text, activePair());
      panel = { ...panel, status: scene === "failed" ? "failed" : "finished",
        suggestions: scene === "failed" ? [] : fixtures.suggestionsFor(text),
        selected: scene === "failed" ? null : "formal",
        error: scene === "failed" ? "The provider stopped during correction. Try again." : "" };
    }
    renderPanel(); renderWindow();
    if (scene === "streaming") runCorrection({ text, outcome: "preview" });
  }
  function captureKey(event) {
    if (!capturing || event.repeat) return;
    event.preventDefault();
    if (event.key === "Escape" && !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey) {
      capturing = false; renderHotkey(); return;
    }
    if (["Control", "Alt", "Shift", "Meta"].includes(event.key)) return;
    if (!(event.ctrlKey || event.altKey || event.metaKey) || !/^[a-z0-9]$/i.test(event.key)) {
      byId("capture-feedback").textContent = "Use a supported letter or digit with Ctrl, Alt or Super. Your last valid draft is unchanged.";
      return;
    }
    shortcutDraft = [event.ctrlKey && "Ctrl", event.altKey && "Alt", event.shiftKey && "Shift",
      event.metaKey && "Super", event.key.toUpperCase()].filter(Boolean).join("+");
    capturing = false; byId("capture-feedback").textContent = "Shortcut recorded. Apply to save.";
    renderHotkey();
  }
  byId("open-settings").addEventListener("click", openSettings);
  byId("back").addEventListener("click", backToPanel);
  document.querySelectorAll(".category-tab").forEach(tab => {
    tab.addEventListener("click", () => showCategory(tab.dataset.category));
    tab.addEventListener("keydown", event => {
      const categories = ["general", "ai", "advanced"];
      const offset = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[event.key];
      if (offset === undefined && !["Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const index = categories.indexOf(settingsCategory);
      const next = event.key === "Home" ? "general" : event.key === "End" ? "advanced"
        : categories[(index + offset + categories.length) % categories.length];
      showCategory(next); byId("tab-" + next).focus();
    });
  });
  byId("settings-category").addEventListener("change", () => showCategory(byId("settings-category").value));
  byId("edit-prompt").addEventListener("click", () => { showCategory("advanced"); byId("prompt").focus(); });
  byId("preview-size").addEventListener("change", () => {
    const frame = document.querySelector(".window");
    frame.style.width = ""; frame.style.height = "";
    windowDimensions.clear();
    frame.dataset.size = byId("preview-size").value;
  });
  byId("preview-scene").addEventListener("change", () => previewScene(byId("preview-scene").value));
  byId("close-behavior").addEventListener("change", () => mutate({ kind: "closeBehavior", value: byId("close-behavior").value }));
  byId("log-size").addEventListener("change", () => mutate({ kind: "logSize", value: byId("log-size").value }));
  document.querySelectorAll('input[name="provider"]').forEach(input =>
    input.addEventListener("change", () => providerChanged(input.value)));
  byId("save-provider").addEventListener("click", () => mutate({ kind: "provider",
    baseUrl: byId("base-url").value.trim(), model: byId("model").value.trim() }));
  byId("save-key").addEventListener("click", () => mutate({ kind: "key" }));
  byId("save-prompt").addEventListener("click", () => mutate({ kind: "prompt",
    value: byId("prompt").value, presetId: config.activePreset, expectedPrompt: state.activePreset(config).prompt }));
  byId("settings-retry").addEventListener("click", () => {
    if (settingsFailure) mutate(settingsFailure.action);
  });
  byId("resolve-settings").addEventListener("click", () => finishMutation("success"));
  ["base-url", "model", "prompt", "api-key"].forEach(id => byId(id).addEventListener("input", () => {
    if (id === "api-key") byId("key-saved").textContent = "";
    if (id === "prompt" && byId("prompt").value === state.activePreset(config).prompt) byId("prompt-warning").hidden = true;
    renderDraftGuards();
  }));
  byId("external-config").addEventListener("click", externalConfigEdit);
  byId("custom-config").addEventListener("click", () => {
    if (!config.presets.some(item => item.provider === "sample-local")) config = { ...config, logSize: "2",
      presets: [...config.presets, { id: "sample-custom", provider: "sample-local", model: "sample-local-model",
        prompt: "Preserve meaning and key details." }] };
    renderSettings();
  });
  byId("capture").addEventListener("click", () => {
    capturing = true; renderHotkey(); byId("capture").focus();
  });
  byId("capture").addEventListener("keydown", captureKey);
  byId("keep-shortcut").addEventListener("click", () => { resetCapture(); renderHotkey(); });
  byId("apply-shortcut").addEventListener("click", () => mutate({ kind: "shortcut", value: shortcutDraft }));
  byId("hotkey-scenario").addEventListener("change", () => { resetCapture(); renderHotkey(); });
  byId("key-source-scenario").addEventListener("change", renderKeySource);
  document.querySelectorAll("[data-window]").forEach(button =>
    button.addEventListener("click", () => windowAction(button.dataset.window)));
  window.addEventListener("pagehide", () => { cancelStream(); clearTimeout(mutationTimer); });
  syncDrafts(); renderSettings(); renderWindow();
  fixtures.registers.forEach(makeCard);
  byId("editor").value = panel.editor;
  byId("editor").addEventListener("input", () => {
    panel = { ...panel, editor: byId("editor").value }; renderPanel();
  });
  byId("editor").addEventListener("keydown", event => {
    if (!event.repeat && event.ctrlKey && event.key === "Enter") {
      event.preventDefault(); startCorrection(panel.editor);
    }
  });
  byId("suggestions").addEventListener("keydown", event => {
    if (event.repeat || event.ctrlKey || event.altKey || event.metaKey) return;
    const register = fixtures.registers.find(item => item.key === event.key)?.register;
    if (register) { event.preventDefault(); selectSuggestion(register); }
  });
  byId("correct").addEventListener("click", () => startCorrection(panel.editor));
  byId("retry").addEventListener("click", () => startCorrection(panel.submitted));
  byId("theme").addEventListener("change", () => {
    if (byId("theme").value === "system") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = byId("theme").value;
  });
  previewScene("completed");
  byId("editor").focus();
})();
