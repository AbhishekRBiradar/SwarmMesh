import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/inventory_execution.dart';
import 'package:swarm_mesh/models/inventory_image_models.dart';
import 'package:swarm_mesh/models/inventory_models.dart';
import 'package:swarm_mesh/models/inventory_report.dart';
import 'package:swarm_mesh/models/inventory_session.dart';
import 'package:swarm_mesh/models/mesh_models.dart';
import 'package:swarm_mesh/models/run_diagnostics.dart';
import 'package:swarm_mesh/services/report_export_service.dart';
import 'package:swarm_mesh/services/session_history_service.dart';

void main() {
  test('diagnostics survive storage and all export formats; legacy reports stay readable', () {
    final json = _session().toJson();
    final result = json['result'] as Map<String, dynamic>;
    result['diagnostics'] = {
      'remoteWait': {
        'microseconds': 6000,
        'samples': 2,
        'maxMicroseconds': 4000,
      },
    };
    final saved = InventorySession.fromJson(json);
    expect(
      saved.result.diagnostics.phases[RunPhase.remoteWait]!.microseconds,
      6000,
    );
    expect(
      ReportExportService.render(saved, ReportFormat.csv),
      contains('result_remoteWait_microseconds'),
    );
    expect(
      ReportExportService.render(saved, ReportFormat.text),
      contains('6000 µs across 2 spans'),
    );
    expect(
      ReportExportService.render(saved, ReportFormat.json),
      contains('maxMicroseconds'),
    );
    result.remove('diagnostics');
    expect(InventorySession.fromJson(json).result.diagnostics.phases, isEmpty);
    result['diagnostics'] = {
      'remoteWait': {'microseconds': -1, 'samples': 2, 'maxMicroseconds': 4000},
    };
    expect(() => InventorySession.fromJson(json), throwsFormatException);
  });

  test(
    'saved report round-trip preserves filenames, retries and correctness',
    () {
      final original = _session();
      final saved = InventorySession.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(saved.correctnessMatch, isTrue);
      expect(saved.rows.map((row) => row.duplicate), [
        false,
        true,
        false,
        false,
        false,
      ]);
      expect(saved.rows.map((row) => row.unexpected), [
        false,
        false,
        true,
        false,
        false,
      ]);
      expect(saved.result.executions[1].retryCount, 1);
      expect(saved.result.executions.first.image!.fileName, 'a,"quoted".png');
      expect(saved.result.report.missingExpectedIds, ['PKG-000002']);
      expect(saved.result.report.unexpectedIds, ['PKG-999999']);
      expect(saved.result.contributions, {'B': 5});
      expect(saved.toJson(), original.toJson());
      expect(
        () => InventorySession.fromJson({
          ...original.toJson(),
          'schemaVersion': 999,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'CSV survives quoting/newlines and includes summary/recovery details',
    () {
      final csv = ReportExportService.render(_session(), ReportFormat.csv);
      final rows = _parseCsv(csv);
      final header = rows.first;
      expect(rows.every((row) => row.length == header.length), isTrue);
      expect(rows[1][header.indexOf('dataset')], 'Audit, "East"\nTeam');
      expect(rows[1][header.indexOf('filename')], 'a,"quoted".png');
      expect(rows[2][header.indexOf('filename')], "'=1+1.png");
      expect(rows[2][header.indexOf('duplicate')], 'true');
      expect(
        rows[2][header.indexOf('attempts_json')],
        contains('disconnected'),
      );
      expect(
        rows.any(
          (row) => row.contains('missing_id') && row.contains('PKG-000002'),
        ),
        isTrue,
      );
      expect(
        rows.any(
          (row) =>
              row.contains('worker_contributions') && row.contains('{"B":5}'),
        ),
        isTrue,
      );
    },
  );

  test('exports do not claim expected-ID checks when no list was supplied', () {
    final session = _session(expected: const {});
    final json = jsonDecode(
      ReportExportService.render(session, ReportFormat.json),
    ) as Map;
    expect(json['summary']['missingIds'], isNull);
    expect(json['summary']['unexpectedIds'], isNull);
    expect(session.rows.every((row) => row.unexpected == null), isTrue);
    final text = ReportExportService.render(session, ReportFormat.text);
    expect(text, contains('not performed (no expected list)'));
    expect(text, contains('DEMO DATASET'));
    expect(text, contains('Worker: B'));
    expect(text, contains('Retries count failed remote attempts'));
  });

  test('benchmark medians use real pairs and suppress invalid speedups', () {
    final summary = BenchmarkSummary([
      _session(singleMs: 100, swarmMs: 30),
      _session(singleMs: 200, swarmMs: 50),
      _session(singleMs: 300, swarmMs: 100),
    ]);
    expect(summary.medianSingleMicroseconds, 200000);
    expect(summary.medianSwarmMicroseconds, 50000);
    expect(summary.bestSwarmMicroseconds, 30000);
    expect(summary.worstSwarmMicroseconds, 100000);
    expect(summary.bestSingleMicroseconds, 100000);
    expect(summary.worstSingleMicroseconds, 300000);
    expect(summary.speedup, 4);
    expect(BenchmarkSummary([_session(localFallback: true)]).speedup, isNull);
    expect(
      BenchmarkSummary([_session(), _session(expected: {})]).speedup,
      isNull,
    );
  });

  group('private report history', () {
    late Directory root;
    late Directory reports;
    late SessionHistoryService history;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('swarmmesh-history-test-');
      reports = Directory('${root.path}/reports');
      history = SessionHistoryService(directoryProvider: () async => reports);
    });
    tearDown(() async => root.delete(recursive: true));

    test('reopens after restart and deletes only the chosen report', () async {
      final image = File('${root.path}/source.png');
      await image.writeAsBytes([1, 2, 3]);
      await history.save(_session());
      final restarted = SessionHistoryService(
        directoryProvider: () async => reports,
      );
      final loaded = await restarted.load();
      expect(loaded.sessions.single.datasetName, 'Audit, "East"\nTeam');
      expect(loaded.unreadableFiles, isEmpty);
      expect(await reports.list().length, 1);
      await restarted.delete(loaded.sessions.single.id);
      expect((await restarted.load()).sessions, isEmpty);
      expect(await image.readAsBytes(), [1, 2, 3]);
    });

    test('save then delete is serialized; corrupt records are retained and reported', () async {
      final save = history.save(_session());
      final delete = history.delete('session-001');
      await Future.wait([save, delete]);
      expect((await history.load()).sessions, isEmpty);
      final corrupt = File('${reports.path}/broken.json');
      await corrupt.writeAsString('{');
      final loaded = await history.load();
      expect(loaded.unreadableFiles, ['broken.json']);
      expect(await corrupt.exists(), isTrue);
      await expectLater(history.delete('../outside'), throwsArgumentError);
      await history.save(_session());
      expect((await history.load()).sessions, hasLength(1));
    });
  });
}

InventorySession _session({
  Set<String> expected = const {'PKG-000001', 'PKG-000002'},
  int singleMs = 100,
  int swarmMs = 50,
  bool localFallback = false,
}) => InventorySession(
  id: 'session-001',
  createdAt: DateTime.utc(2026, 10, 3),
  datasetName: 'Audit, "East"\nTeam',
  isDemo: true,
  leaderNodeId: 'L',
  devices: const {'L': 'Leader', 'A': 'Worker A', 'B': 'Worker B'},
  baseline: _run(false, expected, singleMs),
  result: _run(true, expected, swarmMs, localFallback: localFallback),
);

MeshRunResult _run(
  bool swarm,
  Set<String> expected,
  int elapsedMs, {
  bool localFallback = false,
}) {
  const labels = ['PKG-000001', 'PKG-000001', 'PKG-999999', 'BAD', ''];
  final batch = InventoryProcessor.process(labels);
  final nodeId = swarm ? 'B' : 'L';
  return MeshRunResult(
    mode: swarm
        ? (localFallback ? 'image-local-fallback' : 'image-swarm')
        : 'single-device',
    labels: labels,
    expectedIds: expected,
    results: batch.labels,
    report: InventoryReport.aggregate(
      originalLabels: labels,
      workerBatches: [batch],
      expectedIds: expected,
    ),
    elapsed: Duration(milliseconds: elapsedMs),
    contributions: {nodeId: labels.length},
    retries: swarm ? 1 : 0,
    sentBytes: swarm ? 100 : 0,
    receivedBytes: swarm ? 20 : 0,
    executions: [
      for (var i = 0; i < labels.length; i++)
        InventoryExecution(
          label: batch.labels[i],
          nodeId: nodeId,
          image: InventoryImageDecodeResult(
            imageId: 'IMAGE-$i',
            fileName: i == 0
                ? 'a,"quoted".png'
                : i == 1
                ? '=1+1.png'
                : '标签_$i.png',
            decodedValue: labels[i].isEmpty ? null : labels[i],
            status: labels[i].isEmpty ? 'unreadable' : 'decoded',
            reason: 'Test',
            elapsedMilliseconds: 2,
          ),
          attempts: [
            if (swarm && i == 1)
              const InventoryAttempt(
                nodeId: 'A',
                succeeded: false,
                error: 'disconnected',
              ),
            InventoryAttempt(
              nodeId: nodeId,
              succeeded: true,
              processingMicroseconds: 2000,
            ),
          ],
        ),
    ],
  );
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (ch == ',' || ch == '\r')) {
      row.add(cell.toString());
      cell = StringBuffer();
      if (ch == '\r') {
        rows.add(row);
        row = [];
        i++;
      }
    } else {
      cell.write(ch);
    }
  }
  return rows;
}
