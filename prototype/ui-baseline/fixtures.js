"use strict";
window.UiBaseline = {};
(() => {
  const registers = [
    { register: "formal", label: "Corrected", key: "1" },
    { register: "casual", label: "Casual", key: "2" },
    { register: "shorter", label: "Short", key: "3" },
  ];
  const sampleInput = "I has a meeting tomorrow and I wants to know if you can joins.";
  function suggestionsFor(text) {
    const corrected = text.replace(/\bI has\b/g, "I have")
      .replace(/\bI wants\b/g, "I want").replace(/\bcan joins\b/g, "can join");
    const knownSample = text === sampleInput;
    return registers.map(({ register, label }) => ({
      register, label,
      text: register === "casual" && knownSample
        ? "I've got a meeting tomorrow. Can you join?"
        : register === "shorter" && knownSample
          ? "Can you join my meeting tomorrow?" : corrected,
    }));
  }
  function streamSample({ text, outcome, onPartial, onFinished, onFailed }) {
    const results = suggestionsFor(text);
    const timers = [
      setTimeout(() => onPartial(results.map(item => ({
        ...item, text: item.text.slice(0, Math.max(1, Math.ceil(item.text.length / 3))),
      }))), 150),
      setTimeout(() => onPartial(results.map(item => ({
        ...item, text: item.text.slice(0, Math.ceil(item.text.length * .7)),
      }))), 420),
      setTimeout(() => outcome === "success" ? onFinished(results)
        : onFailed(outcome === "timeout"
          ? "The correction timed out. Try again."
          : "The provider stopped during correction. Try again."), 800),
    ];
    return () => timers.forEach(clearTimeout);
  }
  function copySample({ text, outcome, onResult }) {
    return setTimeout(() => onResult(outcome === "success"
      ? { text, message: "Copied" }
      : { text: null, message: "Couldn't copy this suggestion. Try again." }), 250);
  }
  function mutateSample({ outcome, onResult }) {
    if (outcome === "pending") return null;
    return setTimeout(() => onResult(outcome), 600);
  }
  window.UiBaseline.fixtures = { registers, sampleInput, suggestionsFor,
    streamSample, copySample, mutateSample };
})();
