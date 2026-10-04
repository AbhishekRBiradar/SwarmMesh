import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/inventory_execution.dart';
import 'package:swarm_mesh/models/inventory_models.dart';
import 'package:swarm_mesh/models/inventory_report.dart';
import 'package:swarm_mesh/models/inventory_session.dart';
import 'package:swarm_mesh/models/mesh_models.dart';
import 'package:swarm_mesh/models/node_telemetry.dart';
import 'package:swarm_mesh/screens/radar_home_screen.dart';
import 'package:swarm_mesh/screens/session_history_screen.dart';
import 'package:swarm_mesh/screens/session_report_screen.dart';
import 'package:swarm_mesh/services/device_telemetry_service.dart';
import 'package:swarm_mesh/services/inventory_image_service.dart';
import 'package:swarm_mesh/services/mesh_runtime_service.dart';
import 'package:swarm_mesh/services/session_history_service.dart';
import 'package:swarm_mesh/theme/app_theme.dart';

void main() {
  testWidgets(
    'report search and issue filters preserve record identity and full exports',
    (tester) async {
      final session = _session(
        labels: ['PKG-000001', 'PKG-000001', 'BROKEN', ''],
      );
      InventorySession? exported;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SessionReportScreen(
            session: session,
            exportReport: (value, _) async {
              exported = value;
              return null;
            },
          ),
        ),
      );
      final search = find.byKey(const ValueKey('report-search'));
      await tester.scrollUntilVisible(
        search,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(search, 'PKG-000001');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Duplicates'));
      await tester.tap(find.text('Duplicates'));
      await tester.pumpAndSettle();
      final record = find.byKey(const ValueKey('record-2'));
      await tester.scrollUntilVisible(
        record,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(record, findsOneWidget);
      expect(find.byKey(const ValueKey('record-1')), findsNothing);
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export JSON'));
      await tester.pumpAndSettle();
      expect(exported!.result.results.length, 4);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'missing-query');
      await tester.pumpAndSettle();
      expect(
        find.text('No records match this search and filter.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'explicit demo choice survives numeric Android filenames and is saved correctly',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      final picker = _ImagePicker()..files = [_PickedImage('1000274537.png')];
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final runtime = _PreviewRuntime();
      final history = _MemoryHistory([]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: RadarHomeScreen(
            runtime: runtime,
            telemetryService: _PreviewTelemetry(),
            history: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('LEADER'));
      await tester.pumpAndSettle();
      await runtime.start(role: MeshRole.leader);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Workloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventory verification'));
      await tester.pumpAndSettle();
      final demoSwitch = find.byType(SwitchListTile);
      await tester.ensureVisible(demoSwitch);
      await tester.tap(demoSwitch);
      await tester.pumpAndSettle();
      final datasetField = find.byType(TextField).last;
      await tester.ensureVisible(datasetField);
      await tester.enterText(datasetField, 'Two-phone demo experiment');

      Future<void> pick(String label) async {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> run() async {
        final button = find.text('Run image workload');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await pick('SELECT IMAGES');
      expect(tester.widget<SwitchListTile>(demoSwitch).value, isTrue);
      expect(
        tester.widget<TextField>(datasetField).controller!.text,
        'Two-phone demo experiment',
      );
      await run();
      expect(history.sessions.single.isDemo, isTrue);
      expect(history.sessions.single.toJson()['isDemo'], isTrue);

      picker.files = [];
      await pick('1 IMAGES SELECTED');
      expect(tester.widget<SwitchListTile>(demoSwitch).value, isTrue);
      expect(find.text('1 IMAGES SELECTED'), findsOneWidget);

      // An explicit non-demo choice also wins over recognized sample filenames.
      await tester.ensureVisible(demoSwitch);
      await tester.tap(demoSwitch);
      await tester.pumpAndSettle();
      picker.files = [_PickedImage()];
      await pick('1 IMAGES SELECTED');
      expect(tester.widget<SwitchListTile>(demoSwitch).value, isFalse);
      await run();
      expect(history.sessions.last.isDemo, isFalse);
      expect(history.sessions.last.datasetName, 'Two-phone demo experiment');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'three-pair benchmark control performs and saves three completed pairs',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _ImagePicker();
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final runtime = _PreviewRuntime();
      final history = _MemoryHistory([]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: RadarHomeScreen(
            runtime: runtime,
            telemetryService: _PreviewTelemetry(),
            history: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('LEADER'));
      await tester.pumpAndSettle();
      await runtime.start(role: MeshRole.leader);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventory verification'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('SELECT IMAGES'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('SELECT IMAGES'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Run 3-pair image benchmark'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Run 3-pair image benchmark'));
      await tester.pumpAndSettle();
      expect(runtime.imageRuns, 3);
      expect(history.sessions, hasLength(3));
      expect(
        history.sessions.map((session) => session.id).toSet(),
        hasLength(3),
      );
      expect(
        history.sessions.map((session) => session.benchmarkGroupId).toSet(),
        hasLength(1),
      );
      expect(history.sessions.every((session) => session.isDemo), isTrue);
      expect(find.text('Repeated benchmark: 3/3 completed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'report export handles cancellation and errors without a stuck spinner',
    (tester) async {
      var exports = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SessionReportScreen(
            session: _session(),
            exportReport: (_, _) async {
              if (exports++ == 0) return null;
              throw StateError('disk full');
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Export cancelled'), findsOneWidget);
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not export report'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'history reopens reports and deletion requires the selected session confirmation',
    (tester) async {
      final history = _MemoryHistory([_session()]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SessionHistoryScreen(history: history),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test audit'));
      await tester.pumpAndSettle();
      expect(find.text('Inventory report'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Test audit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(history.sessions, hasLength(1));
      await tester.tap(find.byTooltip('Delete Test audit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(history.sessions, isEmpty);
      expect(find.textContaining('No saved sessions yet'), findsOneWidget);
    },
  );

  testWidgets(
    'small-screen home respects reduced motion while discovery is active',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = _PreviewRuntime();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.2),
            ),
            child: child!,
          ),
          home: RadarHomeScreen(
            runtime: runtime,
            telemetryService: _PreviewTelemetry(),
            history: _MemoryHistory([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('LEADER'));
      await tester.pumpAndSettle();
      await runtime.start(role: MeshRole.leader);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.scrollUntilVisible(
        find.text('REPORTS & HISTORY'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No report yet.'), findsOneWidget);
      for (final destination in ['Workloads', 'Network']) {
        await tester.tap(find.text(destination));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('role selection locks for the app session', (tester) async {
    final runtime = _PreviewRuntime();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RadarHomeScreen(
          runtime: runtime,
          telemetryService: _PreviewTelemetry(),
          history: _MemoryHistory([]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline Distributed Work Platform'), findsOneWidget);
    await tester.tap(find.text('WORKER'));
    await tester.pumpAndSettle();
    expect(find.text('WORKER WORKSPACE'), findsOneWidget);
    expect(find.text('Workloads'), findsNothing);
    expect(find.text('LEADER'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('below-20-percent battery locks the workspace', (tester) async {
    final runtime = _PreviewRuntime();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RadarHomeScreen(
          runtime: runtime,
          telemetryService: _PreviewTelemetry(battery: 19),
          history: _MemoryHistory([]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SWARM MESH LOCKED'), findsOneWidget);
    expect(
      find.textContaining('below the 20% access threshold'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

InventorySession _session({List<String> labels = const ['PKG-000001']}) {
  final batch = InventoryProcessor.process(labels);
  final run = MeshRunResult(
    mode: 'local-fallback',
    labels: labels,
    expectedIds: const {},
    results: batch.labels,
    report: InventoryReport.aggregate(
      originalLabels: labels,
      workerBatches: [batch],
      expectedIds: const [],
    ),
    elapsed: const Duration(milliseconds: 10),
    contributions: {'L': labels.length},
    retries: 0,
    sentBytes: 0,
    receivedBytes: 0,
    executions: [
      for (final label in batch.labels)
        InventoryExecution(
          label: label,
          nodeId: 'L',
          attempts: const [InventoryAttempt(nodeId: 'L', succeeded: true)],
        ),
    ],
  );
  return InventorySession(
    id: 'ui-session',
    createdAt: DateTime.utc(2026),
    datasetName: 'Test audit',
    isDemo: true,
    leaderNodeId: 'L',
    devices: const {'L': 'Phone'},
    baseline: run,
    result: run,
  );
}

class _MemoryHistory extends SessionHistoryService {
  _MemoryHistory(this.sessions);
  final List<InventorySession> sessions;
  @override
  Future<void> save(InventorySession session) async => sessions.add(session);
  @override
  Future<SessionHistory> load() async => SessionHistory(List.of(sessions), []);
  @override
  Future<void> delete(String id) async =>
      sessions.removeWhere((session) => session.id == id);
}

class _PreviewTelemetry extends DeviceTelemetryService {
  _PreviewTelemetry({this.battery = 100});
  final int battery;

  @override
  Future<NodeTelemetry> collectTelemetry({
    required String nodeId,
    bool isLeader = false,
  }) async => NodeTelemetry(
    nodeId: nodeId,
    deviceModel: 'Test phone',
    batteryLevel: battery,
    cpuCores: 4,
    computeWeight: 4,
    isLeader: isLeader,
    status: 'READY',
    timestamp: DateTime(2026),
  );
}

class _PreviewImageService extends InventoryImageService {
  @override
  Future<void> dispose() async {}
}

class _PreviewRuntime extends MeshRuntimeService {
  _PreviewRuntime() : super(imageService: _PreviewImageService());
  final _changes = StreamController<MeshRuntimeSnapshot>.broadcast();
  MeshRuntimeSnapshot _state = const MeshRuntimeSnapshot();
  int imageRuns = 0;
  @override
  Stream<MeshRuntimeSnapshot> get snapshots => _changes.stream;
  @override
  MeshRuntimeSnapshot get snapshot => _state;
  @override
  Future<void> start({required MeshRole role}) async {
    _state = MeshRuntimeSnapshot(
      active: true,
      isLeader: role == MeshRole.leader,
      phase: 'RADAR ACTIVE',
    );
    _changes.add(_state);
  }

  @override
  Future<void> runImageWorkload(
    List<String> paths, {
    Iterable<String> expectedIds = const [],
  }) async {
    imageRuns++;
    final session = _session();
    _state = MeshRuntimeSnapshot(
      active: true,
      localTelemetry: await _PreviewTelemetry().collectTelemetry(
        nodeId: 'L',
        isLeader: true,
      ),
      phase: 'IMAGE REPORT READY',
      result: session.result,
      singleResult: session.baseline,
      swarmResult: session.result,
    );
    _changes.add(_state);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await _changes.close();
    await super.dispose();
  }
}

class _ImagePicker extends FilePickerPlatform {
  List<PlatformFile> files = [_PickedImage()];
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

final class _PickedImage extends PlatformFile {
  _PickedImage([this.name = 'label_01.png']);
  @override
  final String name;
  @override
  Uri get uri => Uri.file('/demo/$name');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
