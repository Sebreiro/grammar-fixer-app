import '../domain/collection_equality.dart';
import '../domain/correction/correction_event.dart';
import '../domain/correction/suggestion_register.dart';

/// Where one panel session's correction stands.
enum CorrectionStatus { idle, running, completed, failed }

/// Everything the panel renders for one session (AD-18).
///
/// A session begins at [freshSession], so nothing an earlier session produced
/// can be mistaken for the current one. *Which* returns of the panel begin one
/// is `CorrectionController`'s decision rather than this type's — see
/// [isFreshSession].
final class CorrectionState {
  const CorrectionState({
    required this.editorText,
    required this.status,
    required this.suggestionTexts,
    this.submittedText,
    this.failure,
    this.selectedRegister,
    this.copyFailure,
    this.copyRegister,
    this.copyPending = false,
    this.copySucceeded = false,
    this.isFreshSession = false,
  }) : assert(
         (status == CorrectionStatus.failed) == (failure != null),
         'a failure is present exactly when the status is failed',
       ),
       // [freshSession]'s doc calls it "the only value that carries
       // [isFreshSession]", and until this assert nothing but that sentence
       // said so: the constructor is public and the marker is an ordinary
       // named parameter, so a caller could stamp a completed session, or one
       // holding an error, as a session *beginning* — DW-54's conflation
       // through a door the type claimed was shut. The fields checked are the
       // const-evaluable ones; `suggestionTexts` is left out because a
       // collection predicate would not survive the const constructor that
       // builds [freshSession] itself.
       assert(
         !isFreshSession ||
             (editorText == '' &&
                 status == CorrectionStatus.idle &&
                 submittedText == null &&
                 failure == null &&
                 selectedRegister == null &&
                 copyFailure == null &&
                 copyRegister == null &&
                 !copyPending &&
                 !copySucceeded),
         'a session begins with nothing in it: the marker belongs to '
         'CorrectionState.freshSession and to no other shape',
       );

  /// An idle session with nothing in it: no seed, no suggestions, no error.
  ///
  /// The controller's initial state — "this daemon has never shown a panel" —
  /// and deliberately **not** the state a session begins with, which is
  /// [freshSession].
  ///
  /// **Why they are two values and not one.** [isFreshSession] takes part in
  /// `==`, so folding them together would make "nothing has happened yet" and "a
  /// session just began" compare equal — the same conflation DW-54 was filed
  /// for, moved from a getter into a constant. Anything holding a snapshot would
  /// then be unable to tell them apart, and one such holder already exists:
  /// `CorrectionController.state` keeps the marker true for the rest of a
  /// session whose clipboard was empty, because the seeding emission that would
  /// have cleared it is skipped. Today only the two stream callbacks read the
  /// marker, so nothing is broken either way — which is exactly when to keep the
  /// distinction rather than after something depends on it.
  static const CorrectionState empty = CorrectionState(
    editorText: '',
    status: CorrectionStatus.idle,
    suggestionTexts: {},
  );

  /// [empty] plus the marker: the one state `CorrectionController._beginSession`
  /// emits, and the only value that carries [isFreshSession] (AD-18).
  static const CorrectionState freshSession = CorrectionState(
    editorText: '',
    status: CorrectionStatus.idle,
    suggestionTexts: {},
    isFreshSession: true,
  );

  /// The micro-editor's content (CAP-3): seeded from the clipboard when a
  /// session begins (CAP-2), then whatever the user has typed.
  ///
  /// Not on every show. A panel that comes back from an iconify or a focus loss
  /// returns to the session it left, with this field exactly as the user had it
  /// (DW-30).
  final String editorText;

  /// The exact string the running correction was submitted with, captured so
  /// Retry replays it even after the user has typed on (AD-18, CAP-13). Null
  /// until the session's first submit.
  final String? submittedText;

  final CorrectionStatus status;

  /// Text per register: deltas accumulated while running (CAP-5), replaced
  /// wholesale by the authoritative completed suggestions (AD-3). Empty
  /// while idle and after a failure — the error replaces them (CAP-13).
  final Map<SuggestionRegister, String> suggestionTexts;

  /// The terminal failure to render inline beside a Retry action (CAP-13).
  /// Null unless [status] is [CorrectionStatus.failed].
  final CorrectionFailed? failure;

