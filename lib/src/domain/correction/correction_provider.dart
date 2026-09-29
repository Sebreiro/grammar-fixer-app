import 'correction_event.dart';
import 'preset.dart';

abstract interface class CorrectionProvider {
  /// Text in, stream out. Stateless: no state survives between calls.
  Stream<CorrectionEvent> correct({
    required String text,
    required Preset preset,
  });
}
