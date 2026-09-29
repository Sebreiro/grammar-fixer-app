import 'package:flutter/material.dart';

import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import 'hotkey_binding_label.dart';

/// AD-10's read-out: what is actually in effect (CAP-12, HOTKEY-03).
///
/// Everything here is derived from what the backend *reported*, never from the
/// binding that was requested. That is the whole of what AD-10 exists to
/// prevent — a settings screen claiming it set a hotkey the desktop actually
/// chose — and it is why no path here falls back to printing [preference] where
/// the effective shortcut goes. On Wayland every real bind comes back with a
/// null [HotkeyRegistration.effective] (the portal carries no machine-readable
/// combination anywhere in its replies), so that fallback would be the lie in
/// the common case rather than in an edge one.
///
/// **Which regime owns the shortcut is not said, and that is deliberate**
/// (D-03). AD-10's ratified rule had this screen name the regime —
/// authoritative on X11, advisory on Wayland — and the user ratified dropping
/// it on 2026-09-01: one UI everywhere, mechanism hidden. The app still grabs
/// directly on X11 and declares through the portal on Wayland; what the screen
/// presents is the shortcut in effect and nothing about the machinery that
/// holds it. The spine is **not** edited here — plan 01-10 files the amendment
/// for Phase 7's spine pass, which is the precedent for this class of change.
///
/// The accepted cost of that, recorded so nobody reads it as a bug: shortcut
/// notation now differs between display servers even though the regime label is
/// hidden, because on Wayland what is shown is the desktop's own wording
/// (D-04). Accuracy beats uniform notation.
///
/// [preference] is read for exactly one purpose, on exactly one branch: saying
/// when the reported combination and the requested one differ. An outcome can
/// be accurate field by field and silent about the request — an X11 rebind the
/// backend refused answers `HotkeyBound` carrying the *previous* combination,
/// while Wayland answers `HotkeyRetained`. The comparison uses
/// `HotkeyBinding`'s own `==`, which is set-based, so modifier order cannot
/// fake a difference. Where no combination is reported there is nothing
/// comparable to compare, and nothing is said about the preference at all.
class HotkeyStatusView extends StatelessWidget {
  const HotkeyStatusView({
    required this.outcome,
    required this.backendDescription,
    required this.preference,
    super.key,
  });

  /// What the last bind — or the last backend-initiated change — resolved to.
  /// Null until anything has been attempted at all.
  final HotkeyBindOutcome? outcome;

  /// The backend's own user-readable wording for what is in effect, verbatim,
  /// or null when the backend authors none (HOTKEY-03, D-04).
  ///
  /// The Wayland portal's `trigger_description`, which is the only thing that
  /// reply says about the shortcut in force — and null on X11, where the
  /// combination itself is reported and this screen renders it with
  /// [hotkeyBindingLabel] instead.
  ///
  /// **Rendered, never parsed and never restyled.** It is localized and
  /// backend-specific — a German desktop sends `Strg+Umschalt+G` — so turning
  /// it into this app's notation would either be a parser that fails silently
  /// on a translated string (DW-66's ratified `decision:` rejected exactly
  /// that) or a claim in this app's voice about words the desktop chose.
  final String? backendDescription;

  /// The combination the config file holds, which on Wayland is a submitted
  /// preference rather than a setting (AD-10).
  final HotkeyBinding preference;

