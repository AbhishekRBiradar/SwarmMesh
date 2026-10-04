import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/inventory_image_models.dart';
import 'package:swarm_mesh/models/binary_image_job.dart';
import 'package:swarm_mesh/models/inventory_models.dart';
import 'package:swarm_mesh/models/math_workload.dart';
import 'package:swarm_mesh/models/node_telemetry.dart';
import 'package:swarm_mesh/models/run_diagnostics.dart';
import 'package:swarm_mesh/services/device_telemetry_service.dart';
import 'package:swarm_mesh/services/inventory_image_service.dart';
import 'package:swarm_mesh/services/mesh_discovery_service.dart';
import 'package:swarm_mesh/services/mesh_runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MeshRuntimeService runtime;
  late Directory images;
  late List<String> paths;
  late _TestTelemetry telemetry;

  setUp(() async {
    images = await Directory.systemTemp.createTemp('swarmmesh-traffic-test-');
    paths = [];
    // The fake decoder keeps this test independent of native ML Kit. The real
    // runtime still reads and transfers each file's bytes over a real socket.
    for (var index = 1; index <= 18; index++) {
      final file = File('${images.path}/标签_$index.png');
      await file.writeAsBytes([index, 0, 255, 1, 2, 3]);
      paths.add(file.path);
    }
    telemetry = _TestTelemetry();
    runtime = MeshRuntimeService(
      telemetryService: telemetry,
      discoveryService: _TestDiscovery(),
      imageService: _TestImageService(),
    );
    await runtime.start(role: MeshRole.leader);
    expect(runtime.snapshot.active, isTrue);
  });

  tearDown(() async {
    await runtime.dispose();
    await images.delete(recursive: true);
  });

  Future<_TestWorker> connectWorker({
    int? disconnectOnJob,
    bool malformedReply = false,
    bool measured = false,
    String nodeId = 'TEST-WORKER',
    Duration replyDelay = Duration.zero,
    bool stallFirstJob = false,
    bool binary = false,
  }) async {
    final worker = await _TestWorker.start(
      disconnectOnJob: disconnectOnJob,
      malformedReply: malformedReply,
      measured: measured,
      nodeId: nodeId,
      replyDelay: replyDelay,
      stallFirstJob: stallFirstJob,
      binary: binary,
    );
    addTearDown(worker.dispose);
    final targetCount = runtime.snapshot.connectedPeers + 1;
    final connected = runtime.snapshots.firstWhere(
      (snapshot) => snapshot.connectedPeers == targetCount,
    );
    await runtime.connectManually('127.0.0.1', port: worker.server.port);
    await connected.timeout(const Duration(seconds: 5));
    return worker;
  }

  void expectTraffic(_TestWorker worker) {
    final result = runtime.snapshot.swarmResult!;
    expect(result.sentBytes, _bytes(worker.jobs));
    expect(result.receivedBytes, _bytes(worker.replies));
    expect(result.totalBytes, _bytes([...worker.jobs, ...worker.replies]));
    expect(runtime.snapshot.singleResult!.totalBytes, 0);
    expect(result.hasSameCorrectnessAs(runtime.snapshot.singleResult!), isTrue);
  }

  test('local-only text and image runs have zero job traffic', () async {
    await runtime.runDemoWorkload();
    expect(runtime.snapshot.singleResult!.totalBytes, 0);
    expect(runtime.snapshot.swarmResult!.totalBytes, 0);

    await runtime.runImageWorkload(paths);
    expect(runtime.snapshot.singleResult!.totalBytes, 0);
    expect(runtime.snapshot.swarmResult!.totalBytes, 0);
  });

  test(
    'image diagnostics count actual batches and survive failed remote attempts',
    () async {
      await connectWorker(binary: true, disconnectOnJob: 2);
      await runtime.runImageWorkload(paths);
      final result = runtime.snapshot.swarmResult!;
      final phases = result.diagnostics.phases;
      expect(result.retries, 1);
      expect(phases[RunPhase.remoteWait]!.samples, 2);
      expect(phases[RunPhase.encodeAndQueue]!.samples, 2);
      expect(phases[RunPhase.imageRead]!.samples, 2);
      expect(phases[RunPhase.localProcessing]!.samples, greaterThan(0));
      expect(
        phases[RunPhase.telemetry]!.samples,
        phases[RunPhase.localProcessing]!.samples,
      );
      expect(phases[RunPhase.aggregation]!.samples, 1);
      expect(
        runtime
            .snapshot
            .singleResult!
            .diagnostics
            .phases[RunPhase.localProcessing]!
            .samples,
        1,
      );
      expect(
        result.hasSameCorrectnessAs(runtime.snapshot.singleResult!),
        isTrue,
      );
      // Timings are attached to attempts/batches, not repeated for every image.
      expect(
        phases[RunPhase.remoteWait]!.samples,
        lessThan(result.results.length),
      );
      await runtime.runImageWorkload(paths.take(1).toList());
      expect(
        runtime.snapshot.swarmResult!.diagnostics.phases[RunPhase.remoteWait],
        isNull,
      );
    },
  );

  test('text traffic uses UTF-8, excludes noise and resets per run', () async {
    final worker = await connectWorker();
    for (var run = 0; run < 2; run++) {
      worker.jobs.clear();
      worker.replies.clear();
      await runtime.runDemoWorkload();
      expectTraffic(worker);
      expect(worker.jobs, hasLength(1));
      expect(
        runtime.snapshot.swarmResult!.receivedBytes,
        greaterThan(worker.replies.single.length),
      );
    }
  });

  test(
    'mathematical tasks execute on a Worker and match the Leader baseline',
    () async {
      final worker = await connectWorker(measured: true);
      await runtime.runMathWorkload(MathProblem.linearRegression);
      final result = runtime.snapshot.swarmMathResult!;
      final baseline = runtime.snapshot.singleMathResult!;

      expect(result.mode, 'math-swarm');
      expect(result.hasSameCorrectnessAs(baseline), isTrue);
      expect(result.summary['count'], 18000);
      expect(result.contributions['TEST-WORKER'], greaterThan(0));
      expect(result.sentBytes, greaterThan(0));
      expect(result.receivedBytes, greaterThan(0));
      expect(jsonDecode(worker.jobs.single)['payload']['kind'], 'math');
      expect(
        runtime.snapshot.peers.single.performance.mathematics.sampleCount,
        1,
      );
    },
  );

  test(
    'image traffic includes every batch, base64 and Unicode names',
    () async {
      final worker = await connectWorker();
      await runtime.runImageWorkload(paths);
      expectTraffic(worker);
      expect(
        worker.jobs.map((message) {
          final job = jsonDecode(message) as Map;
          return (job['payload']['images'] as List).length;
        }),
        [4, 4, 1],
      );
      expect(
        runtime.snapshot.swarmResult!.sentBytes,
        greaterThan(worker.jobs.fold<int>(0, (sum, job) => sum + job.length)),
      );
    },
  );

  test('text disconnect retains sent bytes during local recovery', () async {
    final worker = await connectWorker(disconnectOnJob: 1);
    await runtime.runDemoWorkload();
    expectTraffic(worker);
    expect(runtime.snapshot.swarmResult!.sentBytes, greaterThan(0));
    expect(runtime.snapshot.swarmResult!.receivedBytes, 0);
    expect(runtime.snapshot.swarmResult!.retries, 1);
  });

  test(
    'image disconnect retains earlier batches and the failed send',
    () async {
      final worker = await connectWorker(disconnectOnJob: 2);
      await runtime.runImageWorkload(paths);
      expectTraffic(worker);
      expect(worker.jobs, hasLength(2));
      expect(worker.replies, hasLength(1));
      expect(runtime.snapshot.swarmResult!.retries, 1);
    },
  );

  test('malformed replies retain traffic and trigger local recovery', () async {
    final worker = await connectWorker(malformedReply: true);
    await runtime.runDemoWorkload().timeout(const Duration(seconds: 5));
    expectTraffic(worker);
    expect(runtime.snapshot.swarmResult!.receivedBytes, greaterThan(0));
    expect(runtime.snapshot.swarmResult!.retries, 1);
  });

  test('legacy Workers leave unmeasured timing and RTT empty', () async {
    await connectWorker();
    await runtime.runDemoWorkload();
    final performance = runtime.snapshot.peers.single.performance;
    expect(performance.roundTripMilliseconds, isNull);
    expect(performance.images.sampleCount, 0);
    expect(performance.labels.sampleCount, 0);
  });

  test(
    'binary-capable Worker receives raw frames with exact byte accounting',
    () async {
      final worker = await connectWorker(binary: true);
      await runtime.runImageWorkload(paths);
      final result = runtime.snapshot.swarmResult!;
      expect(
        result.hasSameCorrectnessAs(runtime.snapshot.singleResult!),
        isTrue,
      );
      expect(worker.binaryJobs, hasLength(3));
      expect(worker.jobs, isEmpty);
      expect(
        result.sentBytes,
        worker.binaryJobs.fold<int>(0, (sum, frame) => sum + frame.length),
      );
      expect(result.receivedBytes, _bytes(worker.replies));
      expect(result.transports, {'binary-images-v1'});
      final first = BinaryImageJob.decode(worker.binaryJobs.first).images.first;
      expect(first.bytes!.length, 6);
    },
  );

  test('failed image batches move to a busy Worker and successful batches stay committed', () async {
    final a = await connectWorker(
      nodeId: 'A',
      disconnectOnJob: 2,
      binary: true,
    );
    final b = await connectWorker(
      nodeId: 'B',
      replyDelay: const Duration(milliseconds: 40),
    );
    await runtime.runImageWorkload(paths);
    final result = runtime.snapshot.swarmResult!;
    expect(result.hasSameCorrectnessAs(runtime.snapshot.singleResult!), isTrue);
    expect(result.contributions, {'TEST-LEADER': 6, 'A': 4, 'B': 8});
    expect(result.retries, 1);
    expect(result.executions, hasLength(18));
    expect(
      result.executions.map((item) => item.image!.imageId).toSet(),
      hasLength(18),
    );
    expect(result.executions.where((item) => item.retryCount == 1).length, 2);
    expect(
      result.executions
          .where((item) => item.retryCount == 1)
          .every((item) => item.nodeId == 'B'),
      isTrue,
    );
    expect(b.maxInFlight, 1);
    expect(
      result.sentBytes,
      _bytes([...a.jobs, ...b.jobs]) +
          a.binaryJobs.fold<int>(0, (sum, frame) => sum + frame.length),
    );
    expect(result.transports, {'binary-images-v1', 'json-base64'});
    expect(result.receivedBytes, _bytes([...a.replies, ...b.replies]));
    expect(runtime.snapshot.completedLabels, 18);
  });

  test(
    'all Workers failing falls back to Leader and attributes work correctly',
    () async {
      await connectWorker(nodeId: 'A', malformedReply: true);
      await connectWorker(nodeId: 'B', malformedReply: true);
      await runtime.runDemoWorkload();
      final result = runtime.snapshot.swarmResult!;
      expect(
        result.hasSameCorrectnessAs(runtime.snapshot.singleResult!),
        isTrue,
      );
      expect(result.contributions, {'TEST-LEADER': 900});
      expect(result.retries, 2);
      expect(
        result.executions.every((item) => item.nodeId == 'TEST-LEADER'),
        isTrue,
      );
    },
  );

  test('timed-out Worker work is reassigned to another Worker', () async {
    await connectWorker(nodeId: 'A', stallFirstJob: true);
    final b = await connectWorker(nodeId: 'B');
    await runtime.runDemoWorkload().timeout(const Duration(seconds: 20));
    final result = runtime.snapshot.swarmResult!;
    expect(result.hasSameCorrectnessAs(runtime.snapshot.singleResult!), isTrue);
    expect(result.contributions, {'TEST-LEADER': 300, 'B': 600});
    expect(b.jobs, hasLength(2));
    expect(result.retries, 1);
  });

  test(
    'one image assigned only to Leader is not reported as a swarm run',
    () async {
      final worker = await connectWorker();
      await runtime.runImageWorkload([paths.first]);
      expect(worker.jobs, isEmpty);
      expect(runtime.snapshot.swarmResult!.isSwarm, isFalse);
      expect(runtime.snapshot.swarmResult!.totalBytes, 0);
    },
  );

  test(
    'correlated probes and successful jobs populate separate timings',
    () async {
      await connectWorker(measured: true);
      if (runtime.snapshot.peers.single.performance.roundTripMilliseconds ==
          null) {
        await runtime.snapshots
            .firstWhere(
              (snapshot) =>
                  snapshot.peers.single.performance.roundTripMilliseconds !=
                  null,
            )
            .timeout(const Duration(seconds: 5));
      }
      expect(
        runtime.snapshot.peers.single.performance.roundTripMilliseconds,
        greaterThan(0),
      );
      await runtime.runImageWorkload(paths);
      final imageTiming = runtime.snapshot.peers.single.performance.images;
      expect(imageTiming.sampleCount, greaterThan(0));
      expect(imageTiming.lastMilliseconds, 20);
      expect(runtime.snapshot.peers.single.performance.labels.sampleCount, 0);
      await runtime.runDemoWorkload();
      expect(runtime.snapshot.peers.single.performance.labels.sampleCount, 1);
      expect(
        runtime.snapshot.peers.single.performance.images.sampleCount,
        imageTiming.sampleCount,
      );
    },
  );

  test('thermal updates exclude a Worker from new allocations', () async {
    final worker = await connectWorker();
    final updated = runtime.snapshots.firstWhere(
      (snapshot) =>
          snapshot.peers.single.telemetry.thermalState == ThermalState.severe,
    );
    worker.sendThermalUpdate(ThermalState.severe);
    await updated.timeout(const Duration(seconds: 5));
    await runtime.runImageWorkload(paths);
    expect(worker.jobs, isEmpty);
    expect(runtime.snapshot.swarmResult!.isSwarm, isFalse);
    expect(runtime.snapshot.swarmResult!.totalBytes, 0);
  });

  test('refresh before baseline pauses a low-battery Leader and clears old reports', () async {
    await runtime.runDemoWorkload();
    expect(runtime.snapshot.result, isNotNull);
    telemetry.batteryLevel = 10;
    await runtime.runImageWorkload(paths);
    expect(runtime.snapshot.running, isFalse);
    expect(runtime.snapshot.phase, 'WORKLOAD STOPPED');
    expect(runtime.snapshot.message, contains('Battery'));
    expect(runtime.snapshot.result, isNull);
    expect(runtime.snapshot.singleResult, isNull);
    expect(runtime.snapshot.localPerformance.images.sampleCount, 0);
  });

  test('malformed measured results do not train the scheduler', () async {
    await connectWorker(measured: true, malformedReply: true);
    await runtime.runDemoWorkload();
    expect(runtime.snapshot.peers.single.performance.labels.sampleCount, 0);
    expect(runtime.snapshot.swarmResult!.retries, 1);
  });

  test('active mesh refreshes battery telemetry automatically', () async {
    telemetry.batteryLevel = 17;
    final updated = await runtime.snapshots
        .firstWhere((snapshot) => snapshot.localTelemetry?.batteryLevel == 17)
        .timeout(const Duration(seconds: 12));
    expect(updated.active, isTrue);
  });

  test('Worker measures processing and rejects work when refreshed thermal state pauses it', () async {
    await runtime.stop();
    await runtime.start(role: MeshRole.worker);
    final socket = await WebSocket.connect('ws://127.0.0.1:4040');
    final messages = StreamController<Map<String, dynamic>>.broadcast();
    final subscription = socket.listen(
      (data) => messages.add(
        Map<String, dynamic>.from(jsonDecode(data as String) as Map),
      ),
    );
    addTearDown(() async {
      await socket.close();
      await subscription.cancel();
      await messages.close();
    });
    void send(String type, Map<String, dynamic> payload) => socket.add(
      jsonEncode({'version': 1, 'type': type, 'payload': payload}),
    );
    final requested = runtime.snapshots.firstWhere(
      (snapshot) => snapshot.pendingRequests.isNotEmpty,
    );
    send('connection_request', {
      'requestId': 'test-leader-request',
      'telemetry': _telemetry('TEST-CLIENT', isLeader: true).toJson(),
    });
    final request = await requested.timeout(const Duration(seconds: 5));
    await runtime.approveConnection(request.pendingRequests.single.requestId);

    final decoded = messages.stream.firstWhere(
      (message) => message['type'] == 'job_result',
    );
    send('job', {
      'jobId': 'decode-1',
      'images': [
        InventoryImageTask(
          imageId: '1',
          fileName: 'label_1.png',
          bytesBase64: base64Encode([1, 2, 3]),
        ).toJson(),
      ],
    });
    final result =
        (await decoded.timeout(const Duration(seconds: 5)))['payload'] as Map;
    expect(result['processingMicroseconds'], greaterThan(0));
    expect((result['results'] as List).single['decodedValue'], 'PKG-000001');
    expect(runtime.snapshot.localPerformance.images.sampleCount, 1);
    expect(runtime.snapshot.phase, 'WORKER READY');
    expect(runtime.snapshot.completedLabels, 1);
    expect(runtime.snapshot.running, isFalse);

    final binaryDecoded = messages.stream.firstWhere(
      (message) => message['type'] == 'job_result',
    );
    socket.add(
      BinaryImageJob('binary-2', [
        InventoryImageTask(
          imageId: '2',
          fileName: 'label_2.png',
          bytes: Uint8List.fromList([4, 5, 6]),
        ),
      ]).encode(),
    );
    final binaryResult =
        (await binaryDecoded.timeout(const Duration(seconds: 5)))['payload']
            as Map;
    expect(binaryResult['kind'], 'images');
    expect(
      (binaryResult['results'] as List).single['decodedValue'],
      'PKG-000002',
    );

    final failedDecode = messages.stream.firstWhere(
      (message) => message['type'] == 'job_result',
    );
    send('job', {
      'jobId': 'decoder-failure',
      'images': [
        InventoryImageTask(
          imageId: 'bad',
          fileName: 'no-digits.png',
          bytesBase64: base64Encode([1]),
        ).toJson(),
      ],
    });
    final failedReply =
        (await failedDecode.timeout(const Duration(seconds: 5)))['payload']
            as Map;
    expect(failedReply['error'], isNotNull);
    expect(runtime.snapshot.running, isFalse);
    expect(runtime.snapshot.phase, 'WORKER READY');

    telemetry.thermalState = ThermalState.severe;
    final rejected = messages.stream.firstWhere(
      (message) => message['type'] == 'job_result',
    );
    send('job', {
      'jobId': 'paused-2',
      'labels': ['PKG-000002'],
    });
    final error =
        (await rejected.timeout(const Duration(seconds: 5)))['payload'] as Map;
    expect(error['error'], contains('Thermal'));
    expect(error['telemetry']['thermalState'], 'severe');
    expect(runtime.snapshot.localPerformance.labels.sampleCount, 0);
  });
}

