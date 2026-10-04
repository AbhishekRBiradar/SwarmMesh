import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/inventory_image_models.dart';
import '../models/inventory_execution.dart';
import '../models/binary_image_job.dart';
import '../models/inventory_models.dart';
import '../models/inventory_report.dart';
import '../models/math_workload.dart';
import '../models/mesh_models.dart';
import '../models/node_telemetry.dart';
import '../models/node_performance.dart';
import '../models/work_allocation.dart';
import '../models/run_diagnostics.dart';
import 'device_telemetry_service.dart';
import 'inventory_image_service.dart';
import 'mesh_discovery_service.dart';

enum MeshRole { leader, worker }

/// Local-only mesh runtime. Every node advertises a WebSocket endpoint so a
/// Leader can discover workers; only a Leader schedules the demo workload.
class MeshRuntimeService {
  MeshRuntimeService({
    DeviceTelemetryService? telemetryService,
    MeshDiscoveryService? discoveryService,
    InventoryImageService? imageService,
  }) : _telemetryService = telemetryService ?? DeviceTelemetryService(),
       _discoveryService = discoveryService ?? MeshDiscoveryService(),
       _imageService = imageService ?? InventoryImageService();

  final DeviceTelemetryService _telemetryService;
  final MeshDiscoveryService _discoveryService;
  final InventoryImageService _imageService;
  final _snapshots = StreamController<MeshRuntimeSnapshot>.broadcast();

  MeshRuntimeSnapshot _snapshot = const MeshRuntimeSnapshot();
  MeshRole _role = MeshRole.leader;
  NodeTelemetry? _localTelemetry;
  NodePerformance _localPerformance = const NodePerformance();
  Future<void>? _telemetryRefresh;
  int _generation = 0;
  int _nextProbeId = 0;
  int _nextJobId = 0;
  int _activeWorkerJobs = 0;
  String? _nodeId;
  String? _localServiceName;
  HttpServer? _server;
  StreamSubscription<List<MeshEndpoint>>? _discoverySubscription;
  Timer? _heartbeatTimer;
  bool _starting = false;

  final _connections = <_SocketPeer>{};
  final _peers = <String, MeshPeer>{};
  final _pendingConnections = <String, _PendingConnection>{};
  final _connecting = <String>{};
  final _pendingJobs = <String, Completer<_RemoteJobResult>>{};
  final _pendingImageJobs = <String, Completer<_RemoteImageJobResult>>{};
  final _pendingMathJobs = <String, Completer<_RemoteMathJobResult>>{};
  final _jobTimers = <String, Timer>{};
  final _jobConnections = <String, _SocketPeer>{};
  final _jobTraffic = <String, _WorkloadTraffic>{};
  final _jobInputs = <String, List<String>>{};
  final _mathJobInputs = <String, List<String>>{};

  Stream<MeshRuntimeSnapshot> get snapshots => _snapshots.stream;
  MeshRuntimeSnapshot get snapshot => _snapshot;

  void setRole(MeshRole role) {
    if (_snapshot.active || _starting) return;
    _role = role;
    _replace(
      _snapshot.copyWith(
        isLeader: role == MeshRole.leader,
        message: role == MeshRole.leader
            ? 'Leader will coordinate jobs on this network'
            : 'Worker is ready to accept jobs from a Leader',
      ),
    );
  }

