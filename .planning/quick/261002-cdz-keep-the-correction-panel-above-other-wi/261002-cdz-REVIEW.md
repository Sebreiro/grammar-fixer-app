---
quick_id: 261002-cdz
status: passed
---

# Inline source review

Reviewed the 14 files in source commit `36d91b9` against CAP-1/CAP-14 and AGENTS.md.
No unresolved source findings were identified.

- KWin changes are restricted to this app's normal windows. Taskbar eligibility
  stays enabled. Focus loss does not trigger reactivation.
- The existing GTK portal/tray activation tokens still flow through the same
  one-use presentation path. No provider, history or app-config changes.
- Runtime script setup and cleanup run on workers; the summon path adds no D-Bus
  round trips or window construction. The temporary file remains available
  until KWin has read it, then is removed.
- Shared ownership and a mutex preserve worker lifetime and serialize setup
  with disposal. Failed script execution rolls back the owned script; normal
  window disposal explicitly unloads it.
- Plasma compatibility was checked against upstream API/source, including
  window/client naming and script object paths. The final implementation
  introspects the common `/Scripting` parent, avoiding Qt's rejection of an
  unknown Plasma-6 path on Plasma 5.

Real KWin compositor behavior and the 100 ms target remain unobserved locally.
The delivered artifact is AppImage; Flatpak access to KWin's scripting service
and host-visible temporary storage was not validated by this task.