int _bytes(Iterable<String> messages) =>
    messages.fold(0, (sum, message) => sum + utf8.encode(message).length);

NodeTelemetry _telemetry(String nodeId, {bool isLeader = false}) =>
    NodeTelemetry(
      nodeId: nodeId,
      deviceModel: 'Test device',
      batteryLevel: 100,
      cpuCores: 1,
      computeWeight: 1,
      isLeader: isLeader,
      status: 'READY',
      timestamp: DateTime(2026),
    );

class _TestTelemetry extends DeviceTelemetryService {
  int batteryLevel = 100;
  ThermalState thermalState = ThermalState.unknown;
  @override
  Future<String> createNodeId() async => 'TEST-LEADER';

  @override
  Future<NodeTelemetry> collectTelemetry({
    required String nodeId,
    bool isLeader = false,
  }) async => _telemetry(
    nodeId,
    isLeader: isLeader,
  ).copyWith(batteryLevel: batteryLevel, thermalState: thermalState);
}

class _TestDiscovery extends MeshDiscoveryService {
  @override
  Future<void> startDiscovery() async {}

  @override
  Future<String> registerNode({
    required String nodeId,
    required int port,
  }) async => 'TEST-SERVICE';
}

InventoryImageDecodeResult _decodeImage(InventoryImageTask task) {
  final id = RegExp(r'\d+').firstMatch(task.fileName)!.group(0)!;
  return InventoryImageDecodeResult(
    imageId: task.imageId,
    fileName: task.fileName,
    decodedValue: 'PKG-${id.padLeft(6, '0')}',
    status: 'decoded',
    reason: 'Decoded ✓ 标签',
    elapsedMilliseconds: 1,
  );
}

