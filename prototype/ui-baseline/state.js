"use strict";
(() => {
  function initialPanel(editor) {
    return { editor, submitted: "", status: "idle", suggestions: [], selected: null,
      error: "", copyStatuses: {}, generation: 0 };
  }
  function startCorrection(panel, text, pair) {
    return { ...panel, submitted: text, submittedPair: pair, status: "running",
      suggestions: [], selected: null, error: "", copyStatuses: {},
      generation: panel.generation + 1 };
  }
  function selectSuggestion(panel, register) {
    if (panel.status !== "finished") return panel;
    if (!panel.suggestions.some(item => item.register === register && item.text.trim())) return panel;
    return { ...panel, selected: register };
  }
  function initialConfig() {
    return { closeBehavior: "closeToTray", shortcut: "Ctrl+Shift+G", logSize: "1",
      activePreset: "default-formal-casual-shorter", baseUrl: "", keyPresent: false, version: 0,
      presets: [
        { id: "default-formal-casual-shorter", provider: "claude-agent-sdk", model: "claude-sonnet-5",
          prompt: "Correct grammar and unnatural phrasing while preserving meaning. Return Corrected, Casual and Short variants." },
        { id: "sample-fast", provider: "claude-agent-sdk", model: "sample-fast-model",
          prompt: "Keep the meaning and key details. Use natural English." },
      ] };
  }
  function activePreset(config) { return config.presets.find(item => item.id === config.activePreset); }
  function validBaseUrl(text) {
    try {
      const url = new URL(text);
      const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
      return !url.username && !url.password && !url.search && !url.hash &&
        (url.protocol === "https:" || url.protocol === "http:" && loopback);
    } catch { return false; }
  }
  function commitChange(config, action) {
    const next = { ...config, version: config.version + 1 };
    if (action.kind === "provider") {
      const preset = { id: "sample-compatible", provider: "openai-compatible",
        model: action.model, prompt: activePreset(config).prompt };
      return { ...next, baseUrl: action.baseUrl, activePreset: preset.id,
        presets: [...config.presets.filter(item => item.id !== preset.id), preset] };
    }
    if (action.kind === "prompt") return { ...next, presets: config.presets.map(item =>
      item.id === action.presetId ? { ...item, prompt: action.value } : item) };
    if (action.kind === "key") return { ...next, keyPresent: true };
    return { ...next, [action.kind]: action.value };
  }
  window.UiBaseline.state = { initialPanel, startCorrection, selectSuggestion,
    initialConfig, activePreset, validBaseUrl, commitChange };
})();
