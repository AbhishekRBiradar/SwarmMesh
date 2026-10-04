import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/inventory_session.dart';
import '../models/mesh_models.dart';

enum ReportFormat { csv, json, text, pdf }

class ReportExportService {
  static String render(InventorySession session, ReportFormat format) =>
      switch (format) {
        ReportFormat.json => const JsonEncoder.withIndent(
          '  ',
        ).convert(session.toJson()),
        ReportFormat.csv => _csv(session),
        ReportFormat.text => _text(session),
        ReportFormat.pdf => throw ArgumentError(
          'Use renderPdf for PDF reports',
        ),
      };

  static Future<Uint8List> renderPdf(InventorySession session) async {
    final report = session.result.report;
    final document = pw.Document();
    final rows = session.rows;
    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('SwarmMesh inventory report')),
          pw.Text(
            '${session.datasetName}${session.isDemo ? ' - DEMO DATASET' : ''}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Session: ${session.id}'),
          pw.Text('UTC: ${session.createdAt.toUtc().toIso8601String()}'),
          pw.Text('Leader: ${session.leaderNodeId}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Metric', 'Value'],
            data: [
              ['Items', report.totalLabels],
              ['Unique valid', report.uniqueValidCount],
              ['Duplicates', report.duplicateCount],
              ['Invalid', report.invalidCount],
              ['Unreadable', report.unreadableCount],
              ['Correctness match', session.correctnessMatch ? 'Yes' : 'No'],
              ['Single-device time', _milliseconds(session.baseline)],
              [
                session.result.isSwarm ? 'Swarm time' : 'Distributed time',
                _milliseconds(session.result),
              ],
              [
                'Speedup',
                session.speedup?.toStringAsFixed(2) ?? 'Not applicable',
              ],
              ['Job bytes sent', session.result.sentBytes],
              ['Job bytes received', session.result.receivedBytes],
              ['Failed remote attempts', session.result.retries],
            ],
          ),
          pw.SizedBox(height: 12),
          if (report.expectedIds.isEmpty)
            pw.Text(
              'Missing/unexpected checks: not performed (no expected list).',
            )
          else ...[
            pw.Text(
              'Missing IDs: ${report.missingExpectedIds.isEmpty ? 'None' : report.missingExpectedIds.join(', ')}',
            ),
            pw.Text(
              'Unexpected IDs: ${report.unexpectedIds.isEmpty ? 'None' : report.unexpectedIds.join(', ')}',
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Header(level: 1, child: pw.Text('Image / record details')),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Filename',
              'Decoded value',
              'State',
              'Duplicate',
              'Unexpected',
              'Device',
              'Retries',
            ],
            data: [
              for (final row in rows)
                [
                  row.execution.image?.fileName ?? 'Text record',
                  row.execution.label.rawLabel,
                  row.execution.label.status.name,
                  row.duplicate ? 'Yes' : 'No',
                  row.unexpected == null
                      ? 'Not checked'
                      : row.unexpected!
                      ? 'Yes'
                      : 'No',
                  row.execution.nodeId,
                  row.execution.retryCount,
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Generated/sample data is not evidence of real warehouse performance.',
            style: pw.TextStyle(
              color: session.isDemo ? PdfColors.orange : PdfColors.grey,
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _milliseconds(MeshRunResult run) =>
      '${(run.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms';

  static Future<Uri?> save(
    InventorySession session,
    ReportFormat format,
  ) async {
    final extension = format == ReportFormat.text ? 'txt' : format.name;
    final bytes = format == ReportFormat.pdf
        ? await renderPdf(session)
        : Uint8List.fromList(utf8.encode(render(session, format)));
    return FilePicker.saveFile(
      fileName: 'swarmmesh-${session.id}.$extension',
      bytes: bytes,
      mimeType: switch (format) {
        ReportFormat.json => 'application/json',
        ReportFormat.csv => 'text/csv',
        ReportFormat.text => 'text/plain',
        ReportFormat.pdf => 'application/pdf',
      },
    );
  }

  static String _csv(InventorySession session) {
    final rows = <List<Object?>>[
      [
        'record_type',
        'dataset',
        'demo_dataset',
        'timestamp',
        'image_id',
        'filename',
        'raw_label',
        'package_id',
        'state',
        'duplicate',
        'unexpected',
        'decode_state',
        'image_processing_ms',
        'worker_node_id',
        'retries',
        'attempts_json',
        'metric',
        'value',
      ],
      for (final row in session.rows)
        [
          'item',
          session.datasetName,
          session.isDemo,
          session.createdAt.toIso8601String(),
          row.execution.image?.imageId,
          row.execution.image?.fileName,
          row.execution.label.rawLabel,
          row.execution.label.isValid ? row.execution.label.normalizedId : null,
          row.execution.label.status.name,
          row.duplicate,
          row.unexpected,
          row.execution.image?.status,
          row.execution.image?.elapsedMilliseconds,
          row.execution.nodeId,
          row.execution.retryCount,
          jsonEncode(
            row.execution.attempts.map((attempt) => attempt.toJson()).toList(),
          ),
          '',
          '',
        ],
    ];
    void summary(String key, Object? value) => rows.add([
      'summary',
      session.datasetName,
      session.isDemo,
      session.createdAt.toIso8601String(),
      ...List<Object?>.filled(12, ''),
      key,
      value,
    ]);
    summary('session_id', session.id);
    summary('leader', session.leaderNodeId);
    summary('devices', jsonEncode(session.devices));
    summary('expected_list_provided', session.result.expectedIds.isNotEmpty);
    summary('correctness_match', session.correctnessMatch);
    summary('single_microseconds', session.baseline.elapsed.inMicroseconds);
    summary('swarm_microseconds', session.result.elapsed.inMicroseconds);
    summary('swarm_mode', session.result.mode);
    summary('transports', session.result.transports.join(', '));
    summary('speedup', session.speedup);
    summary('sent_bytes', session.result.sentBytes);
    summary('received_bytes', session.result.receivedBytes);
    summary('failed_remote_attempts', session.result.retries);
    summary('worker_contributions', jsonEncode(session.result.contributions));
    summary('measurement_notes', session.toJson()['measurementNotes']);
    for (final run in [session.baseline, session.result]) {
      final prefix = identical(run, session.baseline) ? 'baseline' : 'result';
      for (final entry in run.diagnostics.phases.entries) {
        summary(
          '${prefix}_${entry.key.name}_microseconds',
          entry.value.microseconds,
        );
        summary('${prefix}_${entry.key.name}_samples', entry.value.samples);
        summary(
          '${prefix}_${entry.key.name}_max_microseconds',
          entry.value.maxMicroseconds,
        );
      }
    }
    if (session.result.expectedIds.isNotEmpty) {
      for (final id in session.result.report.missingExpectedIds) {
        summary('missing_id', id);
      }
      for (final id in session.result.report.unexpectedIds) {
        summary('unexpected_id', id);
      }
    }
    return '${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
  }

  static String _cell(Object? value) {
    var text = value?.toString() ?? '';
    // Preserve spreadsheet text rather than executing barcode/filename formulas.
    if (value is String && RegExp(r'^\s*[=+@-]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  static String _text(InventorySession session) {
    final run = session.result;
    final report = run.report;
    final output = StringBuffer()
      ..writeln('SWARM MESH INVENTORY REPORT')
      ..writeln(
        '${session.datasetName}${session.isDemo ? ' — DEMO DATASET' : ''}',
      )
      ..writeln('Session: ${session.id}')
      ..writeln('UTC: ${session.createdAt.toUtc().toIso8601String()}')
      ..writeln('Leader: ${session.leaderNodeId}')
      ..writeln('Devices: ${session.devices}')
      ..writeln(
        'Items: ${report.totalLabels}; unique valid: ${report.uniqueValidCount}; '
        'duplicates: ${report.duplicateCount}; invalid: ${report.invalidCount}; unreadable: ${report.unreadableCount}',
      )
      ..writeln('Correctness match: ${session.correctnessMatch}')
      ..writeln(
        'Single: ${session.baseline.elapsed.inMicroseconds} µs; '
        '${run.mode}: ${run.elapsed.inMicroseconds} µs; speedup: ${session.speedup ?? 'not applicable'}',
      )
      ..writeln(
        'Job bytes sent/received: ${run.sentBytes}/${run.receivedBytes}',
      )
      ..writeln(
        'Failed remote attempts: ${run.retries}; contributions: ${run.contributions}',
      )
      ..writeln(session.toJson()['measurementNotes']);
    for (final measured in [session.baseline, run]) {
      output.writeln(
        'Measured phase totals (${identical(measured, session.baseline) ? 'baseline' : 'result'}):',
      );
      if (measured.diagnostics.phases.isEmpty) {
        output.writeln('Not recorded in this run.');
      }
      for (final entry in measured.diagnostics.phases.entries) {
        output.writeln(
          '${entry.key.label}: ${entry.value.microseconds} µs across '
          '${entry.value.samples} spans; max ${entry.value.maxMicroseconds} µs',
        );
      }
    }
    if (session.isDemo) {
      output.writeln(
        'Generated/sample data. Not evidence of real warehouse performance.',
      );
    }
    if (run.expectedIds.isEmpty) {
      output.writeln(
        'Missing/unexpected checks: not performed (no expected list).',
      );
    } else {
      output
        ..writeln('Missing IDs: ${report.missingExpectedIds.join(', ')}')
        ..writeln('Unexpected IDs: ${report.unexpectedIds.join(', ')}');
    }
    for (final row in session.rows) {
      output
        ..writeln(
          '\n${row.execution.image?.fileName ?? 'Text record'}: ${jsonEncode(row.execution.label.rawLabel)}',
        )
        ..writeln(
          'State: ${row.execution.label.status.name}; duplicate: ${row.duplicate}; '
          'unexpected: ${row.unexpected ?? 'not checked'}; Worker: ${row.execution.nodeId}; retries: ${row.execution.retryCount}',
        )
        ..writeln(
          'Image processing: ${row.execution.image?.elapsedMilliseconds ?? 'unknown'} ms; '
          'decode state: ${row.execution.image?.status ?? 'not an image'}',
        )
        ..writeln(
          'Attempts: ${jsonEncode(row.execution.attempts.map((attempt) => attempt.toJson()).toList())}',
        );
    }
    return output.toString();
  }
}