  @override
  Widget build(BuildContext context) {
    final outcome = this.outcome;
    final lines = switch (outcome) {
      // Never a regime and never a combination: nothing has been asked of a
      // backend, so nothing about one is known.
      null => const [
        'No shortcut has been requested yet, so nothing is in effect.',
      ],
      // Both halves are destructured: the cause selects what this screen says
      // about the situation, the message carries the adapter's own diagnosis.
      // Selecting on the cause rather than on the text of the message is the
      // whole of HOTKEY-08 at this end — a screen that matched on substrings
      // would go silently wrong the day an adapter reworded a sentence.
      HotkeyUnavailable(:final cause, :final message) => _unavailableLines(
        cause,
        message,
      ),
      HotkeyBound(:final registration) => _boundLines(registration),
      HotkeyRetained(:final registration) => [
        ..._boundLines(registration),
        'That combination was refused. The previous shortcut still works; '
            'choose another and apply it.',
      ],
    };
    final theme = Theme.of(context);
    return Semantics(
      // The one place a compositor-side rebind or a dropped shortcut becomes
      // visible, and it changes with no user action (AD-11) — so a reader who
      // cannot see it would otherwise never learn their hotkey stopped working.
      // An unchanged sentence updates no semantics node, so this does not
      // re-announce on every rebuild.
      liveRegion: true,
      // `container: true` so the node this flag lands on is guaranteed to be
      // this widget's own rather than one the surrounding layout happened to
      // form. **Pinned by no row, and said so rather than left looking
      // guarded:** measured on this tree, removing it fails zero rows, because
      // the annotation currently merges into an ancestor node that carries these
      // sentences and nothing else. That is a property of this widget's
      // neighbours — a screen someone else will edit — not of this widget, and
      // the failure it would produce is silent (a live region with an empty
      // label announces nothing). The flag itself *is* pinned, by the A8/A9
      // semantics row.
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }

  /// AD-12's statement: what this means for the user, then the adapter's own
  /// words for why.
  ///
  /// **The first line is chosen by [cause], never by the text of [message]**
  /// (D-06, HOTKEY-08). Three genuinely different situations used to render
  /// identically here, distinguishable only by prose the screen relayed without
  /// understanding: a desktop with no global-shortcut mechanism at all, a
  /// working backend that refused one combination, and a live shortcut the
  /// desktop took away. They call for three different responses from the user —
  /// give up, pick another key, set it again — and [_causeLine] is where that
  /// is said.
  ///
  /// **The adapter's [message] is still rendered as it stands, and this screen
  /// appends one closing status line.** Every
  /// `HotkeyUnavailable`
  /// this codebase produces already ends by naming the tray as the way in that
  /// still works, and a screen that added the sentence itself printed it twice
  /// — so [_causeLine]'s three sentences deliberately do **not** mention the
  /// tray. The one exception is the empty-message path below, where there is no
  /// message to have named it and therefore nothing to duplicate.
  ///
  /// **An empty or blank message cannot produce a blank unavailable state.**
  /// The cost of trusting the message used to be that an adapter whose sentence
  /// was empty left this screen saying nothing at all about a hotkey that had
  /// stopped working. Because the first line now comes from the cause, that is
  /// structurally impossible; [_trayFallback] covers D-07 for that path.
  ///
  /// **No regime is claimed**, which is the part that must not regress: the
  /// display server is a fact this ring cannot see (AD-1), and guessing "this
  /// app owns it" is precisely what the SPEC's Ratified Divergence forbids on
  /// the compositor this state is most likely to be reached on (a wlroots
  /// session ships no portal at all, which is AD-12's headline case). The
  /// closing line describes the user's system, not this widget's epistemic
  /// position.
  ///
  /// The closing line is appended for every unavailable outcome, after the
  /// adapter message or the tray fallback. A revoked shortcut was already
  /// registered, so its line describes current status rather than treating
  /// its past ownership as unknown.
  List<String> _unavailableLines(
    HotkeyUnavailableCause cause,
    String message,
  ) => [
    _causeLine(cause),
    // Whitespace counts as absent: a message of blank space would render a
    // stripe of nothing between two sentences that read as consecutive.
    if (message.trim().isEmpty) _trayFallback else message,
    _unavailableStatusLine(cause),
  ];

  String _unavailableStatusLine(
    HotkeyUnavailableCause cause,
  ) => switch (cause) {
    HotkeyUnavailableCause.revoked => 'No shortcut is currently in effect.',
    HotkeyUnavailableCause.noBackend || HotkeyUnavailableCause.keyRefused =>
      'Whether this app or your desktop would own the shortcut is not known '
          'until one is registered.',
  };

  /// What the situation means for the user, exhaustively over the three causes
  /// D-06 names (HOTKEY-08).
  ///
  /// Each says what to do rather than restating the diagnosis, because the
  /// diagnosis is the adapter's message and printing it twice in two
  /// vocabularies helps nobody. **None of them names the tray** — see
  /// [_unavailableLines] for why that is load-bearing rather than an oversight.
  ///
  /// No line offers an action the screen does not have: D-06 is explicit that
  /// the messages differ and the affordances do not, so "choose a different
  /// one" points at the field already on this screen and not at a button this
  /// method would have to invent.
  String _causeLine(HotkeyUnavailableCause cause) => switch (cause) {
    // A different combination cannot help while no backend is reachable.
    // The cause does not prove the desktop lacks shortcut support entirely.
    HotkeyUnavailableCause.noBackend =>
      'Global shortcuts are unavailable to this app right now, so no '
          'combination can be registered.',
    // A backend answered, so the mechanism exists and another combination may
    // well be granted. This is the one cause where retrying is the move.
    HotkeyUnavailableCause.keyRefused =>
      'That combination was refused. Choose a different one and apply it '
          'again.',
    // D-08: the daemon does not re-claim a revoked shortcut, so the user is
    // told plainly that setting it again is theirs to do. D-09 is why they are
    // reading it here rather than being interrupted by it.
    HotkeyUnavailableCause.revoked =>
      'Your desktop took this shortcut away. Set it again when you want it '
          'back.',
  };

  /// D-07 for the one path where the adapter's message cannot carry it.
  ///
  /// Not a general-purpose append: it is reached only when [message] is empty
  /// or blank, precisely so the tray is never named twice on the paths where
  /// the adapter already named it.
  static const String _trayFallback = 'The tray menu still opens the panel.';

  /// What a backend that took the request says, in whichever vocabulary is
  /// truthful for the backend that reported it.
  ///
  /// Three cases, and which one applies is a fact about the backend rather than
  /// a choice this widget makes:
  ///
  /// 1. **A combination was reported** — X11, where this app owns the grab.
  ///    Rendered with [hotkeyBindingLabel], and this is the one branch where
  ///    the differs-from-your-preference line means anything: both sides are
  ///    structured and compare as sets.
  /// 2. **Wording but no combination** — the Wayland portal, where every real
  ///    bind comes back this way. The desktop's text is rendered **verbatim on
  ///    a line of its own**, under a line saying whose words they are: DW-66's
  ///    ratified `decision:` asks for the description "clearly labelled as the
  ///    desktop's own wording rather than this app's". Nothing is prepended to
  ///    it, appended to it, or spelled differently in it.
  /// 3. **Neither** — a backend that took the request and reported nothing
  ///    about what it holds. It says so. What it must never do is print
  ///    [preference] in the combination's place: showing what was asked for
  ///    where what is in effect belongs is the one defect this whole surface
  ///    exists to prevent, and on the backend where case 3 was once the common
  ///    case it would have been a lie almost every time.
  ///
  /// A shortcut the desktop accepted but assigned *differently* arrives here,
  /// not on the unavailable path (D-02): something opens the panel, which is
  /// what the user wanted, and the exact combination is the desktop's to
  /// choose. This method's job is to report that combination — or the desktop's
  /// words for it — never to compare it against the request and call it a
  /// failure.
  List<String> _boundLines(HotkeyRegistration registration) {
    final effective = registration.effective;
    if (effective != null) {
      return [
        'In effect: ${hotkeyBindingLabel(effective)}',
        if (effective != preference)
          'That differs from your preference, '
              '${hotkeyBindingLabel(preference)}.',
      ];
    }
    final description = backendDescription;
    // Whitespace counts as absent, as it does for an unavailable message: a
    // description of blank space would render a stripe of nothing under a line
    // promising the desktop's own words.
    if (description != null && description.trim().isNotEmpty) {
      return [_desktopWording, description];
    }
    return [
      'A shortcut is in effect, but nothing was reported about which '
          'combination it is, so this app cannot show it.',
    ];
  }

  /// Whose words the line beneath it is, which is the whole of what this app
  /// adds to the desktop's description (D-04, DW-66).
  ///
  /// Separate from the description rather than wrapped around it, so the text
  /// the desktop authored is rendered as itself and this app's sentence cannot
  /// be mistaken for part of it.
  static const String _desktopWording =
      'Your desktop holds this shortcut and describes it as:';
}
