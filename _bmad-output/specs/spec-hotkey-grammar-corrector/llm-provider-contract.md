# LLM Provider Contract

Companion to [SPEC.md](SPEC.md). The abstraction layer is explicitly in scope alongside the app itself; the model behind it is not. These principles bind the interface — the concrete types, transport code, and field names are architecture decisions built on top of them.

## Principles

1. **Text in, stream out.** The interface takes text and returns a stream. It is not HTTP-shaped: a provider may be a local process, an SDK call, or a network API, and none of that leaks into the interface. Anything that would force every provider to be an HTTP client violates this.

2. **Many described, one active.** Config describes any number of providers; exactly one is active at a time. Selection is config or in-app settings, not code, and not runtime negotiation. There is no cascade, no fallback, no race between backends.

3. **Prompt and model travel together as a preset.** A preset binds a prompt to a model as one unit. Combined with stateless sessions, this makes model experimentation a config-only activity — the reason "try a faster model" is not an engineering task.

4. **Stateless sessions.** Each correction is a fresh session. No conversation state, no carried context, no per-user history fed back in. A provider implementation that accumulates state across calls violates the contract.

5. **Structured response.** A provider returns a structured `suggestions[]`, not a blob of prose. The multi-suggestion panel (CAP-4) consumes this structure directly; a provider that returns unstructured text cannot satisfy it.

## Default provider

The shipped default is the **Claude Agent SDK** (`claude-agent-sdk` / `@anthropic-ai/claude-agent-sdk`) on model **`claude-sonnet-5`**.

Two naming points that matter when the architecture is written:

- The product formerly called the "Claude Code SDK" is now the **Claude Agent SDK** — Claude Code packaged as a library, supplying the agent harness and built-in tools while you host it. It is a different package from the Anthropic API SDK's Tool Runner (`client.beta.messages.tool_runner`), which only loops over tools you define. Do not substitute one for the other.
- The Sonnet 5 model id is exactly `claude-sonnet-5` — no date suffix.

This is a default, not a lock. Principle 2 still governs: the default is one entry in a config that may describe many providers, and switching the active one is a config or settings change, never a code change.

## `suggestions[]` doubles as the history schema

The structured response is also what gets persisted (CAP-7). One shape serves both the panel and the correction-history database — provider design *is* analytics design, and the two must not drift apart into separate models.

What is fixed here: the response is a list of suggestions; each entry is a register variant of the same correction (formal / casual / shorter per CAP-4); the same structure is what the history database stores.

What is **not** fixed here and belongs to architecture: the field names, the per-suggestion metadata, how streaming partials map onto the final structure, and the table layout that persists it.