  /// The register the user highlighted with its 1/2/3 key (CAP-4). Selection
  /// highlights and never copies (AD-18), so this is read by the panel and by
  /// nothing else — and it is only ever set while [status] is
  /// [CorrectionStatus.completed], because a partial is not the record of
  /// truth (AD-3). Null when nothing is highlighted.
  final SuggestionRegister? selectedRegister;

  /// A short sentence for a CAP-11 copy the clipboard rejected, rendered
  /// beside the variants and cleared by the next successful copy.
  ///
  /// Deliberately not [failure]: that field is CAP-13's *correction* error and
  /// its assert ties it to [CorrectionStatus.failed]. A rejected clipboard
  /// write did not fail the correction, so it carries no Retry — retrying
  /// would re-run a correction that already succeeded.
  final String? copyFailure;

  /// The only card whose latest copy request owns feedback, if any.
  final SuggestionRegister? copyRegister;

  /// A queued or active clipboard write still belongs to [copyRegister].
  final bool copyPending;

  /// The latest request completed its clipboard write successfully.
  final bool copySucceeded;

  /// Whether this state *is* the beginning of a session (AD-18).
  ///
  /// The signal two widgets need: the panel brings the caret back to the editor,
  /// and the daemon's home view returns to the panel, because CAP-1 promises the
  /// hotkey summons the *correction panel* and a window that comes up showing
  /// settings breaks it.
  ///
  /// **Stamped, never derived.** True on [freshSession] — the one state
  /// `CorrectionController._beginSession` emits — and false everywhere else,
  /// including on every state [copyWith] builds from that one: a state derived
  /// from a session beginning is not itself a session beginning. So an idle
  /// session whose editor the user cleared by hand reports false and is `!=`
  /// [freshSession], which is what the earlier `this == empty` comparison could
  /// not say (DW-54).
  final bool isFreshSession;

  /// Cannot clear [submittedText], [failure], [selectedRegister] or
  /// [copyFailure]; the transitions that drop them build a state directly
  /// instead.
  ///
  /// [isFreshSession] is deliberately absent, in both directions: it cannot be
  /// set here and it is never carried over. A state built from another is an
  /// update *within* a session — a keystroke, a streamed delta, the clipboard
  /// seed landing — and only `_beginSession` begins one.
  CorrectionState copyWith({
    String? editorText,
    String? submittedText,
    CorrectionStatus? status,
    Map<SuggestionRegister, String>? suggestionTexts,
    CorrectionFailed? failure,
    SuggestionRegister? selectedRegister,
    String? copyFailure,
    SuggestionRegister? copyRegister,
    bool? copyPending,
    bool? copySucceeded,
  }) {
    return CorrectionState(
      editorText: editorText ?? this.editorText,
      submittedText: submittedText ?? this.submittedText,
      status: status ?? this.status,
      suggestionTexts: suggestionTexts ?? this.suggestionTexts,
      failure: failure ?? this.failure,
      selectedRegister: selectedRegister ?? this.selectedRegister,
      copyFailure: copyFailure ?? this.copyFailure,
      copyRegister: copyRegister ?? this.copyRegister,
      copyPending: copyPending ?? this.copyPending,
      copySucceeded: copySucceeded ?? this.copySucceeded,
    );
  }

  /// Value equality so a consumer can dedupe: this state is re-emitted per
  /// keystroke and per streamed delta, and `Stream.distinct()` and Riverpod's
  /// `select` both fall back to identity without it. [suggestionTexts]
  /// compares as a map — it is rebuilt on every delta, so an identity compare
  /// would make every state distinct by construction.
  ///
  /// [isFreshSession] takes part, and that is load-bearing rather than
  /// completeness for its own sake: it is what stops a hand-cleared editor from
  /// comparing equal to the state a session begins with (DW-54).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CorrectionState &&
        editorText == other.editorText &&
        submittedText == other.submittedText &&
        status == other.status &&
        failure == other.failure &&
        selectedRegister == other.selectedRegister &&
        copyFailure == other.copyFailure &&
        copyRegister == other.copyRegister &&
        copyPending == other.copyPending &&
        copySucceeded == other.copySucceeded &&
        isFreshSession == other.isFreshSession &&
        mapEquals(suggestionTexts, other.suggestionTexts);
  }

  @override
  int get hashCode => Object.hash(
    editorText,
    submittedText,
    status,
    failure,
    selectedRegister,
    copyFailure,
    copyRegister,
    copyPending,
    copySucceeded,
    isFreshSession,
    mapHash(suggestionTexts),
  );
}
