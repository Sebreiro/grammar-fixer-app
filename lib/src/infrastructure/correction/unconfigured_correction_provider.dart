import '../../domain/correction/correction_event.dart';
import '../../domain/correction/correction_provider.dart';
import '../../domain/correction/preset.dart';

/// The provider a config gets when it names one this build cannot build.
///
/// AD-19 is explicit that a provider the daemon cannot reach must not prevent
/// it from starting — the tray, panel and settings all have to stay reachable
/// for the user to fix the setting. So an unknown or undescribed provider id
/// resolves to this, and the failure surfaces where CAP-13 can render it with
/// a Retry: one `CorrectionFailed(providerUnavailable, …)` on the first
/// correction, then the stream closes, exactly as AD-3 requires.
final class UnconfiguredCorrectionProvider implements CorrectionProvider {
  const UnconfiguredCorrectionProvider({required this.message});

  /// Why no provider could be built, in terms the panel can render and the
  /// user can act on — it names the id that could not be resolved.
  final String message;

  @override
  Stream<CorrectionEvent> correct({
    required String text,
    required Preset preset,
  }) async* {
    // `async*` gives the single-subscription stream AD-4 requires, and there
    // is nothing to tear down on cancel because nothing was started.
    yield CorrectionFailed(
      kind: CorrectionFailureKind.providerUnavailable,
      message: message,
    );
  }
}
