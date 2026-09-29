final class ReleasePlan {
  const ReleasePlan({
    required this.version,
    required this.tag,
    required this.isPrerelease,
  });

  final String version;
  final String tag;
  final bool isPrerelease;

  String get debianVersion => version.replaceFirst('-', '~');
  String get title => 'Hotkey Grammar Corrector $version';
}
