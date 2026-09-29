/// A hand edit reached the config file after the caller read its previous value.
///
/// The store leaves the newer file untouched and updates its cached value so a
/// controller can derive the intended change again from that value.
final class ConfigWriteConflict implements Exception {
  const ConfigWriteConflict();
}