class _TestImageService extends InventoryImageService {
  @override
  Future<InventoryImageDecodeResult> decodeTask(
    InventoryImageTask task,
  ) async => _decodeImage(task);

  @override
  Future<void> dispose() async {}
}

class _TestWorker {
  _TestWorker(
    this.server,
    this.disconnectOnJob,
    this.malformedReply,
    this.measured,
    this.nodeId,
    this.replyDelay,
    this.stallFirstJob,
    this.binary,
  );

  final HttpServer server;
  final int? disconnectOnJob;
  final bool malformedReply;
  final bool measured;
  final String nodeId;
  final Duration replyDelay;
  final bool stallFirstJob;
  final bool binary;
  final binaryJobs = <Uint8List>[];
  int inFlight = 0;
  int maxInFlight = 0;
  final jobs = <String>[];
  final replies = <String>[];
  final sockets = <WebSocket>[];

  static Future<_TestWorker> start({
    int? disconnectOnJob,
    bool malformedReply = false,
    bool measured = false,
    String nodeId = 'TEST-WORKER',
    Duration replyDelay = Duration.zero,
    bool stallFirstJob = false,
    bool binary = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final worker = _TestWorker(
      server,
      disconnectOnJob,
      malformedReply,
      measured,
      nodeId,
      replyDelay,
      stallFirstJob,
      binary,
    );
    server.listen(worker._accept);
    return worker;
  }

  Future<void> _accept(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((data) async {
      final Map message;
      if (data is List<int>) {
        final frame = data is Uint8List ? data : Uint8List.fromList(data);
        binaryJobs.add(frame);
        final job = BinaryImageJob.decode(frame);
        message = {
          'type': 'job',
          'payload': {
            'jobId': job.jobId,
            'images': job.images.map((image) => image.toJson()).toList(),
          },
        };
      } else {
        message = jsonDecode(data as String) as Map;
      }
      final payload = Map<String, dynamic>.from(message['payload'] as Map);
      switch (message['type']) {
        case 'heartbeat':
          if (measured) {
            _send(socket, 'heartbeat_ack', {'probeId': 'wrong-id'});
            _send(socket, 'heartbeat_ack', {
              'probeId': payload['probeId'],
              'telemetry': _telemetry(nodeId).toJson(),
            });
          }
        case 'connection_request':
          _send(socket, 'connection_response', {
            'requestId': payload['requestId'],
            'approved': true,
          });
        case 'hello':
          _send(socket, 'hello_ack', {
            'nodeId': nodeId,
            'role': 'worker',
            'telemetry': _telemetry(nodeId).toJson(),
            if (binary) 'capabilities': [BinaryImageJob.capability],
          });
        case 'job':
          if (data is String) jobs.add(data);
          final jobCount = jobs.length + binaryJobs.length;
          if (stallFirstJob && jobCount == 1) return;
          if (jobCount == disconnectOnJob) {
            unawaited(socket.close());
            return;
          }
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          if (replyDelay != Duration.zero) {
            await Future<void>.delayed(replyDelay);
          }
          // These messages must not be charged to the workload.
          _send(socket, 'heartbeat', {});
          _send(socket, 'job_result', {'jobId': 'unknown-job'});
          final response = <String, dynamic>{
            'jobId': payload['jobId'],
            if (measured) 'processingMicroseconds': 20000,
          };
          if (malformedReply) {
            response['result'] = 'invalid result ✓';
          } else if (payload['images'] is List) {
            response['kind'] = 'images';
            response['results'] = [
              for (final raw in payload['images'] as List)
                _decodeImage(
                  InventoryImageTask.fromJson(
                    Map<String, dynamic>.from(raw as Map),
                  ),
                ).toJson(),
            ];
          } else if (payload['kind'] == 'math') {
            final problem = MathProblem.fromId(payload['problem'] as String);
            final tasks = [
              for (final raw in payload['tasks'] as List)
                MathTask.fromJson(Map<String, dynamic>.from(raw as Map)),
            ];
            response['kind'] = 'math';
            response['problem'] = problem.id;
            response['results'] = MathWorkloadEngine.process(
              problem,
              tasks,
            ).map((result) => result.toJson()).toList();
          } else {
            final batch = InventoryProcessor.process(
              List<String>.from(payload['labels'] as List),
            ).toJson();
            for (final label in batch['labels'] as List) {
              label['reason'] = 'Validated ✓ 📦';
            }
            response['kind'] = 'labels';
            response['result'] = batch;
          }
          replies.add(_send(socket, 'job_result', response));
          // A duplicate response must not be counted twice.
          _send(socket, 'job_result', response);
          inFlight--;
      }
    });
  }

  String _send(WebSocket socket, String type, Map<String, dynamic> payload) {
    final message = jsonEncode({
      'version': 1,
      'type': type,
      'payload': payload,
    });
    socket.add(message);
    return message;
  }

  void sendThermalUpdate(ThermalState state) {
    for (final socket in sockets) {
      _send(socket, 'heartbeat', {
        'telemetry': _telemetry(nodeId).copyWith(thermalState: state).toJson(),
      });
    }
  }

  Future<void> dispose() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
