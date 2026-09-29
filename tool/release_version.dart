import 'dart:io';

import 'release_plan.dart';

final class ReleaseVersionPlanner {
  const ReleaseVersionPlanner._();

  static final RegExp _core = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+\d+)?$',
  );
  static final RegExp _tag = RegExp(
    r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([a-z0-9]+(?:-[a-z0-9]+)*)\.([1-9]\d*))?$',
  );

  static ReleasePlan plan({
    required String pubspecVersion,
    required String mainVersion,
    required String branchRef,
    required String bump,
    required Iterable<String> remoteTags,
    String? retryTag,
  }) {
    final branch = _branch(branchRef);
    if (retryTag != null && retryTag.isNotEmpty) {
      return _retry(branch, retryTag);
    }
    if (!const {'major', 'minor', 'patch'}.contains(bump)) {
      throw FormatException('bump must be major, minor, or patch');
    }
    final core = _bump(
      _parseCore(branch == 'main' ? pubspecVersion : mainVersion),
      bump,
    );
    final tags = remoteTags.toSet();
    if (branch == 'main') {
      final tag = 'v$core';
      if (tags.contains(tag)) {
        throw FormatException('stable tag already exists: $tag');
      }
      return ReleasePlan(version: core, tag: tag, isPrerelease: false);
    }
    final slug = _slug(branch);
    final prefix = 'v$core-$slug.';
    var maxSequence = 0;
    for (final tag in tags.where((tag) => tag.startsWith(prefix))) {
      final match = _tag.firstMatch(tag);
      if (match == null || match.group(4) != slug) {
        throw FormatException('ambiguous remote tag: $tag');
      }
      final sequence = int.parse(
        match.group(5) ?? (throw StateError('missing sequence')),
      );
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    final version = '$core-$slug.${maxSequence + 1}';
    return ReleasePlan(version: version, tag: 'v$version', isPrerelease: true);
  }

  static ReleasePlan _retry(String branch, String tag) {
    final match = _tag.firstMatch(tag);
    if (match == null) {
      throw FormatException('invalid retry tag: $tag');
    }
    final prereleaseSlug = match.group(4);
    if (branch == 'main' && prereleaseSlug != null) {
      throw FormatException('prerelease tag does not belong to main');
    }
    if (branch != 'main' && prereleaseSlug != _slug(branch)) {
      throw FormatException('retry tag does not belong to branch');
    }
    return ReleasePlan(
      version: tag.substring(1),
      tag: tag,
      isPrerelease: prereleaseSlug != null,
    );
  }

  static String _branch(String ref) {
    const prefix = 'refs/heads/';
    if (!ref.startsWith(prefix)) {
      throw FormatException('dispatch must name a branch');
    }
    final branch = ref.substring(prefix.length);
    if (branch.isEmpty ||
        branch.trim() != branch ||
        branch.contains(RegExp(r'[\x00-\x20]'))) {
      throw FormatException('invalid branch ref');
    }
    return branch;
  }

  static List<int> _parseCore(String version) {
    final match = _core.firstMatch(version);
    if (match == null) {
      throw FormatException('invalid pubspec version: $version');
    }
    return [
      for (var index = 1; index <= 3; index++)
        int.parse(
          match.group(index) ?? (throw StateError('missing version part')),
        ),
    ];
  }

  static String _bump(List<int> parts, String bump) => switch (bump) {
    'major' => '${parts[0] + 1}.0.0',
    'minor' => '${parts[0]}.${parts[1] + 1}.0',
    'patch' => '${parts[0]}.${parts[1]}.${parts[2] + 1}',
    _ => throw FormatException('invalid bump'),
  };

  static String _slug(String branch) {
    final lower = branch.toLowerCase();
    var slug = lower
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.length > 32) {
      slug = slug.substring(0, 32).replaceFirst(RegExp(r'-$'), '');
    }
    if (slug.isEmpty) {
      throw FormatException('branch has no ASCII slug');
    }
    if (slug != branch) {
      var digest = 0x811c9dc5;
      for (final byte in branch.codeUnits) {
        digest = ((digest ^ byte) * 0x01000193) & 0xffffffff;
      }
      slug = '$slug-${digest.toRadixString(16).padLeft(8, '0')}';
    }
    return slug;
  }
}

void main(List<String> args) {
  try {
    final options = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--') || index + 1 >= args.length) {
        throw const FormatException('expected --name value pairs');
      }
      options[args[index].substring(2)] = args[index + 1];
    }
    String required(String name) =>
        options[name] ?? (throw FormatException('missing $name'));
    final plan = ReleaseVersionPlanner.plan(
      pubspecVersion: required('pubspec-version'),
      mainVersion: required('main-version'),
      branchRef: required('branch-ref'),
      bump: required('bump'),
      remoteTags: File(required('tags-file')).readAsLinesSync(),
      retryTag: options['retry-tag'],
    );
    stdout.writeln('version=${plan.version}');
    stdout.writeln('tag=${plan.tag}');
    stdout.writeln('debian_version=${plan.debianVersion}');
    stdout.writeln('title=${plan.title}');
    stdout.writeln('prerelease=${plan.isPrerelease}');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