  Future<void> start({required MeshRole role}) async {
    if (_snapshot.active || _starting) return;
    _generation++;
    _starting = true;
    _role = role;
    _replace(
      _snapshot.copyWith(
        starting: true,
        isLeader: role == MeshRole.leader,
        phase: 'STARTING',
        message: 'Collecting resources and opening the local endpoint',
      ),
    );

    try {
      _nodeId = await _telemetryService.createNodeId();
      _localTelemetry = await _telemetryService.collectTelemetry(
        nodeId: _nodeId!,
        isLeader: role == MeshRole.leader,
      );
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        MeshDiscoveryService.servicePort,
        shared: true,
      );
      _server!.listen(_handleRequest);
      final localAddresses = await _localIpv4Addresses();

      _discoverySubscription = _discoveryService.servicesStream.listen(
        _handleEndpoints,
      );
      _localServiceName = await _discoveryService.registerNode(
        nodeId: _nodeId!,
        port: MeshDiscoveryService.servicePort,
      );
      await _discoveryService.startDiscovery();

      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_sendHeartbeats()),
      );
      _starting = false;
      _replace(
        _snapshot.copyWith(
          active: true,
          starting: false,
          localTelemetry: _localTelemetry,
          addresses: localAddresses,
          port: MeshDiscoveryService.servicePort,
          phase: 'RADAR ACTIVE',
          message: role == MeshRole.leader
              ? 'Leader is discovering nearby workers'
              : 'Worker is visible and waiting for jobs',
        ),
      );
      _addEvent(
        'Advertised $_localServiceName on port ${MeshDiscoveryService.servicePort}',
      );
    } catch (error) {
      _starting = false;
      await _cleanup();
      _replace(
        const MeshRuntimeSnapshot(
          phase: 'ERROR',
          message:
              'Could not start the local mesh. Check Wi-Fi/hotspot access.',
        ),
      );
      _addEvent('$error');
    }
  }

  Future<void> stop() async {
    if (!_snapshot.active && !_starting && _server == null) return;
    _starting = false;
    await _cleanup();
    _replace(
      MeshRuntimeSnapshot(
        isLeader: _role == MeshRole.leader,
        phase: 'STANDBY',
        message: 'Mesh stopped. Choose a role and start again.',
      ),
    );
  }

  /// Lets a Leader connect when hotspot isolation prevents NSD discovery.
  Future<void> connectManually(
    String host, {
    int port = MeshDiscoveryService.servicePort,
  }) async {
    if (!_snapshot.active) return;
    final endpoint = MeshEndpoint(
      name: 'Manual $host',
      host: host.trim(),
      port: port,
    );
    await _connect(endpoint);
  }

  Future<void> approveConnection(String requestId) async {
    final pending = _pendingConnections.remove(requestId);
    if (pending == null) return;

    pending.connection.authorized = true;
    _send(pending.connection, 'connection_response', {
      'requestId': requestId,
      'approved': true,
    });
    _sendHello(pending.connection);
    _publishPendingConnections();
    _addEvent('Approved connection from ${pending.request.nodeId}');
  }

  Future<void> rejectConnection(String requestId) async {
    final pending = _pendingConnections.remove(requestId);
    if (pending == null) return;

    _send(pending.connection, 'connection_response', {
      'requestId': requestId,
      'approved': false,
      'reason': 'Connection rejected on this device',
    });
    _publishPendingConnections();
    _addEvent('Rejected connection from ${pending.request.nodeId}');
    await pending.connection.socket.close(
      WebSocketStatus.policyViolation,
      'Connection rejected',
    );
  }

  Future<void> _runWorkload(Future<void> Function(int) body) async {
    if (!_snapshot.active || _role != MeshRole.leader || _snapshot.running) {
      return;
    }
    final generation = _generation;
    _replace(
      _snapshot.copyWith(
        running: true,
        phase: 'PREPARING BASELINE',
        message:
            'Refreshing device resources before the single-device baseline',
        clearResults: true,
        completedLabels: 0,
        totalLabels: 0,
        retries: 0,
      ),
    );
    try {
      await _refreshLocalTelemetry();
      _requireRun(generation);
      _requireLocalCompute();
      await body(generation);
    } catch (error) {
      if (_generation == generation && _snapshot.active) {
        _replace(
          _snapshot.copyWith(
            running: false,
            phase: 'WORKLOAD STOPPED',
            message: _short(error),
          ),
        );
        _addEvent('Workload stopped: ${_short(error)}');
      }
    } finally {
      if (_generation == generation && _snapshot.running) {
        _replace(_snapshot.copyWith(running: false));
      }
    }
  }

  void _requireRun(int generation) {
    if (_generation != generation || !_snapshot.active) {
      throw StateError('Mesh stopped');
    }
  }

  void _requireLocalCompute() {
    final reason = _localTelemetry?.computePauseReason;
    if (reason != null) throw StateError('Leader compute paused: $reason');
  }

  Future<void> runDemoWorkload() => _runWorkload(_runDemoWorkload);

  Future<void> runMathWorkload(MathProblem problem) =>
      _runWorkload((generation) => _runMathWorkload(generation, problem));

  Future<void> _runDemoWorkload(int generation) async {
    final labels = _demoLabels();
    final expectedIds = {
      for (var index = 1; index <= 849; index++)
        'PKG-${index.toString().padLeft(6, '0')}',
    };
    final localStart = Stopwatch()..start();
    final local = InventoryProcessor.process(labels);
    final localProcessing = localStart.elapsed;
    _recordLocalTask(WorkloadKind.labels, localProcessing, labels.length);
    final localResult = _runResult(
      mode: 'single-device',
      labels: labels,
      expectedIds: expectedIds,
      batches: [local],
      elapsed: localStart.elapsed,
      watch: localStart,
      contributions: {_nodeId ?? 'local': labels.length},
      retries: 0,
      sentBytes: 0,
      receivedBytes: 0,
      executions: _labelExecutions(local, _nodeId!, [
        InventoryAttempt(
          nodeId: _nodeId!,
          succeeded: true,
          processingMicroseconds: localProcessing.inMicroseconds,
        ),
      ]),
    );

    final started = Stopwatch()..start();
    final targets = _workTargets(WorkloadKind.labels, labels.length);
    final chunks = _split(labels, targets);
    final workers = chunks.where((chunk) => !chunk.target.isLocal).toList();

    _replace(
      _snapshot.copyWith(
        running: true,
        phase: 'DISTRIBUTING',
        message: workers.isEmpty
            ? 'No eligible Workers assigned; processing on this device'
            : 'Split ${labels.length} labels across ${targets.length} weighted nodes',
        completedLabels: 0,
        totalLabels: labels.length,
        retries: 0,
        singleResult: localResult,
      ),
    );
    _addEvent(
      workers.isEmpty
          ? 'Benchmark fallback: no eligible Worker was assigned'
          : 'Distributed batch assigned to ${workers.length} worker(s)',
    );

    final traffic = _WorkloadTraffic();
    final completed = await Future.wait(
      chunks.map(
        (chunk) => _runChunk(chunk.target, chunk.items, traffic, generation),
      ),
    );
    _requireRun(generation);

    final contributions = _contributions(
      completed.expand((item) => item.executions),
    );
    final swarmResult = _runResult(
      mode: contributions.keys.any((id) => id != _nodeId)
          ? 'swarm'
          : 'local-fallback',
      labels: labels,
      expectedIds: expectedIds,
      batches: [for (final item in completed) item.result],
      elapsed: started.elapsed,
      watch: started,
      contributions: contributions,
      retries: traffic.retries,
      sentBytes: traffic.sentBytes,
      receivedBytes: traffic.receivedBytes,
      executions: [for (final item in completed) ...item.executions],
      transports: traffic.transports,
    );
    _replace(
      _snapshot.copyWith(
        running: false,
        phase: 'COMPLETE',
        message: _summary(swarmResult),
        swarmResult: swarmResult,
        result: swarmResult,
      ),
    );
    _addEvent(
      'Completed in ${started.elapsedMilliseconds} ms; '
      'single baseline ${localStart.elapsedMilliseconds} ms',
    );
  }

  Future<void> _runMathWorkload(int generation, MathProblem problem) async {
    final tasks = MathWorkloadEngine.createTasks(problem);
    final localWatch = Stopwatch()..start();
    final localResults = MathWorkloadEngine.process(problem, tasks);
    localWatch.stop();
    _recordLocalTask(
      WorkloadKind.mathematics,
      localWatch.elapsed,
      tasks.length,
    );
    final localResult = _mathRunResult(
      mode: 'math-single-device',
      problem: problem,
      tasks: tasks,
      results: localResults,
      elapsed: localWatch.elapsed,
      contributions: {_nodeId ?? 'local': tasks.length},
      retries: 0,
      sentBytes: 0,
      receivedBytes: 0,
    );

    await _refreshLocalTelemetry();
    _requireRun(generation);
    _requireLocalCompute();
    final watch = Stopwatch()..start();
    final traffic = _WorkloadTraffic();
    final targets = _workTargets(WorkloadKind.mathematics, tasks.length);
    final chunks = _split(tasks, targets);
    final workers = chunks.where((chunk) => !chunk.target.isLocal).toList();
    _replace(
      _snapshot.copyWith(
        phase: 'DISTRIBUTING MATHEMATICS',
        message: workers.isEmpty
            ? 'No eligible Workers assigned; solving on this device'
            : 'Split ${tasks.length} mathematical tasks across ${targets.length} nodes',
        completedLabels: 0,
        totalLabels: tasks.length,
        retries: 0,
        singleMathResult: localResult,
      ),
    );
    _addEvent(
      workers.isEmpty
          ? 'Mathematical workload fallback: no eligible Worker was assigned'
          : 'Mathematical workload assigned to ${workers.length} Worker(s)',
    );

    final completed = await Future.wait(
      chunks.map(
        (chunk) => _runMathChunk(
          problem,
          chunk.target,
          chunk.items,
          traffic,
          generation,
        ),
      ),
    );
    _requireRun(generation);
    final results = [for (final item in completed) ...item.results];
    final contributions = <String, int>{};
    for (final item in completed) {
      contributions.update(
        item.nodeId,
        (count) => count + item.results.length,
        ifAbsent: () => item.results.length,
      );
    }
    final swarmResult = _mathRunResult(
      mode: contributions.keys.any((id) => id != _nodeId)
          ? 'math-swarm'
          : 'math-local-fallback',
      problem: problem,
      tasks: tasks,
      results: results,
      elapsed: watch.elapsed,
      contributions: contributions,
      retries: traffic.retries,
      sentBytes: traffic.sentBytes,
      receivedBytes: traffic.receivedBytes,
    );
    _replace(
      _snapshot.copyWith(
        running: false,
        phase: 'MATHEMATICS COMPLETE',
        message: _mathSummary(swarmResult),
        mathResult: swarmResult,
        swarmMathResult: swarmResult,
      ),
    );
    _addEvent(
      '${problem.title} completed in ${watch.elapsedMilliseconds} ms; '
      'single baseline ${localWatch.elapsedMilliseconds} ms',
    );
  }

  Future<void> runImageWorkload(
    List<String> paths, {
    Iterable<String> expectedIds = const [],
  }) => _runWorkload(
    (generation) => _runImageWorkload(
      generation,
      List.of(paths),
      expectedIds: expectedIds.toSet(),
    ),
  );

  Future<void> _runImageWorkload(
    int generation,
    List<String> paths, {
    required Iterable<String> expectedIds,
  }) async {
    if (paths.isEmpty) {
      _replace(_snapshot.copyWith(phase: 'NO IMAGES'));
      _addEvent('Select at least one label image before starting');
      return;
    }

    final tasks = <InventoryImageTask>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        tasks.add(
          InventoryImageTask.fromPath(
            path,
            imageId: 'IMAGE-${tasks.length + 1}',
          ),
        );
      }
    }
    if (tasks.isEmpty) {
      _replace(_snapshot.copyWith(phase: 'NO IMAGES'));
      _addEvent('The selected image files are no longer available');
      return;
    }

    final expected = expectedIds.toSet();
    _requireRun(generation);
    _replace(
      _snapshot.copyWith(
        phase: 'BASELINE DECODING',
        message:
            'Decoding ${tasks.length} images on the Leader for the reference run',
        totalLabels: tasks.length,
      ),
    );
    final baselineProfile = RunProfiler();
    final localWatch = Stopwatch()..start();
    final localImages = await baselineProfile.measure(
      RunPhase.localProcessing,
      () => _imageService.decodeFiles(tasks),
    );
    final localProcessing = localWatch.elapsed;
    _requireRun(generation);
    if (localImages.every((result) => result.status != 'error')) {
      _recordLocalTask(WorkloadKind.images, localProcessing, tasks.length);
    }
    final localResult = _imageRunResult(
      mode: 'single-device',
      imageResults: localImages,
      expectedIds: expected,
      elapsed: localWatch.elapsed,
      watch: localWatch,
      profiler: baselineProfile,
      contributions: {_nodeId ?? 'local': tasks.length},
      retries: 0,
      sentBytes: 0,
      receivedBytes: 0,
      executions: _imageExecutions(localImages, _nodeId!, [
        InventoryAttempt(
          nodeId: _nodeId!,
          succeeded: true,
          processingMicroseconds: localProcessing.inMicroseconds,
        ),
      ]),
    );

    await _refreshLocalTelemetry();
    _requireRun(generation);
    _requireLocalCompute();
    final watch = Stopwatch()..start();
    final traffic = _WorkloadTraffic();
    final scheduleWatch = Stopwatch()..start();
    final targets = _workTargets(WorkloadKind.images, tasks.length);
    final chunks = _split(tasks, targets);
    final workers = chunks.where((chunk) => !chunk.target.isLocal).toList();
    traffic.profiler.record(RunPhase.scheduling, scheduleWatch.elapsed);

    _replace(
      _snapshot.copyWith(
        running: true,
        phase: 'DISTRIBUTING IMAGES',
        message: workers.isEmpty
            ? 'No eligible Workers assigned; decoding on this device'
            : 'Splitting ${tasks.length} images across ${targets.length} nodes',
        completedLabels: 0,
        totalLabels: tasks.length,
        retries: 0,
        singleResult: localResult,
      ),
    );
    _addEvent(
      workers.isEmpty
          ? 'Image benchmark fallback: no eligible Worker was assigned'
          : 'Image decode batch assigned to ${workers.length} Worker(s)',
    );

    final completed = await Future.wait(
      chunks.map(
        (chunk) =>
            _runImageChunk(chunk.target, chunk.items, traffic, generation),
      ),
    );
    _requireRun(generation);
    final imageResults = [for (final item in completed) ...item.results];
    final contributions = _contributions(
      completed.expand((item) => item.executions),
    );
    final swarmResult = _imageRunResult(
      mode: contributions.keys.any((id) => id != _nodeId)
          ? 'image-swarm'
          : 'image-local-fallback',
      imageResults: imageResults,
      expectedIds: expected,
      elapsed: watch.elapsed,
      watch: watch,
      contributions: contributions,
      retries: traffic.retries,
      sentBytes: traffic.sentBytes,
      receivedBytes: traffic.receivedBytes,
      executions: [for (final item in completed) ...item.executions],
      transports: traffic.transports,
      profiler: traffic.profiler,
    );
    _replace(
      _snapshot.copyWith(
        running: false,
        phase: 'IMAGE REPORT READY',
        message: _summary(swarmResult),
        swarmResult: swarmResult,
        result: swarmResult,
      ),
    );
    _addEvent(
      'Image workload completed in ${watch.elapsedMilliseconds} ms; '
      'single baseline ${localWatch.elapsedMilliseconds} ms',
    );
  }

  Future<void> dispose() async {
    await stop();
    await _discoveryService.dispose();
    await _imageService.dispose();
    await _snapshots.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('SwarmMesh WebSocket endpoint');
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final host = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      _attach(socket, host, MeshDiscoveryService.servicePort);
    } catch (_) {
      await request.response.close();
    }
  }

  void _handleEndpoints(List<MeshEndpoint> endpoints) {
    final visible = endpoints
        .where((endpoint) => endpoint.name != _localServiceName)
        .toList(growable: false);
    _replace(_snapshot.copyWith(endpoints: visible));
    if (_role == MeshRole.leader) {
      for (final endpoint in visible) {
        unawaited(_connect(endpoint));
      }
    }
  }

  Future<void> _connect(MeshEndpoint endpoint) async {
    final key = '${endpoint.host}:${endpoint.port}';
    if (_isConnected(endpoint.host, endpoint.port) || !_connecting.add(key)) {
      return;
    }
    try {
      final socket = await WebSocket.connect(_uri(endpoint.host, endpoint.port))
          .timeout(const Duration(seconds: 4));
      socket.pingInterval = const Duration(seconds: 15);
      _attach(socket, endpoint.host, endpoint.port);
      _addEvent('Connected to ${endpoint.name}');
    } catch (error) {
      _addEvent('Could not connect to ${endpoint.host}: ${_short(error)}');
    } finally {
      _connecting.remove(key);
    }
  }

  void _attach(WebSocket socket, String host, int port) {
    final connection = _SocketPeer(socket: socket, host: host, port: port);
    _connections.add(connection);
    socket.listen(
      (data) => _receive(connection, data),
      onDone: () => _remove(connection),
      onError: (Object error, StackTrace stack) => _remove(connection),
      cancelOnError: true,
    );
    final requestId = 'REQ-${DateTime.now().microsecondsSinceEpoch}';
    connection.requestId = requestId;
    _send(connection, 'connection_request', {
      'requestId': requestId,
      'nodeId': _nodeId,
      'role': _role.name,
      'telemetry': _localTelemetry?.toJson(),
    });
  }

  void _receive(_SocketPeer connection, dynamic data) {
    if (data is List<int>) {
      if (!connection.authorized) return;
      try {
        final job = BinaryImageJob.decode(
          data is Uint8List ? data : Uint8List.fromList(data),
        );
        unawaited(
          _executeJob(connection, {
            'jobId': job.jobId,
          }, binaryImages: job.images),
        );
      } catch (error) {
        _addEvent('Rejected binary image job: ${_short(error)}');
      }
      return;
    }
    if (data is! String) return;
    try {
      final message = jsonDecode(data);
      if (message is! Map || message['version'] != 1) return;
      final type = message['type'] as String?;
      final payload = message['payload'] is Map
          ? Map<String, dynamic>.from(message['payload'] as Map)
          : <String, dynamic>{};
      switch (type) {
        case 'connection_request':
          _handleConnectionRequest(connection, payload);
        case 'connection_response':
          _handleConnectionResponse(connection, payload);
        case 'hello':
          _hello(connection, payload, acknowledged: false);
        case 'hello_ack':
          _hello(connection, payload, acknowledged: true);
        case 'heartbeat':
          if (!connection.authorized) return;
          _touch(connection, payload: payload);
          _send(connection, 'heartbeat_ack', {
            if (payload['probeId'] is String) 'probeId': payload['probeId'],
            'telemetry': _localTelemetry?.toJson(),
          });
        case 'heartbeat_ack':
          if (!connection.authorized) return;
          _receiveHeartbeatAck(connection, payload);
        case 'job':
          if (!connection.authorized) return;
          unawaited(_executeJob(connection, payload));
        case 'job_result':
          if (!connection.authorized) return;
          _jobResult(connection, payload, utf8.encode(data).length);
      }
    } catch (error) {
      _addEvent('Rejected malformed mesh message: ${_short(error)}');
    }
  }

  void _handleConnectionRequest(
    _SocketPeer connection,
    Map<String, dynamic> payload,
  ) {
    final requestId = payload['requestId'] as String?;
    if (requestId == null || _pendingConnections.containsKey(requestId)) {
      return;
    }

    final rawTelemetry = payload['telemetry'];
    final role = payload['role'] as String?;
    final telemetry = rawTelemetry is Map
        ? NodeTelemetry.fromJson(Map<String, dynamic>.from(rawTelemetry))
        : NodeTelemetry(
            nodeId: payload['nodeId'] as String? ?? 'UNKNOWN',
            deviceModel: 'Remote Android Device',
            batteryLevel: 0,
            batteryLevelKnown: false,
            cpuCores: 1,
            computeWeight: 1,
            isLeader: role == MeshRole.leader.name,
            status: 'REQUESTING',
            timestamp: DateTime.now(),
          );
    final request = MeshConnectionRequest(
      requestId: requestId,
      telemetry: telemetry,
      host: connection.host,
      port: connection.port,
      requestedAt: DateTime.now(),
    );
    connection.requestId = requestId;
    connection.nodeId = telemetry.nodeId;
    _pendingConnections[requestId] = _PendingConnection(
      request: request,
      connection: connection,
    );
    _publishPendingConnections();
    _addEvent('Connection permission requested by ${telemetry.nodeId}');
  }

  void _handleConnectionResponse(
    _SocketPeer connection,
    Map<String, dynamic> payload,
  ) {
    final requestId = payload['requestId'] as String?;
    if (requestId == null || requestId != connection.requestId) return;

    if (payload['approved'] != true) {
      _addEvent('Connection request was rejected by the other device');
      unawaited(
        connection.socket.close(
          WebSocketStatus.policyViolation,
          'Connection rejected',
        ),
      );
      return;
    }

    connection.authorized = true;
    _sendHello(connection);
    _addEvent('Connection approved; completing device handshake');
  }

  void _sendHello(_SocketPeer connection) {
    _send(connection, 'hello', {
      'nodeId': _nodeId,
      'role': _role.name,
      'telemetry': _localTelemetry?.toJson(),
      'capabilities': [BinaryImageJob.capability],
    });
  }

  void _hello(
    _SocketPeer connection,
    Map<String, dynamic> payload, {
    required bool acknowledged,
  }) {
    if (!connection.authorized) return;
    final rawTelemetry = payload['telemetry'];
    final telemetry = rawTelemetry is Map
        ? NodeTelemetry.fromJson(Map<String, dynamic>.from(rawTelemetry))
        : null;
    final nodeId = telemetry?.nodeId ?? payload['nodeId'] as String?;
    if (nodeId == null || nodeId == _nodeId) return;
    connection.nodeId = nodeId;
    connection.supportsBinaryImages =
        payload['capabilities'] is List &&
        (payload['capabilities'] as List).contains(BinaryImageJob.capability);
    final actualTelemetry =
        telemetry ??
        NodeTelemetry(
          nodeId: nodeId,
          deviceModel: 'Remote Android Device',
          batteryLevel: 0,
          batteryLevelKnown: false,
          cpuCores: 1,
          computeWeight: 1,
          isLeader: false,
          status: 'CONNECTED',
          timestamp: DateTime.now(),
        );
    _peers[nodeId] = MeshPeer(
      telemetry: actualTelemetry,
      host: connection.host,
      connected: true,
      lastSeen: DateTime.now(),
      performance: _peers[nodeId]?.connected == true
          ? _peers[nodeId]!.performance
          : const NodePerformance(),
      completedLabels: _peers[nodeId]?.connected == true
          ? _peers[nodeId]!.completedLabels
          : 0,
    );
    _publishPeers();
    _addEvent(
      '${acknowledged ? 'Handshake confirmed with' : 'Discovered'} $nodeId',
    );
    if (!acknowledged) {
      _sendHelloAck(connection);
    }
    _sendProbe(connection);
  }

  void _sendHelloAck(_SocketPeer connection) {
    _send(connection, 'hello_ack', {
      'nodeId': _nodeId,
      'role': _role.name,
      'telemetry': _localTelemetry?.toJson(),
      'capabilities': [BinaryImageJob.capability],
    });
  }

  Future<void> _executeJob(
    _SocketPeer connection,
    Map<String, dynamic> payload, {
    List<InventoryImageTask>? binaryImages,
  }) async {
    final jobId = payload['jobId'] as String?;
    if (jobId == null) return;
    final generation = _generation;
    try {
      await _refreshLocalTelemetry();
    } catch (error) {
      if (_generation == generation) {
        _send(connection, 'job_result', {
          'jobId': jobId,
          'error': 'Telemetry unavailable',
        });
        _addEvent('Worker telemetry unavailable: ${_short(error)}');
      }
      return;
    }
    if (_generation != generation || !_connections.contains(connection)) return;
    final pauseReason = _localTelemetry?.computePauseReason;
    if (pauseReason != null) {
      _send(connection, 'job_result', {
        'jobId': jobId,
        'error': pauseReason,
        'telemetry': _localTelemetry?.toJson(),
      });
      _addEvent('Worker compute paused: $pauseReason');
      return;
    }

    final rawImages = payload['images'];
    if (rawImages is List || binaryImages != null) {
      var completed = 0;
      _beginWorkerBatch(binaryImages?.length ?? (rawImages as List).length);
      try {
        final tasks =
            binaryImages ??
            (rawImages as List)
                .whereType<Map>()
                .map(
                  (item) => InventoryImageTask.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false);
        final watch = Stopwatch()..start();
        final results = await _imageService.decodeFiles(tasks);
        watch.stop();
        if (_generation != generation) return;
        completed = results.length;
        if (results.every((result) => result.status != 'error')) {
          _recordLocalTask(WorkloadKind.images, watch.elapsed, tasks.length);
        }
        _send(connection, 'job_result', {
          'jobId': jobId,
          'kind': 'images',
          'results': results.map((result) => result.toJson()).toList(),
          'processingMicroseconds': watch.elapsedMicroseconds,
          'telemetry': _localTelemetry?.toJson(),
        });
        _addEvent('Worker decoded ${results.length} images');
      } catch (error) {
        if (_generation == generation) {
          _send(connection, 'job_result', {
            'jobId': jobId,
            'error': _short(error),
          });
          _addEvent('Worker image decode failed: ${_short(error)}');
        }
      } finally {
        _finishWorkerBatch(completed, generation);
      }
      return;
    }

    if (payload['kind'] == 'math') {
      final problemId = payload['problem'];
      final rawTasks = payload['tasks'];
      if (problemId is! String || rawTasks is! List) return;
      var completed = 0;
      _beginWorkerBatch(rawTasks.length);
      try {
        final problem = MathProblem.fromId(problemId);
        final tasks = [
          for (final item in rawTasks)
            MathTask.fromJson(Map<String, dynamic>.from(item as Map)),
        ];
        final watch = Stopwatch()..start();
        final results = MathWorkloadEngine.process(problem, tasks);
        watch.stop();
        if (_generation != generation) return;
        completed = results.length;
        _recordLocalTask(WorkloadKind.mathematics, watch.elapsed, tasks.length);
        _send(connection, 'job_result', {
          'jobId': jobId,
          'kind': 'math',
          'problem': problem.id,
          'results': results.map((result) => result.toJson()).toList(),
          'processingMicroseconds': watch.elapsedMicroseconds,
          'telemetry': _localTelemetry?.toJson(),
        });
        _addEvent('Worker completed ${results.length} mathematical tasks');
      } catch (error) {
        if (_generation == generation) {
          _send(connection, 'job_result', {
            'jobId': jobId,
            'error': _short(error),
          });
          _addEvent('Worker mathematical job failed: ${_short(error)}');
        }
      } finally {
        _finishWorkerBatch(completed, generation);
      }
      return;
    }

    final labels = payload['labels'];
    if (labels is! List) return;
    _beginWorkerBatch(labels.length);
    final watch = Stopwatch()..start();
    final result = InventoryProcessor.process(labels.map((item) => '$item'));
    watch.stop();
    _recordLocalTask(WorkloadKind.labels, watch.elapsed, labels.length);
    _send(connection, 'job_result', {
      'jobId': jobId,
      'kind': 'labels',
      'result': result.toJson(),
      'processingMicroseconds': watch.elapsedMicroseconds,
      'telemetry': _localTelemetry?.toJson(),
    });
    _addEvent('Worker processed ${result.labels.length} labels');
    _finishWorkerBatch(result.labels.length, generation);
  }

  void _beginWorkerBatch(int count) {
    if (_role != MeshRole.worker) return;
    final first = _activeWorkerJobs++ == 0;
    _replace(
      _snapshot.copyWith(
        running: true,
        phase: 'WORKER PROCESSING',
        totalLabels: first ? count : _snapshot.totalLabels + count,
        completedLabels: first ? 0 : _snapshot.completedLabels,
        message: 'Processing assigned work on this phone',
      ),
    );
  }

  void _finishWorkerBatch(int completed, int generation) {
    if (_role != MeshRole.worker || generation != _generation) return;
    _activeWorkerJobs--;
    _replace(
      _snapshot.copyWith(
        running: _activeWorkerJobs > 0,
        completedLabels: _snapshot.completedLabels + completed,
        phase: _activeWorkerJobs > 0 ? 'WORKER PROCESSING' : 'WORKER READY',
        message: _activeWorkerJobs > 0
            ? 'Processing assigned work on this phone'
            : 'Batch finished; waiting for the next assignment',
      ),
    );
  }

  void _jobResult(
    _SocketPeer connection,
    Map<String, dynamic> payload,
    int receivedBytes,
  ) {
    final jobId = payload['jobId'] as String?;
    if (jobId == null || _jobConnections[jobId] != connection) return;
    _jobTimers.remove(jobId)?.cancel();
    _jobConnections.remove(jobId);
    final traffic = _jobTraffic.remove(jobId);
    if (traffic != null) traffic.receivedBytes += receivedBytes;
    final imageCompleter = _pendingImageJobs.remove(jobId);
    final inputs = _jobInputs.remove(jobId) ?? const <String>[];
    final labelCompleter = _pendingJobs.remove(jobId);
    final mathCompleter = _pendingMathJobs.remove(jobId);
    final mathInputs = _mathJobInputs.remove(jobId) ?? const <String>[];

    // Complete malformed replies with an error so local recovery can run and
    // the traffic already used by the failed attempt stays in the run totals.
    try {
      _touch(connection, payload: payload);
      if (mathCompleter != null) {
        final rawResults = payload['results'];
        final problemId = payload['problem'];
        if (payload['kind'] != 'math' ||
            problemId is! String ||
            rawResults is! List ||
            rawResults.length != mathInputs.length ||
            rawResults.any((item) => item is! Map)) {
          throw const FormatException(
            'Worker returned an invalid mathematical batch',
          );
        }
        final results = [
          for (final item in rawResults)
            MathTaskResult.fromJson(Map<String, dynamic>.from(item as Map)),
        ];
        for (var index = 0; index < results.length; index++) {
          if (results[index].taskId != mathInputs[index]) {
            throw const FormatException(
              'Worker returned different mathematical task IDs',
            );
          }
        }
        _recordPeerTask(
          connection,
          WorkloadKind.mathematics,
          results.length,
          payload['processingMicroseconds'],
        );
        mathCompleter.complete(
          _RemoteMathJobResult(
            results,
            processingMicroseconds: _processingTime(payload),
          ),
        );
        return;
      }
      if (imageCompleter != null) {
        final rawResults = payload['results'];
        if (payload['kind'] != 'images' ||
            rawResults is! List ||
            inputs.length != rawResults.length ||
            rawResults.any((item) => item is! Map)) {
          throw const FormatException('Worker returned an invalid image batch');
        }
        final results = [
          for (final item in rawResults)
            InventoryImageDecodeResult.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
        ];
        for (var index = 0; index < inputs.length; index++) {
          if (results[index].imageId != inputs[index]) {
            throw const FormatException('Worker returned different image IDs');
          }
        }
        if (results.any((result) => result.status == 'error')) {
          throw StateError('Worker could not decode the image batch');
        }
        _recordPeerTask(
          connection,
          WorkloadKind.images,
          inputs.length,
          results.every((result) => result.status != 'error')
              ? payload['processingMicroseconds']
              : null,
        );
        imageCompleter.complete(
          _RemoteImageJobResult(
            results,
            processingMicroseconds: _processingTime(payload),
          ),
        );
        return;
      }

      if (labelCompleter != null) {
        final rawResult = payload['result'];
        if ((payload['kind'] ?? 'labels') != 'labels' || rawResult is! Map) {
          throw const FormatException('Worker returned an invalid label batch');
        }
        final result = InventoryBatchResult.fromJson(
          Map<String, dynamic>.from(rawResult),
        );
        InventoryReport.aggregate(
          originalLabels: inputs,
          workerBatches: [result],
          expectedIds: const [],
        );
        _recordPeerTask(
          connection,
          WorkloadKind.labels,
          inputs.length,
          payload['processingMicroseconds'],
        );
        labelCompleter.complete(
          _RemoteJobResult(
            result,
            processingMicroseconds: _processingTime(payload),
          ),
        );
      }
    } catch (error, stack) {
      imageCompleter?.completeError(error, stack);
      labelCompleter?.completeError(error, stack);
      mathCompleter?.completeError(error, stack);
    }
  }

  Future<_CompletedImageChunk> _runImageChunk(
    _WorkTarget target,
    List<InventoryImageTask> tasks,
    _WorkloadTraffic traffic,
    int generation,
  ) async {
    final executions = <InventoryExecution>[];
    // Commit each successful batch once. Recovery never discards earlier work.
    for (var start = 0; start < tasks.length;) {
      final preparationWatch = Stopwatch()..start();
      var end = start;
      var byteCount = 0;
      while (end < tasks.length && end - start < 4) {
        final task = tasks[end];
        var size = task.bytes?.length ?? 0;
        if (task.localPath != null) {
          try {
            size = await File(task.localPath!).length();
          } catch (_) {
            /* Decoder reports file errors. */
          }
        } else if (task.bytesBase64 != null) {
          size = base64Decode(task.bytesBase64!).length;
        }
        if (end > start && byteCount + size > 8 * 1024 * 1024) break;
        byteCount += size;
        end++;
      }
      final oversized =
          byteCount >
          BinaryImageJob.maxFrameBytes - BinaryImageJob.maxHeaderBytes - 8;
      if (oversized && !target.isLocal) {
        _addEvent('Image exceeds transfer limit; decoding this batch locally');
      }
      final batch = tasks.sublist(start, end);
      traffic.profiler.record(
        RunPhase.batchPreparation,
        preparationWatch.elapsed,
      );
      final outcome = await _recover<_RemoteImageJobResult>(
        target: oversized ? const _WorkTarget.local(1) : target,
        kind: WorkloadKind.images,
        itemCount: batch.length,
        traffic: traffic,
        generation: generation,
        remote: (connection) => _dispatchImages(connection, batch, traffic),
        local: () async {
          await traffic.profiler.measure(
            RunPhase.telemetry,
            _refreshLocalTelemetry,
          );
          _requireRun(generation);
          _requireLocalCompute();
          final watch = Stopwatch()..start();
          final results = await traffic.profiler.measure(
            RunPhase.localProcessing,
            () => _imageService.decodeFiles(batch),
          );
          watch.stop();
          _requireRun(generation);
          if (results.every((result) => result.status != 'error')) {
            _recordLocalTask(WorkloadKind.images, watch.elapsed, batch.length);
          }
          return _RemoteImageJobResult(
            results,
            processingMicroseconds: watch.elapsedMicroseconds,
          );
        },
        processingTime: (value) => value.processingMicroseconds,
      );
      executions.addAll(
        _imageExecutions(
          [
            for (var i = 0; i < batch.length; i++)
              InventoryImageDecodeResult(
                imageId: batch[i].imageId,
                fileName: batch[i].fileName,
                decodedValue: outcome.value.results[i].decodedValue,
                status: outcome.value.results[i].status,
                reason: outcome.value.results[i].reason,
                elapsedMilliseconds:
                    outcome.value.results[i].elapsedMilliseconds,
              ),
          ],
          outcome.nodeId,
          outcome.attempts,
        ),
      );
      _updateProgress(batch.length);
      start = end;
    }
    return _CompletedImageChunk(List.unmodifiable(executions));
  }

  Future<_CompletedChunk> _runChunk(
    _WorkTarget target,
    List<String> labels,
    _WorkloadTraffic traffic,
    int generation,
  ) async {
    final outcome = await _recover<_RemoteJobResult>(
      target: target,
      kind: WorkloadKind.labels,
      itemCount: labels.length,
      traffic: traffic,
      generation: generation,
      remote: (connection) => _dispatch(connection, labels, traffic),
      local: () async {
        await _refreshLocalTelemetry();
        _requireRun(generation);
        _requireLocalCompute();
        final watch = Stopwatch()..start();
        final result = InventoryProcessor.process(labels);
        watch.stop();
        _recordLocalTask(WorkloadKind.labels, watch.elapsed, labels.length);
        return _RemoteJobResult(
          result,
          processingMicroseconds: watch.elapsedMicroseconds,
        );
      },
      processingTime: (value) => value.processingMicroseconds,
    );
    _updateProgress(labels.length);
    return _CompletedChunk(
      outcome.value.result,
      _labelExecutions(outcome.value.result, outcome.nodeId, outcome.attempts),
    );
  }

  Future<_CompletedMathChunk> _runMathChunk(
    MathProblem problem,
    _WorkTarget target,
    List<MathTask> tasks,
    _WorkloadTraffic traffic,
    int generation,
  ) async {
    final outcome = await _recover<_RemoteMathJobResult>(
      target: target,
      kind: WorkloadKind.mathematics,
      itemCount: tasks.length,
      traffic: traffic,
      generation: generation,
      remote: (connection) =>
          _dispatchMath(connection, problem, tasks, traffic),
      local: () async {
        await _refreshLocalTelemetry();
        _requireRun(generation);
        _requireLocalCompute();
        final watch = Stopwatch()..start();
        final results = MathWorkloadEngine.process(problem, tasks);
        watch.stop();
        _recordLocalTask(WorkloadKind.mathematics, watch.elapsed, tasks.length);
        return _RemoteMathJobResult(
          results,
          processingMicroseconds: watch.elapsedMicroseconds,
        );
      },
      processingTime: (value) => value.processingMicroseconds,
    );
    _updateMathProgress(tasks.length);
    return _CompletedMathChunk(outcome.value.results, outcome.nodeId);
  }

  Future<_Recovered<T>> _recover<T>({
    required _WorkTarget target,
    required WorkloadKind kind,
    required int itemCount,
    required _WorkloadTraffic traffic,
    required int generation,
    required Future<T> Function(_SocketPeer) remote,
    required Future<T> Function() local,
    required int? Function(T) processingTime,
  }) async {
    final attempts = <InventoryAttempt>[];
    var candidate = target.connection;
    while (true) {
      _requireRun(generation);
      if (!target.isLocal &&
          (candidate == null ||
              !_canUseWorker(candidate) ||
              traffic.failedWorkers.contains(candidate.nodeId))) {
        candidate = _replacementWorker(kind, itemCount, traffic);
      }
      if (target.isLocal || candidate == null) {
        if (!target.isLocal) {
          _addEvent(
            'No eligible Worker remains; processing $itemCount pending items on Leader',
          );
        }
        final value = await traffic.enqueue(_nodeId!, local);
        _requireRun(generation);
        final nodeId = _nodeId!;
        attempts.add(
          InventoryAttempt(
            nodeId: nodeId,
            succeeded: true,
            processingMicroseconds: processingTime(value),
          ),
        );
        return _Recovered(value, nodeId, List.unmodifiable(attempts));
      }
      final connection = candidate;
      final nodeId = connection.nodeId!;
      try {
        // A busy replacement is queued, never mistaken for "no Worker".
        final value = await traffic.enqueue(nodeId, () async {
          _requireRun(generation);
          if (traffic.failedWorkers.contains(nodeId)) {
            throw const _ReassignPending();
          }
          try {
            _requireWorkerCompute(connection);
            return await remote(connection);
          } catch (_) {
            traffic.failedWorkers.add(nodeId);
            rethrow;
          }
        });
        _requireRun(generation);
        attempts.add(
          InventoryAttempt(
            nodeId: nodeId,
            succeeded: true,
            processingMicroseconds: processingTime(value),
          ),
        );
        return _Recovered(value, nodeId, List.unmodifiable(attempts));
      } on _ReassignPending {
        candidate = null;
      } catch (error) {
        _requireRun(generation);
        attempts.add(
          InventoryAttempt(
            nodeId: nodeId,
            succeeded: false,
            error: _short(error),
          ),
        );
        traffic.failedWorkers.add(nodeId);
        traffic.retries++;
        _replace(_snapshot.copyWith(retries: traffic.retries));
        _addEvent(
          '$nodeId failed; $itemCount unfinished items returned to pending',
        );
        candidate = _replacementWorker(kind, itemCount, traffic);
        if (candidate != null) {
          _addEvent('Reassigned $itemCount items to ${candidate.nodeId}');
        }
      }
    }
  }

  _SocketPeer? _replacementWorker(
    WorkloadKind kind,
    int itemCount,
    _WorkloadTraffic traffic,
  ) {
    final candidates = _workTargets(kind, itemCount)
        .where(
          (target) =>
              !target.isLocal &&
              !traffic.failedWorkers.contains(target.connection!.nodeId),
        )
        .toList();
    candidates.sort((a, b) {
      final loadA = traffic.pendingByNode[a.connection!.nodeId] ?? 0;
      final loadB = traffic.pendingByNode[b.connection!.nodeId] ?? 0;
      final byLoad = loadA.compareTo(loadB);
      return byLoad != 0 ? byLoad : b.weight.compareTo(a.weight);
    });
    return candidates.firstOrNull?.connection;
  }

  int? _processingTime(Map<String, dynamic> payload) {
    final value = payload['processingMicroseconds'];
    return value is int && value >= 0 && value <= 90000000 ? value : null;
  }

  List<InventoryExecution> _imageExecutions(
    List<InventoryImageDecodeResult> results,
    String nodeId,
    List<InventoryAttempt> attempts,
  ) => [
    for (final result in results)
      InventoryExecution(
        label: result.toLabelResult(),
        image: result,
        nodeId: nodeId,
        attempts: attempts,
      ),
  ];

  List<InventoryExecution> _labelExecutions(
    InventoryBatchResult result,
    String nodeId,
    List<InventoryAttempt> attempts,
  ) => [
    for (final label in result.labels)
      InventoryExecution(label: label, nodeId: nodeId, attempts: attempts),
  ];

  Map<String, int> _contributions(Iterable<InventoryExecution> executions) {
    final counts = <String, int>{};
    for (final item in executions) {
      counts.update(item.nodeId, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Future<_RemoteImageJobResult> _dispatchImages(
    _SocketPeer connection,
    List<InventoryImageTask> tasks,
    _WorkloadTraffic traffic,
  ) async {
    final wireTasks = await traffic.profiler.measure(
      RunPhase.imageRead,
      () async {
        final materialized = <InventoryImageTask>[];
        for (final task in tasks) {
          final path = task.localPath;
          final bytes =
              task.bytes ??
              (task.bytesBase64 != null
                  ? base64Decode(task.bytesBase64!)
                  : path == null
                  ? null
                  : await File(path).readAsBytes());
          if (bytes == null) {
            throw StateError('Image bytes unavailable for ${task.fileName}');
          }
          materialized.add(
            InventoryImageTask(
              imageId: task.imageId,
              fileName: task.fileName,
              bytes: bytes,
            ),
          );
        }
        return materialized;
      },
    );

    _requireWorkerCompute(connection);
    final jobId = 'IMAGE-JOB-$_generation-${++_nextJobId}';
    final completer = Completer<_RemoteImageJobResult>();
    _pendingImageJobs[jobId] = completer;
    _jobInputs[jobId] = tasks.map((task) => task.imageId).toList();
    _jobConnections[jobId] = connection;
    _jobTraffic[jobId] = traffic;
    _jobTimers[jobId] = Timer(const Duration(seconds: 90), () {
      final pending = _pendingImageJobs.remove(jobId);
      _jobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      _jobTimers.remove(jobId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(TimeoutException('No result for $jobId'));
      }
    });

    final encodeWatch = Stopwatch()..start();
    var sent = false;
    try {
      if (connection.supportsBinaryImages) {
        final frame = BinaryImageJob(jobId, wireTasks).encode();
        _requireWorkerCompute(connection);
        connection.socket.add(frame);
        traffic.sentBytes += frame.length;
        traffic.transports.add('binary-images-v1');
      } else {
        traffic.sentBytes += _send(connection, 'job', {
          'jobId': jobId,
          'images': wireTasks.map((task) => task.toJson()).toList(),
        });
        traffic.transports.add('json-base64');
      }
      sent = true;
    } catch (error) {
      _jobTimers.remove(jobId)?.cancel();
      _pendingImageJobs.remove(jobId);
      _jobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      completer.completeError(error);
    } finally {
      traffic.profiler.record(RunPhase.encodeAndQueue, encodeWatch.elapsed);
    }
    return sent
        ? traffic.profiler.measure(RunPhase.remoteWait, () => completer.future)
        : completer.future;
  }

  Future<_RemoteJobResult> _dispatch(
    _SocketPeer connection,
    List<String> labels,
    _WorkloadTraffic traffic,
  ) {
    _requireWorkerCompute(connection);
    final jobId = 'JOB-$_generation-${++_nextJobId}';
    final completer = Completer<_RemoteJobResult>();
    _pendingJobs[jobId] = completer;
    _jobInputs[jobId] = labels;
    _jobConnections[jobId] = connection;
    _jobTraffic[jobId] = traffic;
    _jobTimers[jobId] = Timer(const Duration(seconds: 12), () {
      final pending = _pendingJobs.remove(jobId);
      _jobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      _jobTimers.remove(jobId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(TimeoutException('No result for $jobId'));
      }
    });
    try {
      traffic.sentBytes += _send(connection, 'job', {
        'jobId': jobId,
        'labels': labels,
      });
      traffic.transports.add('json-labels');
    } catch (error) {
      _jobTimers.remove(jobId)?.cancel();
      _pendingJobs.remove(jobId);
      _jobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      completer.completeError(error);
    }
    return completer.future;
  }

  Future<_RemoteMathJobResult> _dispatchMath(
    _SocketPeer connection,
    MathProblem problem,
    List<MathTask> tasks,
    _WorkloadTraffic traffic,
  ) {
    _requireWorkerCompute(connection);
    final jobId = 'MATH-JOB-$_generation-${++_nextJobId}';
    final completer = Completer<_RemoteMathJobResult>();
    _pendingMathJobs[jobId] = completer;
    _mathJobInputs[jobId] = tasks.map((task) => task.taskId).toList();
    _jobConnections[jobId] = connection;
    _jobTraffic[jobId] = traffic;
    _jobTimers[jobId] = Timer(const Duration(seconds: 30), () {
      final pending = _pendingMathJobs.remove(jobId);
      _mathJobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      _jobTimers.remove(jobId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(TimeoutException('No result for $jobId'));
      }
    });
    try {
      traffic.sentBytes += _send(connection, 'job', {
        'jobId': jobId,
        'kind': 'math',
        'problem': problem.id,
        'tasks': tasks.map((task) => task.toJson()).toList(),
      });
      traffic.transports.add('json-mathematics');
    } catch (error) {
      _jobTimers.remove(jobId)?.cancel();
      _pendingMathJobs.remove(jobId);
      _mathJobInputs.remove(jobId);
      _jobConnections.remove(jobId);
      _jobTraffic.remove(jobId);
      completer.completeError(error);
    }
    return completer.future;
  }

  bool _canUseWorker(_SocketPeer connection) {
    final peer = _peers[connection.nodeId];
    return connection.authorized &&
        connection.socket.readyState == WebSocket.open &&
        _connections.contains(connection) &&
        peer != null &&
        peer.connected &&
        peer.nodeId != _nodeId &&
        !peer.telemetry.isLeader &&
        DateTime.now().difference(peer.lastSeen) <=
            const Duration(seconds: 24) &&
        peer.telemetry.computePauseReason == null;
  }

  void _requireWorkerCompute(_SocketPeer connection) {
    if (!_canUseWorker(connection)) {
      throw StateError(
        'Worker unavailable or paused by battery/thermal policy',
      );
    }
  }

  List<_WorkTarget> _workTargets(WorkloadKind kind, int itemCount) {
    final local = _localTelemetry!;
    final now = DateTime.now();
    final reference = _localPerformance.timing(kind);
    final seen = <String>{};
    final workers = _connections
        .where(
          (connection) =>
              _canUseWorker(connection) && seen.add(connection.nodeId!),
        )
        .toList();
    final batchSize = kind == WorkloadKind.images
        ? 4
        : (itemCount / (workers.length + 1)).ceil();
    return [
      _WorkTarget.local(
        schedulingWeight(
          telemetry: local,
          timing: reference,
          referenceTiming: reference,
          referenceCores: local.cpuCores,
          now: now,
        ),
      ),
      for (final connection in workers)
        _WorkTarget.remote(
          connection,
          schedulingWeight(
            telemetry: _peers[connection.nodeId]!.telemetry,
            timing: _peers[connection.nodeId]!.performance.timing(kind),
            referenceTiming: reference,
            referenceCores: local.cpuCores,
            now: now,
            roundTripMilliseconds: _peers[connection.nodeId]!.performance
                .freshRoundTrip(now),
            batchSize: batchSize,
          ),
        ),
    ];
  }

  void _recordLocalTask(WorkloadKind kind, Duration elapsed, int itemCount) {
    _localPerformance = _localPerformance.recordTask(
      kind,
      elapsed,
      itemCount,
      DateTime.now(),
    );
    _replace(_snapshot.copyWith(localPerformance: _localPerformance));
  }

  void _recordPeerTask(
    _SocketPeer connection,
    WorkloadKind kind,
    int itemCount,
    Object? microseconds,
  ) {
    final peer = _peers[connection.nodeId];
    if (peer == null) return;
    var performance = peer.performance;
    // Optional on the wire: old Workers remain usable with no fabricated time.
    if (microseconds is int && microseconds > 0 && microseconds <= 90000000) {
      performance = performance.recordTask(
        kind,
        Duration(microseconds: microseconds),
        itemCount,
        DateTime.now(),
      );
    }
    _peers[peer.nodeId] = peer.copyWith(
      performance: performance,
      completedLabels: peer.completedLabels + itemCount,
      lastSeen: DateTime.now(),
    );
    _publishPeers();
  }

  List<_WorkChunk<T>> _split<T>(List<T> items, List<_WorkTarget> targets) {
    final allocations = partitionByResourceWeight<T, _WorkTarget>(
      items: items,
      resources: [
        for (final target in targets)
          WorkResource(resource: target, weight: target.weight),
      ],
    );
    return [
      for (final allocation in allocations)
        _WorkChunk<T>(allocation.resource, allocation.items),
    ];
  }

  MeshRunResult _imageRunResult({
    required String mode,
    required List<InventoryImageDecodeResult> imageResults,
    required Set<String> expectedIds,
    required Duration elapsed,
    required Map<String, int> contributions,
    required int retries,
    required int sentBytes,
    required int receivedBytes,
    required List<InventoryExecution> executions,
    Set<String> transports = const {},
    Stopwatch? watch,
    RunProfiler? profiler,
  }) {
    final aggregationWatch = Stopwatch()..start();
    final batch = _imageBatch(imageResults);
    final labels = [
      for (final result in imageResults) result.toLabelResult().rawLabel,
    ];
    final report = InventoryReport.aggregate(
      originalLabels: labels,
      workerBatches: [batch],
      expectedIds: expectedIds,
    );
    profiler?.record(RunPhase.aggregation, aggregationWatch.elapsed);
    watch?.stop();
    return MeshRunResult(
      mode: mode,
      labels: labels,
      expectedIds: expectedIds,
      results: batch.labels,
      report: report,
      elapsed: watch?.elapsed ?? elapsed,
      contributions: contributions,
      retries: retries,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
      executions: List.unmodifiable(executions),
      transports: Set.unmodifiable(transports),
      diagnostics: profiler?.snapshot() ?? const RunDiagnostics(),
    );
  }

  InventoryBatchResult _imageBatch(
    List<InventoryImageDecodeResult> imageResults,
  ) {
    return InventoryBatchResult(
      labels: [for (final result in imageResults) result.toLabelResult()],
      elapsedMilliseconds: imageResults.fold(
        0,
        (sum, result) => sum + result.elapsedMilliseconds,
      ),
    );
  }

  MeshRunResult _runResult({
    required String mode,
    required List<String> labels,
    required Set<String> expectedIds,
    required List<InventoryBatchResult> batches,
    required Duration elapsed,
    required Map<String, int> contributions,
    required int retries,
    required int sentBytes,
    required int receivedBytes,
    required List<InventoryExecution> executions,
    Set<String> transports = const {},
    Stopwatch? watch,
  }) {
    final report = InventoryReport.aggregate(
      originalLabels: labels,
      workerBatches: batches,
      expectedIds: expectedIds,
    );
    watch?.stop();
    return MeshRunResult(
      mode: mode,
      labels: labels,
      expectedIds: expectedIds,
      results: [for (final batch in batches) ...batch.labels],
      report: report,
      elapsed: watch?.elapsed ?? elapsed,
      contributions: contributions,
      retries: retries,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
      executions: List.unmodifiable(executions),
      transports: Set.unmodifiable(transports),
    );
  }

  MathRunResult _mathRunResult({
    required String mode,
    required MathProblem problem,
    required List<MathTask> tasks,
    required List<MathTaskResult> results,
    required Duration elapsed,
    required Map<String, int> contributions,
    required int retries,
    required int sentBytes,
    required int receivedBytes,
  }) => MathRunResult(
    mode: mode,
    problem: problem,
    tasks: List.unmodifiable(tasks),
    results: List.unmodifiable(results),
    summary: MathWorkloadEngine.aggregate(problem, results),
    elapsed: elapsed,
    contributions: Map.unmodifiable(contributions),
    retries: retries,
    sentBytes: sentBytes,
    receivedBytes: receivedBytes,
  );

  void _updateProgress(int completed) {
    _replace(
      _snapshot.copyWith(
        phase: 'PROCESSING',
        completedLabels: _snapshot.completedLabels + completed,
        message:
            '${_snapshot.completedLabels + completed} of ${_snapshot.totalLabels} labels complete',
      ),
    );
  }

  void _updateMathProgress(int completed) {
    _replace(
      _snapshot.copyWith(
        phase: 'SOLVING',
        completedLabels: _snapshot.completedLabels + completed,
        message:
            '${_snapshot.completedLabels + completed} of ${_snapshot.totalLabels} mathematical tasks complete',
      ),
    );
  }

  int _send(_SocketPeer connection, String type, Map<String, dynamic> payload) {
    if (connection.socket.readyState != WebSocket.open) {
      if (type == 'job') throw StateError('Worker socket is not open');
      return 0;
    }
    final message = jsonEncode({
      'version': 1,
      'type': type,
      'payload': payload,
    });
    connection.socket.add(message);
    return utf8.encode(message).length;
  }

  Future<void> _refreshLocalTelemetry() async {
    if (_nodeId == null) return;
    final existing = _telemetryRefresh;
    if (existing != null) return existing;
    final pending = _collectLocalTelemetry(_generation, _nodeId!);
    _telemetryRefresh = pending;
    try {
      await pending;
    } finally {
      if (identical(_telemetryRefresh, pending)) _telemetryRefresh = null;
    }
  }

  Future<void> _collectLocalTelemetry(int generation, String nodeId) async {
    final telemetry = await _telemetryService
        .collectTelemetry(nodeId: nodeId, isLeader: _role == MeshRole.leader)
        .timeout(const Duration(seconds: 3));
    if (generation != _generation || nodeId != _nodeId) return;
    _localTelemetry = telemetry;
    _replace(_snapshot.copyWith(localTelemetry: telemetry));
  }

  Future<void> _sendHeartbeats() async {
    try {
      await _refreshLocalTelemetry();
    } catch (error) {
      if (_snapshot.active) {
        _addEvent('Telemetry refresh failed: ${_short(error)}');
      }
    }
    if (!_snapshot.active) return;
    for (final connection in _connections.toList(growable: false)) {
      _sendProbe(connection);
    }
    _publishPeers();
  }

  void _sendProbe(_SocketPeer connection) {
    if (!connection.authorized ||
        connection.socket.readyState != WebSocket.open) {
      return;
    }
    if (connection.probeWatch != null &&
        connection.probeWatch!.elapsed < const Duration(seconds: 8)) {
      return;
    }
    connection.probeId = 'PROBE-${++_nextProbeId}';
    connection.probeWatch = Stopwatch()..start();
    _send(connection, 'heartbeat', {
      'probeId': connection.probeId,
      'telemetry': _localTelemetry?.toJson(),
    });
  }

  void _receiveHeartbeatAck(
    _SocketPeer connection,
    Map<String, dynamic> payload,
  ) {
    final watch = connection.probeWatch;
    final peer = _peers[connection.nodeId];
    if (watch != null &&
        payload['probeId'] == connection.probeId &&
        peer != null) {
      watch.stop();
      _peers[peer.nodeId] = peer.copyWith(
        performance: peer.performance.recordRoundTrip(
          watch.elapsed,
          DateTime.now(),
        ),
      );
      connection.probeWatch = null;
      connection.probeId = null;
    }
    _touch(connection, payload: payload);
  }

  void _touch(_SocketPeer connection, {Map<String, dynamic>? payload}) {
    final nodeId = connection.nodeId;
    final peer = nodeId == null ? null : _peers[nodeId];
    if (peer == null) return;
    var telemetry = peer.telemetry;
    final raw = payload?['telemetry'];
    if (raw is Map) {
      final update = NodeTelemetry.fromJson(Map<String, dynamic>.from(raw));
      if (update.nodeId == peer.nodeId &&
          update.isLeader == peer.telemetry.isLeader) {
        telemetry = update;
      }
    }
    _peers[nodeId!] = peer.copyWith(
      telemetry: telemetry,
      connected: true,
      lastSeen: DateTime.now(),
    );
    _publishPeers();
  }

  void _remove(_SocketPeer connection) {
    if (!_connections.remove(connection)) return;
    final nodeId = connection.nodeId;
    if (nodeId != null && !_connections.any((item) => item.nodeId == nodeId)) {
      final peer = _peers[nodeId];
      if (peer != null) {
        _peers[nodeId] = peer.copyWith(
          connected: false,
          lastSeen: DateTime.now(),
        );
      }
    }
    final pendingRequestIds = _pendingConnections.entries
        .where((entry) => entry.value.connection == connection)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in pendingRequestIds) {
      _pendingConnections.remove(requestId);
    }
    if (pendingRequestIds.isNotEmpty) {
      _publishPendingConnections();
    }

    for (final entry in _jobConnections.entries.toList(growable: false)) {
      if (entry.value != connection) continue;
      final pending = _pendingJobs.remove(entry.key);
      final pendingImages = _pendingImageJobs.remove(entry.key);
      final pendingMath = _pendingMathJobs.remove(entry.key);
      _jobInputs.remove(entry.key);
      _mathJobInputs.remove(entry.key);
      _jobConnections.remove(entry.key);
      _jobTraffic.remove(entry.key);
      _jobTimers.remove(entry.key)?.cancel();
      pending?.completeError(StateError('Worker disconnected'));
      pendingImages?.completeError(StateError('Worker disconnected'));
      pendingMath?.completeError(StateError('Worker disconnected'));
    }
    _publishPeers();
    _addEvent(
      'Worker ${nodeId ?? connection.host} disconnected; unfinished work can retry',
    );
  }

  void _publishPeers() {
    final peers = _peers.values.toList(growable: false)
      ..sort((a, b) => a.nodeId.compareTo(b.nodeId));
    _replace(_snapshot.copyWith(peers: peers));
  }

  void _publishPendingConnections() {
    final requests = _pendingConnections.values
        .map((pending) => pending.request)
        .toList(growable: false);
    _replace(_snapshot.copyWith(pendingRequests: requests));
  }

  void _addEvent(String event) {
    final events = [event, ..._snapshot.events];
    if (events.length > 8) events.removeRange(8, events.length);
    _replace(_snapshot.copyWith(events: events, message: event));
  }

  void _replace(MeshRuntimeSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }

  Future<void> _cleanup() async {
    _generation++;
    _activeWorkerJobs = 0;
    _localPerformance = const NodePerformance();
    _telemetryRefresh = null;
    _heartbeatTimer?.cancel();
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    for (final timer in _jobTimers.values) {
      timer.cancel();
    }
    for (final pending in _pendingJobs.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Mesh stopped'));
      }
    }
    for (final pending in _pendingImageJobs.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Mesh stopped'));
      }
    }
    for (final pending in _pendingMathJobs.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Mesh stopped'));
      }
    }
    _jobTimers.clear();
    _pendingJobs.clear();
    _pendingImageJobs.clear();
    _pendingMathJobs.clear();
    _jobInputs.clear();
    _mathJobInputs.clear();
    _jobConnections.clear();
    _jobTraffic.clear();
    _pendingConnections.clear();
    for (final connection in _connections.toList(growable: false)) {
      await connection.socket.close(WebSocketStatus.goingAway, 'Mesh stopped');
    }
    _connections.clear();
    await _server?.close(force: true);
    _server = null;
    await _discoveryService.stop();
    _peers.clear();
    _localTelemetry = null;
    _nodeId = null;
    _localServiceName = null;
  }

  bool _isConnected(String host, int port) => _connections.any(
    (connection) => connection.host == host && connection.port == port,
  );

  Future<List<String>> _localIpv4Addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return [
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  String _uri(String host, int port) =>
      'ws://${host.contains(':') ? '[$host]' : host}:$port';

  String _short(Object error) => error.toString().split('\n').first;

  String _summary(MeshRunResult result) {
    final counts = _countResults(result.results);
    return '${counts['valid']} valid · ${counts['duplicate']} duplicate · '
        '${counts['invalid']} invalid · ${counts['unreadable']} unreadable';
  }

  String _mathSummary(MathRunResult result) {
    final value = switch (result.problem) {
      MathProblem.monteCarloPi =>
        'π ≈ ${(result.summary['pi'] as num).toDouble().toStringAsFixed(6)}',
      MathProblem.linearRegression =>
        'slope ${(result.summary['slope'] as num).toDouble().toStringAsFixed(4)}',
      MathProblem.primeFactorization =>
        '${result.summary['factored']} numbers factored',
    };
    return '${result.problem.title}: $value';
  }

  Map<String, int> _countResults(List<InventoryLabelResult> results) {
    final seen = <String>{};
    var valid = 0, duplicate = 0, invalid = 0, unreadable = 0;
    for (final result in results) {
      switch (result.status) {
        case InventoryLabelStatus.valid:
          if (result.normalizedId != null && !seen.add(result.normalizedId!)) {
            duplicate++;
          } else {
            valid++;
          }
        case InventoryLabelStatus.invalid:
          invalid++;
        case InventoryLabelStatus.unreadable:
          unreadable++;
      }
    }
    return {
      'valid': valid,
      'duplicate': duplicate,
      'invalid': invalid,
      'unreadable': unreadable,
    };
  }

  List<String> _demoLabels() => [
    for (var i = 1; i <= 848; i++) 'PKG-${i.toString().padLeft(6, '0')}',
    for (var i = 1; i <= 45; i++) 'PKG-${i.toString().padLeft(6, '0')}',
    'PKG-999901',
    'PKG-999902',
    'BROKEN-LABEL',
    'PKG-ABC123',
    '',
    '   ',
    '\t\n',
  ];
}

