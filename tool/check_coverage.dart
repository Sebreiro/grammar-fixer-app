import 'dart:io';

/// LCOV totals for handwritten application code. Flutter emits BRDA entries
/// without BRF/BRH summary lines, so branch totals come from BRDA itself.
final class CoverageReport {
  const CoverageReport({
    required this.coveredLines,
    required this.totalLines,
    required this.coveredBranches,
    required this.totalBranches,
  });

  final int coveredLines;
  final int totalLines;
  final int coveredBranches;
  final int totalBranches;

  static CoverageReport parse(String lcov) {
    final lines = <String, bool>{};
    final branches = <String, bool>{};
    String? source;

    for (final row in lcov.split('\n')) {
      if (row.startsWith('SF:')) {
        source = row.substring(3).replaceAll('\\', '/');
        continue;
      }
      if (row == 'end_of_record') {
        source = null;
        continue;
      }
      if (source == null ||
          !source.startsWith('lib/') ||
          source.endsWith('.g.dart')) {
        continue;
      }
      if (row.startsWith('DA:')) {
        final fields = row.substring(3).split(',');
        if (fields.length < 2) throw FormatException('Invalid DA row: $row');
        final line = int.parse(fields[0]);
        final hits = int.parse(fields[1]);
        final key = '$source:$line';
        lines[key] = (lines[key] ?? false) || hits > 0;
      }
      if (row.startsWith('BRDA:')) {
        final fields = row.substring(5).split(',');
        if (fields.length != 4) throw FormatException('Invalid BRDA row: $row');
        final line = int.parse(fields[0]);
        final taken = fields[3] == '-' ? 0 : int.parse(fields[3]);
        final key = '$source:$line:${fields[1]}:${fields[2]}';
        branches[key] = (branches[key] ?? false) || taken > 0;
      }
    }

    if (lines.isEmpty || branches.isEmpty) {
      throw const FormatException(
        'LCOV has no application line or branch data',
      );
    }
    return CoverageReport(
      coveredLines: lines.values.where((covered) => covered).length,
      totalLines: lines.length,
      coveredBranches: branches.values.where((covered) => covered).length,
      totalBranches: branches.length,
    );
  }

  bool get meetsThreshold =>
      coveredLines * 100 >= totalLines * 90 &&
      coveredBranches * 100 >= totalBranches * 90;

  String get summary =>
      'Lines: $coveredLines/$totalLines '
      '(${_percent(coveredLines, totalLines)}%); '
      'branches: $coveredBranches/$totalBranches '
      '(${_percent(coveredBranches, totalBranches)}%)';

  static String _percent(int covered, int total) =>
      (covered * 100 / total).toStringAsFixed(2);
}

void main(List<String> args) {
  if (args.length > 1) {
    stderr.writeln('Usage: dart run tool/check_coverage.dart [lcov file]');
    exitCode = 2;
    return;
  }
  final path = args.isEmpty ? 'coverage/lcov.info' : args.single;
  try {
    final report = CoverageReport.parse(File(path).readAsStringSync());
    stdout.writeln(report.summary);
    if (!report.meetsThreshold) {
      stderr.writeln('Coverage must reach 90% for both lines and branches.');
      exitCode = 1;
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Coverage report unavailable: ${error.path}');
    exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln('Coverage report invalid: ${error.message}');
    exitCode = 2;
  }
}
