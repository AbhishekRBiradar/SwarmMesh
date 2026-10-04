import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/math_workload.dart';
import 'package:swarm_mesh/services/math_report_export_service.dart';
import 'package:swarm_mesh/services/session_history_service.dart';

void main() {
  late MathSession session;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('swarmmesh-math-');
    session = _session();
  });

  tearDown(() => directory.delete(recursive: true));

  test('mathematical sessions round-trip with baseline and contributions', () {
    final restored = MathSession.fromJson(session.toJson());

    expect(restored.problem, MathProblem.linearRegression);
    expect(restored.correctnessMatch, isTrue);
    expect(restored.result.contributions, {'LEADER': 12});
    expect(restored.result.summary['slope'], closeTo(2.75, .001));
  });

  test('math history saves, reloads and deletes independently', () async {
    final history = SessionHistoryService(
      directoryProvider: () async => directory,
    );

    await history.saveMath(session);
    final loaded = await history.load();
    expect(loaded.sessions, isEmpty);
    expect(loaded.mathSessions.single.id, session.id);

    await history.deleteMath(session.id);
    expect((await history.load()).mathSessions, isEmpty);
  });

  test('mathematical reports render all supported export formats', () async {
    expect(
      MathReportExportService.render(session, MathReportFormat.json),
      contains('linear-regression'),
    );
    expect(
      MathReportExportService.render(session, MathReportFormat.csv),
      contains('distributed_microseconds'),
    );
    expect(
      MathReportExportService.render(session, MathReportFormat.text),
      contains('Task results'),
    );
    final pdf = await MathReportExportService.renderPdf(session);
    expect(pdf, isA<Uint8List>());
    expect(pdf.sublist(0, 5), [37, 80, 68, 70, 45]);
  });
}

MathSession _session() {
  final problem = MathProblem.linearRegression;
  final tasks = MathWorkloadEngine.createTasks(problem);
  final results = MathWorkloadEngine.process(problem, tasks);
  MathRunResult run(String mode) => MathRunResult(
    mode: mode,
    problem: problem,
    tasks: tasks,
    results: results,
    summary: MathWorkloadEngine.aggregate(problem, results),
    elapsed: const Duration(milliseconds: 12),
    contributions: const {'LEADER': 12},
    retries: 0,
    sentBytes: mode == 'math-swarm' ? 100 : 0,
    receivedBytes: mode == 'math-swarm' ? 50 : 0,
  );
  return MathSession(
    id: 'math-session',
    createdAt: DateTime.utc(2026),
    baseline: run('math-single-device'),
    result: run('math-swarm'),
  );
}