/// Per-run application-message bytes, retained even when a chunk retries locally.
class _WorkloadTraffic {
  final profiler = RunProfiler();
  int sentBytes = 0;
  int receivedBytes = 0;
  int retries = 0;
  final transports = <String>{};
  final failedWorkers = <String>{};
  final pendingByNode = <String, int>{};
  final _queues = <String, Future<void>>{};

  Future<T> enqueue<T>(String nodeId, Future<T> Function() work) async {
    pendingByNode.update(nodeId, (count) => count + 1, ifAbsent: () => 1);
    final previous = _queues[nodeId] ?? Future<void>.value();
    final queueWatch = Stopwatch()..start();
    final next = previous.then((_) {
      profiler.record(RunPhase.queueWait, queueWatch.elapsed);
      return work();
    });
    final settled = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _queues[nodeId] = settled;
    try {
      return await next;
    } finally {
      pendingByNode[nodeId] = pendingByNode[nodeId]! - 1;
      if (identical(_queues[nodeId], settled)) _queues.remove(nodeId);
    }
  }
}

class _ReassignPending implements Exception {
  const _ReassignPending();
}

class _Recovered<T> {
  const _Recovered(this.value, this.nodeId, this.attempts);
  final T value;
  final String nodeId;
  final List<InventoryAttempt> attempts;
}

