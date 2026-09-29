# Known Risks and Watch Items

Companion to [SPEC.md](SPEC.md). These warn rather than rule out, so they are not Constraints — but each one can invalidate a design choice made without knowing it. Architecture must read this before committing to a hotkey or windowing approach.

## Wayland global hotkeys — *resolved, and it changed the contract*

The original warning stands and has now been acted on by the architecture step. Verified against the upstream `xdg-desktop-portal` documentation on 2026-08-06:

- **The portal owns the binding, not the app.** `BindShortcuts`' `preferred_trigger` is a hint; the compositor and user choose the actual combination, and the portal presents its own configuration dialog. This is why CAP-12's success criterion is now split per display server rather than claiming the app sets the hotkey everywhere.
- **Only GNOME and KDE ship a GlobalShortcuts backend.** wlroots-based compositors (Sway, Hyprland, Niri) do not, so binds fail there and the hotkey must degrade to unavailable while the tray still opens the panel. Verified against community tracking, not an upstream support matrix — re-check before promising a compositor.
- **A non-sandboxed app must call `org.freedesktop.host.portal.Registry.Register(app_id)` once, before any other portal call** (portal ≥ 1.20), and the app id must be reverse-DNS *and* match an installed `.desktop` file, or the bind is silently discarded. Missing either is a silent failure, not an error.
- **Running under XWayland is not a workaround** — the compositor still will not route unfocused keys.

The full D-Bus call sequence, the two-adapter port, and the binding-authority type live in `ARCHITECTURE-SPINE.md` (AD-9 through AD-12).

## X11 primary selection has no Wayland equivalent

The phase-2 primary-selection input (correct highlighted text with no Ctrl+C step) is X11-specific with no direct Wayland counterpart. It cannot be assumed to port. Anything built in MVP that presupposes a uniform "get selected text" capability across display servers will not survive contact with phase 2.

## Flutter standing memory footprint

The ~96 MB standing RAM cost is an accepted trade for developer experience and the mobile path. It remains a watch item specifically because this is a *warm resident* tray app: unlike a launched-and-closed application, it pays that cost continuously for as long as the user is logged in. Measure the resident footprint rather than assuming the baseline figure holds under a loaded panel and an open database.

*The diff-view watch item that stood here is resolved: the verdict came back "not in MVP", and it now sits in SPEC.md's Non-goals. CAP-6, which held it, is retired.*
