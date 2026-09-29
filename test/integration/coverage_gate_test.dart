import 'package:test/test.dart';

import '../../tool/check_coverage.dart';

void main() {
  test('the gate checks line and branch percentages independently', () {
    final lowBranch = CoverageReport.parse(_report(lineHits: 9, branchHits: 8));
    final lowLine = CoverageReport.parse(_report(lineHits: 8, branchHits: 9));
    final passing = CoverageReport.parse(_report(lineHits: 9, branchHits: 9));

    expect(lowBranch.meetsThreshold, isFalse);
    expect(lowLine.meetsThreshold, isFalse);
    expect(passing.meetsThreshold, isTrue);
  });

  test('the gate counts missing branch hits and excludes generated code', () {
    final report = CoverageReport.parse('''
SF:lib/src/code.dart
DA:1,1
BRDA:1,0,0,-
BRDA:2,0,0,1
end_of_record
SF:lib/src/code.g.dart
DA:1,0
BRDA:1,0,0,0
end_of_record
''');

    expect(report.totalLines, 1);
    expect(report.coveredLines, 1);
    expect(report.totalBranches, 2);
    expect(report.coveredBranches, 1);
  });

  test('the gate refuses a report without branch data', () {
    expect(
      () => CoverageReport.parse('SF:lib/src/code.dart\nDA:1,1\nend_of_record'),
      throwsFormatException,
    );
  });
}

String _report({required int lineHits, required int branchHits}) {
  final lines = [
    for (var index = 1; index <= 10; index++)
      'DA:$index,${index <= lineHits ? 1 : 0}',
  ];
  final branches = [
    for (var index = 1; index <= 10; index++)
      'BRDA:$index,0,0,${index <= branchHits ? 1 : 0}',
  ];
  return [
    'SF:lib/src/code.dart',
    ...lines,
    ...branches,
    'end_of_record',
  ].join('\n');
}