class _SocketPeer {
  _SocketPeer({required this.socket, required this.host, required this.port});
  final WebSocket socket;
  final String host;
  final int port;
  String? nodeId;
  String? requestId;
  bool authorized = false;
  bool supportsBinaryImages = false;
  String? probeId;
  Stopwatch? probeWatch;
}

class _PendingConnection {
  const _PendingConnection({required this.request, required this.connection});
  final MeshConnectionRequest request;
  final _SocketPeer connection;
}

class _WorkTarget {
  const _WorkTarget.local(this.weight) : connection = null, isLocal = true;
  const _WorkTarget.remote(this.connection, this.weight) : isLocal = false;
  final _SocketPeer? connection;
  final double weight;
  final bool isLocal;
}

class _WorkChunk<T> {
  const _WorkChunk(this.target, this.items);
  final _WorkTarget target;
  final List<T> items;
}

class _RemoteJobResult {
  const _RemoteJobResult(this.result, {required this.processingMicroseconds});
  final InventoryBatchResult result;
  final int? processingMicroseconds;
}

class _RemoteImageJobResult {
  const _RemoteImageJobResult(
    this.results, {
    required this.processingMicroseconds,
  });
  final List<InventoryImageDecodeResult> results;
  final int? processingMicroseconds;
}

class _RemoteMathJobResult {
  const _RemoteMathJobResult(
    this.results, {
    required this.processingMicroseconds,
  });
  final List<MathTaskResult> results;
  final int? processingMicroseconds;
}

class _CompletedImageChunk {
  const _CompletedImageChunk(this.executions);
  final List<InventoryExecution> executions;
  List<InventoryImageDecodeResult> get results => [
    for (final item in executions) item.image!,
  ];
}

class _CompletedChunk {
  const _CompletedChunk(this.result, this.executions);
  final InventoryBatchResult result;
  final List<InventoryExecution> executions;
}

class _CompletedMathChunk {
  const _CompletedMathChunk(this.results, this.nodeId);
  final List<MathTaskResult> results;
  final String nodeId;
}
