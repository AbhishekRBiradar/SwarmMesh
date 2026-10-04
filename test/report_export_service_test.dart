import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/inventory_execution.dart';
import 'package:swarm_mesh/models/inventory_models.dart';
import 'package:swarm_mesh/models/inventory_report.dart';
import 'package:swarm_mesh/models/inventory_session.dart';
import 'package:swarm_mesh/models/mesh_models.dart';
import 'package:swarm_mesh/services/report_export_service.dart';

void main() {
  test('PDF report export produces a readable PDF document', () async {
    final labels = ['PKG-000001', 'BROKEN-LABEL'];
    final batch = InventoryProcessor.process(labels);
    final run = MeshRunResult(
      mode: 'local-fallback',
      labels: labels,
      expectedIds: const {'PKG-000001'},
      results: batch.labels,
      report: InventoryReport.aggregate(
        originalLabels: labels,
        workerBatches: [batch],
        expectedIds: const ['PKG-000001'],
      ),
      elapsed: const Duration(milliseconds: 12),
      contributions: const {'LEADER': 2},
      retries: 0,
      sentBytes: 0,
      receivedBytes: 0,
      executions: [
        for (final label in batch.labels)
          InventoryExecution(
            label: label,
            nodeId: 'LEADER',
            attempts: const [
              InventoryAttempt(nodeId: 'LEADER', succeeded: true),
            ],
          ),
      ],
    );
    final session = InventorySession(
      id: 'pdf-session',
      createdAt: DateTime.utc(2026),
      datasetName: 'PDF test',
      isDemo: false,
      leaderNodeId: 'LEADER',
      devices: const {'LEADER': 'Test phone'},
      baseline: run,
      result: run,
    );

    final bytes = await ReportExportService.renderPdf(session);

    expect(utf8.decode(bytes, allowMalformed: true), startsWith('%PDF-'));
    expect(bytes.length, greaterThan(500));
  });
}
