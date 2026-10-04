import 'inventory_models.dart';
import 'inventory_execution.dart';
import 'inventory_report.dart';
import 'math_workload.dart';
import 'node_telemetry.dart';
import 'node_performance.dart';
import 'run_diagnostics.dart';

class MeshPeer {
  const MeshPeer({
    required this.telemetry,
    required this.host,
    required this.connected,
    required this.lastSeen,
    this.completedLabels = 0,
    this.performance = const NodePerformance(),
  });

  final NodeTelemetry telemetry;
  final String host;
  final bool connected;
  final DateTime lastSeen;
  final int completedLabels;
  final NodePerformance performance;
  String get nodeId => telemetry.nodeId;

  MeshPeer copyWith({
    NodeTelemetry? telemetry,
    bool? connected,
    DateTime? lastSeen,
    int? completedLabels,
    NodePerformance? performance,
  }) => MeshPeer(
    telemetry: telemetry ?? this.telemetry,
    host: host,
    connected: connected ?? this.connected,
    lastSeen: lastSeen ?? this.lastSeen,
    completedLabels: completedLabels ?? this.completedLabels,
    performance: performance ?? this.performance,
  );
}

class MeshEndpoint {
  const MeshEndpoint({
    required this.name,
    required this.host,
    required this.port,
  });
  final String name;
  final String host;
  final int port;
  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/mesh');
}

class MeshConnectionRequest {
  const MeshConnectionRequest({
    required this.requestId,
    required this.telemetry,
    required this.host,
    required this.port,
    required this.requestedAt,
  });

  final String requestId;
  final NodeTelemetry telemetry;
  final String host;
  final int port;
  final DateTime requestedAt;

  String get nodeId => telemetry.nodeId;
  String get role => telemetry.isLeader ? 'LEADER' : 'WORKER';
}

/// End-to-end wall time includes scheduling, transport and aggregation. Worker
/// times are separate and must not be added together to claim a speedup.
class MeshRunResult {
  const MeshRunResult({
    required this.mode,
    required this.labels,
    required this.expectedIds,
    required this.results,
    required this.report,
    required this.elapsed,
    required this.contributions,
    required this.retries,
    required this.sentBytes,
    required this.receivedBytes,
    this.executions = const [],
    this.transports = const {},
    this.diagnostics = const RunDiagnostics(),
  });

  final String mode;
  final List<String> labels;
  final Set<String> expectedIds;
  final List<InventoryLabelResult> results;
  final InventoryReport report;
  final Duration elapsed;
  final Map<String, int> contributions;
  final int retries;
  final List<InventoryExecution> executions;
  final Set<String> transports;
  final RunDiagnostics diagnostics;

  /// Application job messages queued on the Leader's WebSockets for this run,
  /// including JSON/base64 or binary images and failed attempts.
  /// This measures application bytes, not confirmed delivery or network frames.
  final int sentBytes;

  /// UTF-8 JSON replies received for this run's pending jobs from their assigned
  /// workers. Control traffic, late/duplicate replies and transport headers are
  /// excluded from both counters. Single-device runs use zero.
  final int receivedBytes;
  int get totalBytes => sentBytes + receivedBytes;
  bool get isSwarm => mode == 'swarm' || mode == 'image-swarm';
  double get throughput => elapsed.inMicroseconds == 0
      ? 0
      : labels.length * 1000000 / elapsed.inMicroseconds;

