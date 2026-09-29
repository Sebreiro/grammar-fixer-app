/// The only credential information the Settings view may receive.
enum ApiKeySource {
  systemKeyring,
  environment,
  configFile,
  none;

  String get settingsLabel => switch (this) {
    systemKeyring => 'System keyring',
    environment => 'Environment variable',
    configFile => 'Config file',
    none => 'None configured',
  };
}
