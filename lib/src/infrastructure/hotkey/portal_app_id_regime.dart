/// Which mechanism owns this process's portal application id, asked once at
/// startup (ARCH-02).
///
/// The host portal registry associates an application id with the caller's bus
/// connection, and the specification is blunt about the limit: that interface
/// "will not work with applications xdg-desktop-portal identifies as
/// sandboxed". Inside a sandbox the portal derives the id from the sandbox
/// metadata instead, so the registration call is dead weight at best and an
/// error line on every launch at worst. Packaging is what settles which of the
/// two applies, and packaging is settled: the committed set includes Flatpak,
/// so the first step of the global-shortcuts handshake is a variable in the
/// sequence rather than a constant (DW-89, closed 2026-09-01).
///
/// **The signals a sandbox detector normally reaches for are rejected here by
/// name, and that rejection is why this type exists at all.** The portal
/// adapter refused to detect a sandbox for one recorded objection: the obvious
/// markers include `/.dockerenv`, which is true in this project's own
/// development container, so a detector keyed on it would take the sandboxed
/// branch in every test run and leave the handshake's first invariant executed
/// by nothing. A `container` variable, `/run/.containerenv` and cgroup path
/// sniffing are out for the same reason — each is true of some ordinary
/// development container, and none of the four says anything about Flatpak.
///
/// Measured in this project's own container on 2026-09-02: `/.dockerenv`
/// exists, `/.flatpak-info` is absent and `FLATPAK_ID` is unset, so the
/// predicate below answers with the host-registry regime here. (Of the rejected
/// four, only `/.dockerenv` actually fires in *this* container — cgroup v2
/// reports a bare `0::/`, and neither `/run/.containerenv` nor `container` is
/// set. They stay rejected because each is true of some other ordinary
/// container, which is the same objection one host further out.) Answering with
/// the host-registry regime here is precisely the property the objection asked
/// for, and it is why the objection is now answered rather than overruled.
enum PortalAppIdRegime {
  /// The host portal registry is what associates this process's application id
  /// with its bus connection, so the handshake's registration step runs.
  ///
  /// The fallback, and deliberately so: a registration attempted on a host with
  /// no such interface is already tolerated — the adapter carries five
  /// exception arms for exactly that shape — whereas *skipping* it on a host
  /// that needed it silently orphans the association, and the compositor then
  /// discards the bind with nothing in the logs pointing at why. An
  /// unrecognised environment is far more often an ordinary desktop than a
  /// sandbox that hides both of its own markers.
  hostRegistry,

  /// The sandbox supplies the application id out of its own metadata, so the
  /// registration step must not run at all.
  sandboxSupplied;

  /// Reads the regime off two injected inputs and nothing else: [environment]
  /// and a [fileExists] probe.
  ///
  /// Pure, and both branches reachable with no sandbox anywhere near the
  /// machine — the same shape, for the same reason, as
  /// `DisplayServer.fromEnvironment`. The probe is injected rather than read
  /// here because a `dart:io` read would leave the sandboxed branch unreachable
  /// on every host that is not a sandbox, which is every host this project is
  /// developed on.
  ///
  /// [sandboxInfoFile] is the load-bearing signal: the Flatpak runtime writes
  /// it into the sandbox and nothing else writes it. `FLATPAK_ID` is checked
  /// beside it because the runtime exports it into the same sandbox, it costs
  /// no second probe, and an environment survives a filesystem view this
  /// process may not be able to read.
  static PortalAppIdRegime fromEnvironment(
    Map<String, String> environment, {
    required bool Function(String path) fileExists,
  }) {
    if (fileExists(sandboxInfoFile)) {
      return PortalAppIdRegime.sandboxSupplied;
    }
    // Trimmed for the reason `DisplayServer.fromEnvironment` trims: the choice
    // is made once and never revisited, so a stray space in an exported
    // variable would pin the regime for the life of the daemon.
    final id = environment['FLATPAK_ID']?.trim();
    if (id != null && id.isNotEmpty) {
      return PortalAppIdRegime.sandboxSupplied;
    }
    return PortalAppIdRegime.hostRegistry;
  }

  /// The file the Flatpak runtime writes into its sandbox, and the only signal
  /// in this predicate that no ordinary development container also carries.
  ///
  /// Named rather than inlined so the confinement gate can pin it: a scan that
  /// silently stopped matching it would let the whole branch be deleted while
  /// every row still passed.
  static const String sandboxInfoFile = '/.flatpak-info';
}