  bool sameDataset(MeshRunResult other) {
    if (labels.length != other.labels.length ||
        expectedIds.length != other.expectedIds.length ||
        !expectedIds.containsAll(other.expectedIds)) {
      return false;
    }
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != other.labels[i]) return false;
    }
    return true;
  }

  bool hasSameCorrectnessAs(MeshRunResult other) {
    return sameDataset(other) && report.hasSameCorrectnessAs(other.report);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'labels': labels,
    'expectedIds': expectedIds.toList()..sort(),
    'results': results.map((result) => result.toJson()).toList(),
    'elapsedMicroseconds': elapsed.inMicroseconds,
    'contributions': contributions,
    'retries': retries,
    'sentBytes': sentBytes,
    'receivedBytes': receivedBytes,
    'executions': executions.map((item) => item.toJson()).toList(),
    'transports': transports.toList()..sort(),
    'diagnostics': diagnostics.toJson(),
  };

  factory MeshRunResult.fromJson(Map<String, dynamic> json) {
    int count(String name) {
      final value = json[name];
      if (value is! int || value < 0) throw FormatException('Invalid $name');
      return value;
    }

    final labels = List<String>.unmodifiable(json['labels'] as List);
    final expectedIds = Set<String>.from(json['expectedIds'] as List);
    final results = List<InventoryLabelResult>.unmodifiable(
      (json['results'] as List).map(
        (item) => InventoryLabelResult.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      ),
    );
    final executions = List<InventoryExecution>.unmodifiable(
      (json['executions'] as List).map(
        (item) =>
            InventoryExecution.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    final contributions = Map<String, int>.from(json['contributions'] as Map);
    if (executions.length != results.length ||
        contributions.values.any((value) => value < 0) ||
        contributions.values.fold<int>(0, (sum, value) => sum + value) !=
            results.length) {
      throw const FormatException('Incomplete saved run');
    }
    for (var index = 0; index < results.length; index++) {
      if (executions[index].label.rawLabel != results[index].rawLabel ||
          executions[index].label.status != results[index].status) {
        throw const FormatException(
          'Saved execution does not match its result',
        );
      }
    }
    return MeshRunResult(
      mode: json['mode'] as String,
      labels: labels,
      expectedIds: Set.unmodifiable(expectedIds),
      results: results,
      report: InventoryReport.aggregate(
        originalLabels: labels,
        workerBatches: [
          InventoryBatchResult(labels: results, elapsedMilliseconds: 0),
        ],
        expectedIds: expectedIds,
      ),
      elapsed: Duration(microseconds: count('elapsedMicroseconds')),
      contributions: Map.unmodifiable(contributions),
      retries: count('retries'),
      sentBytes: count('sentBytes'),
      receivedBytes: count('receivedBytes'),
      executions: executions,
      transports: Set.unmodifiable(
        List<String>.from(json['transports'] as List? ?? const []),
      ),
      diagnostics: RunDiagnostics.fromJson(
        Map<String, dynamic>.from(json['diagnostics'] as Map? ?? const {}),
      ),
    );
  }
}

class MeshRuntimeSnapshot {
  const MeshRuntimeSnapshot({
    this.active = false,
    this.starting = false,
    this.isLeader = true,
    this.running = false,
    this.localTelemetry,
    this.localPerformance = const NodePerformance(),
    this.peers = const [],
    this.endpoints = const [],
    this.addresses = const [],
    this.pendingRequests = const [],
    this.port = 4040,
    this.completedLabels = 0,
    this.totalLabels = 0,
    this.retries = 0,
    this.phase = 'STANDBY',
    this.message = 'Choose a role and start the local mesh',
    this.events = const [],
    this.result,
    this.singleResult,
    this.swarmResult,
    this.mathResult,
    this.singleMathResult,
    this.swarmMathResult,
  });

  final bool active;
  final bool starting;
  final bool isLeader;
  final bool running;
  final NodeTelemetry? localTelemetry;
  final NodePerformance localPerformance;
  final List<MeshPeer> peers;
  final List<MeshEndpoint> endpoints;
  final List<String> addresses;
  final List<MeshConnectionRequest> pendingRequests;
  final int port;
  final int completedLabels;
  final int totalLabels;
  final int retries;
  final String phase;
  final String message;
  final List<String> events;
  final MeshRunResult? result;
  final MeshRunResult? singleResult;
  final MeshRunResult? swarmResult;
  final MathRunResult? mathResult;
  final MathRunResult? singleMathResult;
  final MathRunResult? swarmMathResult;

  double get progress => totalLabels == 0 ? 0 : completedLabels / totalLabels;
  int get connectedPeers => peers.where((peer) => peer.connected).length;

  MeshRuntimeSnapshot copyWith({
    bool? active,
    bool? starting,
    bool? isLeader,
    bool? running,
    NodeTelemetry? localTelemetry,
    NodePerformance? localPerformance,
    List<MeshPeer>? peers,
    List<MeshEndpoint>? endpoints,
    List<String>? addresses,
    List<MeshConnectionRequest>? pendingRequests,
    int? port,
    int? completedLabels,
    int? totalLabels,
    int? retries,
    String? phase,
    String? message,
    List<String>? events,
    MeshRunResult? result,
    MeshRunResult? singleResult,
    MeshRunResult? swarmResult,
    MathRunResult? mathResult,
    MathRunResult? singleMathResult,
    MathRunResult? swarmMathResult,
    bool clearResults = false,
  }) {
    return MeshRuntimeSnapshot(
      active: active ?? this.active,
      starting: starting ?? this.starting,
      isLeader: isLeader ?? this.isLeader,
      running: running ?? this.running,
      localTelemetry: localTelemetry ?? this.localTelemetry,
      localPerformance: localPerformance ?? this.localPerformance,
      peers: List.unmodifiable(peers ?? this.peers),
      endpoints: List.unmodifiable(endpoints ?? this.endpoints),
      addresses: List.unmodifiable(addresses ?? this.addresses),
      pendingRequests: List.unmodifiable(
        pendingRequests ?? this.pendingRequests,
      ),
      port: port ?? this.port,
      completedLabels: completedLabels ?? this.completedLabels,
      totalLabels: totalLabels ?? this.totalLabels,
      retries: retries ?? this.retries,
      phase: phase ?? this.phase,
      message: message ?? this.message,
      events: List.unmodifiable(events ?? this.events),
      result: clearResults ? null : result ?? this.result,
      singleResult: clearResults ? null : singleResult ?? this.singleResult,
      swarmResult: clearResults ? null : swarmResult ?? this.swarmResult,
      mathResult: clearResults ? null : mathResult ?? this.mathResult,
      singleMathResult: clearResults
          ? null
          : singleMathResult ?? this.singleMathResult,
      swarmMathResult: clearResults
          ? null
          : swarmMathResult ?? this.swarmMathResult,
    );
  }
}
