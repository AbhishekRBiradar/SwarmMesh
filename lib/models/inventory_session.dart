import 'dart:math';

import 'inventory_execution.dart';
import 'inventory_models.dart';
import 'mesh_models.dart';
import 'run_diagnostics.dart';

class InventorySession {
  const InventorySession({
    required this.id,
    required this.createdAt,
    required this.datasetName,
    required this.isDemo,
    required this.leaderNodeId,
    required this.devices,
    required this.baseline,
    required this.result,
    this.benchmarkGroupId,
  });

  final String id;
  final DateTime createdAt;
  final String datasetName;
  final bool isDemo;
  final String leaderNodeId;
  final Map<String, String> devices;
  final MeshRunResult baseline;
  final MeshRunResult result;
  final String? benchmarkGroupId;
  bool get correctnessMatch => baseline.hasSameCorrectnessAs(result);
  double? get speedup =>
      correctnessMatch && result.isSwarm && result.elapsed.inMicroseconds > 0
      ? baseline.elapsed.inMicroseconds / result.elapsed.inMicroseconds
      : null;

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  factory InventorySession.capture(
    MeshRuntimeSnapshot snapshot, {
    required String datasetName,
    required bool isDemo,
    String? benchmarkGroupId,
  }) => InventorySession(
    id: newId(),
    createdAt: DateTime.now().toUtc(),
    datasetName: datasetName.trim().isEmpty
        ? 'Inventory session'
        : datasetName.trim(),
    isDemo: isDemo,
    leaderNodeId: snapshot.localTelemetry!.nodeId,
    devices: _participatingDevices(snapshot),
    baseline: snapshot.singleResult!,
    result: snapshot.swarmResult!,
    benchmarkGroupId: benchmarkGroupId,
  );

  static Map<String, String> _participatingDevices(
    MeshRuntimeSnapshot snapshot,
  ) {
    final ids = {
      for (final execution in snapshot.swarmResult!.executions)
        for (final attempt in execution.attempts) attempt.nodeId,
    };
    return Map.unmodifiable({
      snapshot.localTelemetry!.nodeId: snapshot.localTelemetry!.deviceModel,
      for (final peer in snapshot.peers)
        if (ids.contains(peer.nodeId)) peer.nodeId: peer.telemetry.deviceModel,
    });
  }

  List<InventorySessionRow> get rows {
    final seen = <String>{};
    return [
      for (final execution in result.executions)
        InventorySessionRow(
          execution: execution,
          duplicate:
              execution.label.isValid &&
              !seen.add(execution.label.normalizedId!),
          unexpected: result.expectedIds.isEmpty
              ? null
              : execution.label.isValid &&
                    !result.expectedIds.contains(execution.label.normalizedId),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'datasetName': datasetName,
    'isDemo': isDemo,
    'leaderNodeId': leaderNodeId,
    'devices': devices,
    'benchmarkGroupId': benchmarkGroupId,
    'baseline': baseline.toJson(),
    'result': result.toJson(),
    'correctnessMatch': correctnessMatch,
    'speedup': speedup,
    'summary': {
      'total': result.report.totalLabels,
      'uniqueValid': result.report.uniqueValidCount,
      'duplicates': result.report.duplicateCount,
      'invalid': result.report.invalidCount,
      'unreadable': result.report.unreadableCount,
      'expectedListProvided': result.expectedIds.isNotEmpty,
      'missingIds': result.expectedIds.isEmpty
          ? null
          : result.report.missingExpectedIds,
      'unexpectedIds': result.expectedIds.isEmpty
          ? null
          : result.report.unexpectedIds,
    },
    'records': rows.map((row) => row.toJson()).toList(),
    'measurementNotes':
        'Job bytes include application JSON/base64 or binary frames, exclude network headers/control traffic. '
        'Attempt processing times are batch durations, not per-image timings. '
        'Retries count failed remote attempts; per-record retry counts may repeat across a batch. '
        '${RunDiagnostics.measurementNote}',
  };

  factory InventorySession.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['id'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(json['id'] as String)) {
      throw const FormatException('Unsupported or invalid saved session');
    }
    return InventorySession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      datasetName: json['datasetName'] as String,
      isDemo: json['isDemo'] as bool,
      leaderNodeId: json['leaderNodeId'] as String,
      devices: Map.unmodifiable(
        Map<String, String>.from(json['devices'] as Map),
      ),
      benchmarkGroupId: json['benchmarkGroupId'] as String?,
      baseline: MeshRunResult.fromJson(
        Map<String, dynamic>.from(json['baseline'] as Map),
      ),
      result: MeshRunResult.fromJson(
        Map<String, dynamic>.from(json['result'] as Map),
      ),
    );
  }
}

class InventorySessionRow {
  const InventorySessionRow({
    required this.execution,
    required this.duplicate,
    required this.unexpected,
  });
  final InventoryExecution execution;
  final bool duplicate;
  final bool? unexpected;

  Map<String, dynamic> toJson() => {
    'imageId': execution.image?.imageId,
    'fileName': execution.image?.fileName,
    'rawLabel': execution.label.rawLabel,
    'packageId': execution.label.status == InventoryLabelStatus.valid
        ? execution.label.normalizedId
        : null,
    'normalizedValue': execution.label.normalizedId,
    'state': execution.label.status.name,
    'duplicate': duplicate,
    'unexpected': unexpected,
    'decodeState': execution.image?.status,
    'reason': execution.image?.reason ?? execution.label.reason,
    'imageProcessingMilliseconds': execution.image?.elapsedMilliseconds,
    'workerNodeId': execution.nodeId,
    'retryCount': execution.retryCount,
    'attempts': execution.attempts.map((attempt) => attempt.toJson()).toList(),
  };
}

class BenchmarkSummary {
  BenchmarkSummary(Iterable<InventorySession> sessions)
    : sessions = List.unmodifiable(sessions);
  final List<InventorySession> sessions;
  bool get comparable =>
      sessions.isNotEmpty &&
      sessions.every(
        (session) =>
            session.correctnessMatch &&
            session.baseline.sameDataset(sessions.first.baseline) &&
            _sameImages(session, sessions.first),
      );
  bool get allSwarm =>
      sessions.isNotEmpty &&
      sessions.every((session) => session.result.isSwarm);
  double get medianSingleMicroseconds => _median(
    sessions.map((session) => session.baseline.elapsed.inMicroseconds),
  );
  double get medianSwarmMicroseconds =>
      _median(sessions.map((session) => session.result.elapsed.inMicroseconds));
  double? get speedup => comparable && allSwarm && medianSwarmMicroseconds > 0
      ? medianSingleMicroseconds / medianSwarmMicroseconds
      : null;
  int get bestSwarmMicroseconds => sessions
      .map((session) => session.result.elapsed.inMicroseconds)
      .reduce(min);
  int get bestSingleMicroseconds => sessions
      .map((session) => session.baseline.elapsed.inMicroseconds)
      .reduce(min);
  int get worstSingleMicroseconds => sessions
      .map((session) => session.baseline.elapsed.inMicroseconds)
      .reduce(max);
  int get worstSwarmMicroseconds => sessions
      .map((session) => session.result.elapsed.inMicroseconds)
      .reduce(max);

  bool _sameImages(InventorySession a, InventorySession b) {
    final left = a.baseline.executions, right = b.baseline.executions;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].image?.fileName != right[i].image?.fileName ||
          left[i].image?.imageId != right[i].image?.imageId) {
        return false;
      }
    }
    return true;
  }

  static double _median(Iterable<int> input) {
    final sorted = input.toList()..sort();
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
