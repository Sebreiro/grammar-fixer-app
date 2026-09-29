import 'package:test/test.dart';

import '../../tool/release_plan.dart';
import '../../tool/release_version.dart';

void main() {
  ReleasePlan plan({
    String pubspecVersion = '1.0.0+1',
    String mainVersion = '1.0.0+1',
    String branchRef = 'refs/heads/main',
    String bump = 'patch',
    List<String> tags = const [],
    String? retryTag,
  }) => ReleaseVersionPlanner.plan(
    pubspecVersion: pubspecVersion,
    mainVersion: mainVersion,
    branchRef: branchRef,
    bump: bump,
    remoteTags: tags,
    retryTag: retryTag,
  );

  test(
    'manual stable release bumps all three components and ignores legacy v1.0',
    () {
      expect(plan(tags: ['v1.0']).tag, 'v1.0.1');
      expect(plan(bump: 'minor').version, '1.1.0');
      expect(plan(bump: 'major').version, '2.0.0');
    },
  );

  test('branch release uses main core and increases only its own sequence', () {
    final first = plan(
      branchRef: 'refs/heads/feature',
      pubspecVersion: '9.9.9',
    );
    expect(first.tag, 'v1.0.1-feature.1');
    final next = plan(
      branchRef: 'refs/heads/feature',
      tags: [first.tag, 'v1.0.1-other.7'],
    );
    expect(next.tag, 'v1.0.1-feature.2');
    expect(next.debianVersion, '1.0.1~feature.2');
  });

  test(
    'slash, case, unicode, and truncation retain a deterministic identity digest',
    () {
      final slash = plan(branchRef: 'refs/heads/Feature/ABC');
      final collision = plan(branchRef: 'refs/heads/feature-abc');
      final caseVariant = plan(branchRef: 'refs/heads/Feature');
      final lowercase = plan(branchRef: 'refs/heads/feature');
      expect(slash.tag, isNot(collision.tag));
      expect(caseVariant.tag, isNot(lowercase.tag));
      expect(slash.tag, startsWith('v1.0.1-feature-abc-'));
      expect(plan(branchRef: 'refs/heads/café').tag, startsWith('v1.0.1-caf-'));
      expect(
        plan(branchRef: 'refs/heads/averylongbranchnamewithmanycharacters').tag,
        contains('-'),
      );
    },
  );

  test(
    'invalid refs, bumps, versions, and duplicate stable tags fail closed',
    () {
      expect(() => plan(branchRef: 'refs/tags/v1.0.0'), throwsFormatException);
      expect(() => plan(bump: 'build'), throwsFormatException);
      expect(() => plan(pubspecVersion: '1.0'), throwsFormatException);
      expect(() => plan(tags: ['v1.0.1']), throwsFormatException);
      expect(() => plan(branchRef: 'refs/heads/漢字'), throwsFormatException);
      expect(
        () =>
            plan(branchRef: 'refs/heads/feature', tags: ['v1.0.1-feature.bad']),
        throwsFormatException,
      );
    },
  );

  test('recovery selects the exact existing version without a new bump', () {
    expect(plan(bump: 'ignored', retryTag: 'v1.0.1').version, '1.0.1');
    expect(
      plan(
        branchRef: 'refs/heads/feature',
        bump: 'ignored',
        retryTag: 'v1.0.1-feature.4',
      ).tag,
      'v1.0.1-feature.4',
    );
    expect(
      () => plan(branchRef: 'refs/heads/other', retryTag: 'v1.0.1-feature.4'),
      throwsFormatException,
    );
    expect(() => plan(retryTag: 'v1.0.1-feature.4'), throwsFormatException);
  });
}
