/// Read and write access to the system clipboard, plain text only.
///
/// Nothing above this port may assume X11 primary selection exists — that is
/// phase-2 and X11-only (AGENTS.md §4.2).
abstract interface class ClipboardPort {
  /// The current plain-text clipboard content. Null when the clipboard is
  /// empty or holds no plain text — absence is a modelled value, not an error.
  Future<String?> readText();

  Future<void> writeText(String text);
}
