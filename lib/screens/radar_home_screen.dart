import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../models/inventory_session.dart';
import '../models/math_workload.dart';
import '../models/mesh_models.dart';
import '../models/node_telemetry.dart';
import '../models/node_performance.dart';
import '../models/workload_catalog.dart';
import '../services/device_telemetry_service.dart';
import '../services/mesh_runtime_service.dart';
import '../services/session_history_service.dart';
import 'session_history_screen.dart';
import 'math_report_screen.dart';
import 'session_report_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/mesh_topology.dart';
import '../widgets/run_insights.dart';
import '../widgets/swarm_logo.dart';

class RadarHomeScreen extends StatefulWidget {
  const RadarHomeScreen({
    super.key,
    this.runtime,
    this.telemetryService,
    this.history,
  });
  final MeshRuntimeService? runtime;
  final DeviceTelemetryService? telemetryService;
  final SessionHistoryService? history;

  @override
  State<RadarHomeScreen> createState() => _RadarHomeScreenState();
}

class _RadarHomeScreenState extends State<RadarHomeScreen>
    with SingleTickerProviderStateMixin {
  static const _yellow = AppColors.accent;
  static const _background = AppColors.background;
  static const _panel = AppColors.surface;

  late final _runtime = widget.runtime ?? MeshRuntimeService();
  late final _telemetryService =
      widget.telemetryService ?? DeviceTelemetryService();
  final _hostController = TextEditingController();
  final _datasetController = TextEditingController(text: 'Inventory session');
  late final _history = widget.history ?? SessionHistoryService();
  late final AnimationController _radarController;
  late final StreamSubscription<MeshRuntimeSnapshot> _snapshotSubscription;

  MeshRuntimeSnapshot _snapshot = const MeshRuntimeSnapshot();
  NodeTelemetry? _previewTelemetry;
  MeshRole _role = MeshRole.leader;
  bool _roleChosen = false;
  List<String> _imagePaths = const [];
  List<String> _expectedIds = const [];
  InventorySession? _lastSession;
  MathSession? _lastMathSession;
  String? _saveError;
  String? _mathSaveError;
  bool _savingSession = false;
  bool _savingMathSession = false;
  bool _isDemoDataset = false;
  bool? _demoDatasetChoice;
  bool _benchmarking = false;
  bool _benchmarkCancelled = false;
  bool _reducedMotion = false;
  String _selectedWorkload = 'mathematics';
  MathProblem _mathProblem = MathProblem.monteCarloPi;
  MathRunResult? _lastMathResult;
  Timer? _monitorTimer;
  Timer? _peerSearchTimer;
  DateTime? _meshStartedAt;
  int _peerSearchSeconds = 0;
  bool _roleLocked = false;
  bool _batteryLockRequested = false;
  bool _batteryAccessBlocked = false;
  int _page = 0;
  final _benchmarkSessions = <InventorySession>[];
  bool get _busy =>
      _snapshot.running ||
      _benchmarking ||
      _savingSession ||
      _savingMathSession;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _snapshotSubscription = _runtime.snapshots.listen(_handleSnapshot);
    _loadPreviewTelemetry();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadPreviewTelemetry(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncRadar();
  }

  void _handleSnapshot(MeshRuntimeSnapshot snapshot) {
    if (mounted) setState(() => _snapshot = snapshot);
    _syncRadar();
    _syncPeerSearchTimer(snapshot);
    final telemetry = snapshot.localTelemetry;
    if (telemetry?.accessBlockReason != null) {
      _batteryAccessBlocked = true;
    } else if (telemetry != null) {
      _batteryAccessBlocked = false;
    }
    if (telemetry?.accessBlockReason != null &&
        snapshot.active &&
        !_batteryLockRequested) {
      _batteryLockRequested = true;
      _benchmarkCancelled = true;
      unawaited(_runtime.stop());
    }
    if (telemetry?.accessBlockReason == null) {
      _batteryLockRequested = false;
    }
  }

  void _chooseRole(MeshRole role) {
    if (_roleLocked || !mounted) return;
    setState(() {
      _role = role;
      _roleLocked = true;
      _roleChosen = true;
      _previewTelemetry = _previewTelemetry?.copyWith(
        isLeader: role == MeshRole.leader,
      );
    });
    _runtime.setRole(role);
  }

  void _syncPeerSearchTimer(MeshRuntimeSnapshot snapshot) {
    final searching = snapshot.active || snapshot.starting;
    if (searching && _meshStartedAt == null) {
      _meshStartedAt = DateTime.now();
      _peerSearchSeconds = 0;
      _peerSearchTimer?.cancel();
      _peerSearchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _meshStartedAt == null) return;
        setState(
          () => _peerSearchSeconds = DateTime.now()
              .difference(_meshStartedAt!)
              .inSeconds,
        );
      });
    } else if (!searching) {
      _peerSearchTimer?.cancel();
      _peerSearchTimer = null;
      _meshStartedAt = null;
      _peerSearchSeconds = 0;
    }
  }

  bool get _accessBlocked =>
      _batteryAccessBlocked ||
      (_snapshot.localTelemetry ?? _previewTelemetry)?.accessBlockReason !=
          null;

  String _elapsedLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  String _ageLabel(DateTime timestamp) {
    final seconds = DateTime.now().difference(timestamp).inSeconds;
    return seconds <= 1 ? 'just now' : '${seconds}s ago';
  }

  void _syncRadar() {
    if (_page == 0 &&
        (_snapshot.active || _snapshot.starting) &&
        !_reducedMotion) {
      if (!_radarController.isAnimating) _radarController.repeat();
    } else {
      _radarController.stop();
    }
  }

  Future<void> _loadPreviewTelemetry() async {
    final telemetry = await _telemetryService.collectTelemetry(
      nodeId: 'STANDBY',
      isLeader: _role == MeshRole.leader,
    );
    if (mounted) {
      setState(() => _previewTelemetry = telemetry);
      _batteryAccessBlocked = telemetry.accessBlockReason != null;
      if (telemetry.accessBlockReason == null) {
        _batteryLockRequested = false;
      } else if (_snapshot.active && !_batteryLockRequested) {
        _batteryLockRequested = true;
        _benchmarkCancelled = true;
        unawaited(_runtime.stop());
      }
    }
  }

  @override
  void dispose() {
    _snapshotSubscription.cancel();
    _monitorTimer?.cancel();
    _peerSearchTimer?.cancel();
    _runtime.dispose();
    _hostController.dispose();
    _datasetController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _toggleMesh() async {
    if (_snapshot.active) {
      _benchmarkCancelled = true;
      await _runtime.stop();
      return;
    }
    if (!_roleLocked && mounted) setState(() => _roleLocked = true);
    await _runtime.start(role: _role);
  }

  Future<void> _connectManually() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;
    await _runtime.connectManually(host);
    if (mounted) _hostController.clear();
  }

  Future<void> _pickImages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final paths = files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (!mounted || paths.isEmpty) return;
    final demoNames = RegExp(
      r'^(label_\d{2}|duplicate_0[12]|invalid_0[12]|unreadable_0[123]|unexpected)\.png$',
    );
    setState(() {
      _imagePaths = paths;
      // Filename detection is only a default. Android photo providers may
      // replace names with numeric IDs, so never overwrite an explicit choice.
      _isDemoDataset =
          _demoDatasetChoice ??
          files
              .where((file) => file.path != null && file.path!.isNotEmpty)
              .every((file) => demoNames.hasMatch(file.name));
      if (_isDemoDataset &&
          {'', 'Inventory session'}.contains(_datasetController.text.trim())) {
        _datasetController.text = 'Demo Dataset';
      }
      _lastSession = null;
      _benchmarkSessions.clear();
    });
  }

  Future<void> _pickExpectedIds() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;
    try {
      final content = await File(path).readAsString();
      final ids =
          RegExp(r'PKG-\d{6}', caseSensitive: false)
              .allMatches(content)
              .map((match) => match.group(0)!.toUpperCase())
              .toSet()
              .toList(growable: false)
            ..sort();
      if (!mounted) return;
      setState(() => _expectedIds = ids);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read expected-ID list: $error')),
      );
    }
  }

  Future<void> _runImageWorkload() async {
    if (_busy) return;
    _benchmarkSessions.clear();
    await _runtime.runImageWorkload(_imagePaths, expectedIds: _expectedIds);
    await _captureSession(
      datasetName: _datasetController.text,
      isDemo: _isDemoDataset,
    );
  }

  Future<void> _runDemoWorkload() async {
    if (_busy) return;
    _benchmarkSessions.clear();
    await _runtime.runDemoWorkload();
    await _captureSession(
      datasetName: 'Synthetic protocol Demo Dataset',
      isDemo: true,
    );
  }

  Future<void> _runMathWorkload() async {
    if (_busy) return;
    await _runtime.runMathWorkload(_mathProblem);
    final snapshot = _runtime.snapshot;
    final result = snapshot.swarmMathResult;
    final baseline = snapshot.singleMathResult;
    if (mounted && result != null) {
      setState(() => _lastMathResult = result);
      if (baseline != null) {
        final session = MathSession.capture(baseline, result);
        setState(() {
          _lastMathSession = session;
          _mathSaveError = null;
        });
        await _saveMathSession(session);
      }
    }
  }

  Future<void> _saveMathSession(MathSession session) async {
    if (mounted) {
      setState(() {
        _savingMathSession = true;
        _mathSaveError = null;
      });
    }
    try {
      await _history.saveMath(session);
    } catch (error) {
      if (mounted) setState(() => _mathSaveError = error.toString());
    } finally {
      if (mounted) setState(() => _savingMathSession = false);
    }
  }

  Future<InventorySession?> _captureSession({
    required String datasetName,
    required bool isDemo,
    String? groupId,
  }) async {
    final snapshot = _runtime.snapshot;
    if (snapshot.running ||
        snapshot.swarmResult == null ||
        snapshot.singleResult == null ||
        snapshot.localTelemetry == null ||
        identical(_lastSession?.result, snapshot.swarmResult)) {
      return null;
    }
    final session = InventorySession.capture(
      snapshot,
      datasetName: datasetName,
      isDemo: isDemo,
      benchmarkGroupId: groupId,
    );
    if (mounted) {
      setState(() {
        _lastSession = session;
        _saveError = null;
      });
    }
    await _saveSession(session);
    return session;
  }

  Future<void> _saveSession(InventorySession session) async {
    if (mounted) {
      setState(() {
        _savingSession = true;
        _saveError = null;
      });
    }
    try {
      await _history.save(session);
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    } finally {
      if (mounted) setState(() => _savingSession = false);
    }
  }

  Future<void> _runRepeatedBenchmark() async {
    if (_busy || _imagePaths.isEmpty) return;
    final paths = List<String>.of(_imagePaths);
    final expected = List<String>.of(_expectedIds);
    final name = _datasetController.text;
    final demo = _isDemoDataset;
    final groupId = InventorySession.newId();
    setState(() {
      _benchmarking = true;
      _benchmarkCancelled = false;
      _benchmarkSessions.clear();
    });
    try {
      for (var run = 0; run < 3 && !_benchmarkCancelled; run++) {
        if (!mounted || !_runtime.snapshot.active) break;
        await _runtime.runImageWorkload(paths, expectedIds: expected);
        final session = await _captureSession(
          datasetName: name,
          isDemo: demo,
          groupId: groupId,
        );
        if (session == null) break;
        if (mounted) setState(() => _benchmarkSessions.add(session));
        if (!session.correctnessMatch || _saveError != null) break;
      }
    } finally {
      if (mounted) setState(() => _benchmarking = false);
    }
  }

  void _openHistory() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionHistoryScreen(history: _history),
    ),
  );

  void _showAbout() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('About SWARM MESH'),
      content: const SingleChildScrollView(
        child: Text(
          'Version 1.2.5 · build 9\n\n'
          'Offline distributed computing across nearby Android devices. Inventory verification '
          'is one workload adapter; mathematical computing is another.\n\n'
          'Work is sent only to approved local devices. Inventory reports are saved in private, '
          'no-backup storage on the Leader until deleted. Source images are not copied into '
          'report history. Exported files are saved to the location you choose.\n\n'
          'No cloud backend, accounts, payments or analytics are integrated.\n\n'
          'Operator, contact, jurisdiction and legal terms are awaiting confirmation.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            showLicensePage(
              context: this.context,
              applicationName: 'SWARM MESH',
               applicationVersion: '1.2.5+9',
            );
          },
          child: const Text('Open-source notices'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _buildSessionReports() => _panelBox(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('REPORTS & HISTORY', Icons.description_outlined),
        const SizedBox(height: 12),
        Text(
          _lastSession != null
              ? '${_lastSession!.datasetName}${_lastSession!.isDemo ? ' · Demo Dataset' : ''}'
              : _lastMathSession != null
              ? '${_lastMathSession!.problem.title} · mathematical run'
              : 'No report yet.',
        ),
        if (_savingSession)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_saveError != null) ...[
          Text(
            'History save failed: $_saveError',
            style: const TextStyle(color: Colors.orangeAccent),
          ),
          TextButton(
            onPressed: _savingSession || _lastSession == null
                ? null
                : () => _saveSession(_lastSession!),
            child: const Text('Retry saving report'),
          ),
        ],
        if (_savingMathSession)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_mathSaveError != null) ...[
          Text(
            'Mathematical history save failed: $_mathSaveError',
            style: const TextStyle(color: Colors.orangeAccent),
          ),
          TextButton(
            onPressed: _savingMathSession || _lastMathSession == null
                ? null
                : () => _saveMathSession(_lastMathSession!),
            child: const Text('Retry saving mathematical report'),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _lastSession == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SessionReportScreen(session: _lastSession!),
                      ),
                    ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Open / export report'),
            ),
            OutlinedButton.icon(
              onPressed: _lastMathSession == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MathReportScreen(session: _lastMathSession!),
                      ),
                    ),
              icon: const Icon(Icons.functions),
              label: const Text('Open math report'),
            ),
            OutlinedButton.icon(
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
              label: const Text('History'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Saved on this Leader until deleted.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        if (_benchmarkSessions.isNotEmpty) ...[
          const Divider(height: 24),
          _buildRepeatedSummary(),
        ],
      ],
    ),
  );

  Widget _buildRepeatedSummary() {
    final summary = BenchmarkSummary(_benchmarkSessions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeated benchmark: ${_benchmarkSessions.length}/3 completed',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          'Median single: ${(summary.medianSingleMicroseconds / 1000).toStringAsFixed(2)} ms',
        ),
        Text(
          'Best / worst single: ${(summary.bestSingleMicroseconds / 1000).toStringAsFixed(2)} / '
          '${(summary.worstSingleMicroseconds / 1000).toStringAsFixed(2)} ms',
        ),
        Text(
          'Median ${summary.allSwarm ? 'swarm' : 'distributed path (includes local fallback)'}: '
          '${(summary.medianSwarmMicroseconds / 1000).toStringAsFixed(2)} ms',
        ),
        Text(
          'Best / worst distributed: ${(summary.bestSwarmMicroseconds / 1000).toStringAsFixed(2)} / '
          '${(summary.worstSwarmMicroseconds / 1000).toStringAsFixed(2)} ms',
        ),
        Text(
          'Correctness across runs: ${summary.comparable ? 'matches' : 'MISMATCH / different input'}',
        ),
        if (summary.speedup != null)
          Text('Median speedup: ${summary.speedup!.toStringAsFixed(2)}×'),
        const Text(
          'Order: single device, then distributed.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accessBlocked) return _buildBatteryBlockedScreen();
    if (!_roleChosen) return _buildRoleSelectionScreen();
    final telemetry = _snapshot.localTelemetry ?? _previewTelemetry;
    final worker = _role == MeshRole.worker;
    return Scaffold(
      backgroundColor: _background,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (index) {
          setState(() => _page = index);
          _syncRadar();
        },
        destinations: worker
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.memory_outlined),
                  selectedIcon: Icon(Icons.memory),
                  label: 'Worker',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: 'Network',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard),
                  label: 'Command',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Workloads',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: 'Network',
                ),
              ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey('workspace-${_role.name}-$_page'),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      children: [
                        _buildStatus(),
                        if (_snapshot.pendingRequests.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildConnectionApprovals(),
                        ],
                        const SizedBox(height: 18),
                        if (worker && _page == 0) ...[
                          _buildWorkerGuide(),
                          const SizedBox(height: 18),
                          if (telemetry != null) _buildNodeCard(telemetry),
                          const SizedBox(height: 18),
                          _buildRadar(),
                          const SizedBox(height: 18),
                          _buildEvents(),
                        ] else if (worker) ...[
                          if (telemetry != null) _buildNodeCard(telemetry),
                          const SizedBox(height: 18),
                          _buildPeerPanel(),
                          const SizedBox(height: 18),
                          _buildConnectionFallback(),
                          const SizedBox(height: 18),
                          _buildEvents(),
                        ] else if (_page == 0) ...[
                          _buildCommandIntro(),
                          const SizedBox(height: 18),
                          _buildMeshControl(),
                          const SizedBox(height: 18),
                          _buildRadar(),
                          const SizedBox(height: 18),
                          _buildStats(telemetry),
                          const SizedBox(height: 18),
                          _buildSessionReports(),
                        ] else if (_page == 1) ...[
                          _buildWorkloadSelector(),
                          if (_role == MeshRole.leader)
                            const SizedBox(height: 18),
                          if (_role == MeshRole.leader &&
                              _selectedWorkload == 'inventory')
                            _buildImageInputPanel(),
                          if (_role == MeshRole.leader &&
                              _selectedWorkload == 'mathematics')
                            _buildMathPanel(),
                          if (_role == MeshRole.leader &&
                              _selectedWorkload != 'model-training')
                            const SizedBox(height: 18),
                          if (_role == MeshRole.leader &&
                              _selectedWorkload == 'inventory')
                            _buildWorkPanel()
                          else if (_role == MeshRole.leader &&
                              _selectedWorkload == 'model-training')
                            _buildPlannedWorkloadPanel()
                          else if (_role != MeshRole.leader)
                            _buildWorkerGuide(),
                          const SizedBox(height: 18),
                          _buildSessionReports(),
                        ] else ...[
                          if (telemetry != null) _buildNodeCard(telemetry),
                          const SizedBox(height: 18),
                          _buildPeerPanel(),
                          const SizedBox(height: 18),
                          _buildConnectionFallback(),
                          const SizedBox(height: 18),
                          _buildEvents(),
                        ],
                        const SizedBox(height: 18),
                        TextButton.icon(
                          onPressed: _showAbout,
                          icon: const Icon(Icons.info_outline),
                          label: const Text(
                            'About / Legal / Open-source notices',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelectionScreen() => Scaffold(
    backgroundColor: _background,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SwarmLogo(size: 132),
                const SizedBox(height: 22),
                const Text(
                  'SWARM MESH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Offline Distributed Work Platform',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    _roleButton(
                      MeshRole.leader,
                      'LEADER',
                      Icons.account_tree_rounded,
                    ),
                    const SizedBox(width: 10),
                    _roleButton(
                      MeshRole.worker,
                      'WORKER',
                      Icons.memory_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBatteryBlockedScreen() {
    final telemetry = _snapshot.localTelemetry ?? _previewTelemetry;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SwarmLogo(size: 132),
                const SizedBox(height: 28),
                const Text(
                  'SWARM MESH LOCKED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Battery is below the 20% access threshold. Connect the device to power; SWARM MESH will monitor the battery and unlock automatically at 20% or higher.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                if (telemetry != null)
                  Text(
                    '${telemetry.batteryLevel}% · ${telemetry.deviceModel}\nUpdated ${_ageLabel(telemetry.timestamp)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 22),
                const CircularProgressIndicator(value: 1),
                const SizedBox(height: 12),
                const Text(
                  'Live device monitoring is active',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          const SwarmLogo(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SWARM MESH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  _role.name.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openHistory,
            tooltip: 'Saved sessions',
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
    );
  }

  Widget _roleButton(MeshRole role, String label, IconData icon) {
    final selected = _role == role;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _snapshot.active || _snapshot.starting || _roleLocked
            ? null
            : () => _chooseRole(role),
        child: AnimatedContainer(
          duration: _reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _yellow : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.black : AppColors.muted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final busy = _snapshot.starting || _snapshot.running;
    final color = _snapshot.phase == 'ERROR' ? Colors.redAccent : _yellow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _snapshot.phase == 'ERROR'
              ? Colors.redAccent.withValues(alpha: .5)
              : const Color(0xFF2A2A2A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            busy ? Icons.sync : Icons.wifi_tethering,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _snapshot.phase,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          Flexible(
            child: Text(
              _snapshot.connectedPeers == 0
                  ? (_snapshot.active ? 'NO PEERS' : 'READY')
                  : '${_snapshot.connectedPeers} PEER${_snapshot.connectedPeers == 1 ? '' : 'S'}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadar() {
    return MeshTopology(snapshot: _snapshot, animation: _radarController);
  }

  Widget _buildCommandIntro() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'LOCAL MESH',
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 11,
            letterSpacing: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _role == MeshRole.leader ? 'Choose a workload.' : 'Worker ready.',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.12,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _role == MeshRole.leader
            ? 'Split work across nearby devices.'
            : 'Approve a Leader to receive work.',
        style: const TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _pill(
            _snapshot.active ? '01  MESH ACTIVE' : '01  START MESH',
            active: _snapshot.active,
          ),
          _pill(
            _selectedWorkload == 'mathematics'
                ? '02  MATH'
                : _selectedWorkload == 'inventory'
                ? '02  ${_imagePaths.length} IMAGES'
                : '02  PLAN',
            active:
                _selectedWorkload == 'mathematics' || _imagePaths.isNotEmpty,
          ),
          _pill(
            _lastSession == null && _lastMathSession == null
                ? '03  READY'
                : '03  REPORT',
            active: _lastSession != null || _lastMathSession != null,
          ),
        ],
      ),
      if (_snapshot.active && _snapshot.connectedPeers == 0) ...[
        const SizedBox(height: 14),
        _buildNoDevicesNotice(),
      ],
      if (_snapshot.running) ...[
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _snapshot.totalLabels == 0
              ? null
              : _snapshot.progress.clamp(0, 1),
        ),
        const SizedBox(height: 8),
        Text(_snapshot.message, style: const TextStyle(color: AppColors.muted)),
      ],
      if (_role == MeshRole.leader) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() => _page = 1);
            _syncRadar();
          },
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('OPEN WORKLOADS'),
        ),
      ],
    ],
  );

  Widget _buildNoDevicesNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.orangeAccent.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orangeAccent.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.devices_other_outlined, color: Colors.orangeAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _peerSearchSeconds < 15
                ? 'Searching · ${_elapsedLabel(_peerSearchSeconds)}'
                : 'No device found. Start a Worker or use Network.',
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildMeshControl() => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: _snapshot.starting ? null : _toggleMesh,
      style: _snapshot.active
          ? FilledButton.styleFrom(
              backgroundColor: AppColors.elevated,
              foregroundColor: AppColors.error,
            )
          : null,
      icon: Icon(
        _snapshot.active
            ? Icons.stop_circle_outlined
            : Icons.power_settings_new,
      ),
      label: Text(
        _snapshot.starting
            ? 'STARTING…'
            : _snapshot.active
            ? 'STOP MESH'
            : 'START ${_role.name.toUpperCase()}',
      ),
    ),
  );

  Widget _buildWorkerGuide() => _panelBox(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('WORKER WORKSPACE', Icons.memory_rounded),
        const SizedBox(height: 16),
        const Text(
          'Worker ready',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Start the Worker and approve a Leader.',
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        _buildMeshControl(),
      ],
    ),
  );

  Widget _buildStats(NodeTelemetry? telemetry) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'NODES',
            '${(_snapshot.active ? 1 : 0) + _snapshot.connectedPeers}',
            Icons.devices_rounded,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _statCard(
            'WORKLOAD',
            _selectedWorkload == 'mathematics'
                ? 'MATH'
                : _selectedWorkload == 'inventory'
                ? '${_imagePaths.length} IMG'
                : 'PLAN',
            Icons.functions,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _statCard(
            'BATTERY',
            telemetry?.batteryLevelKnown == true
                ? '${telemetry!.batteryLevel}%'
                : '—',
            Icons.battery_5_bar_rounded,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: _yellow, size: 19),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(NodeTelemetry telemetry) {
    return _panelBox(
      Column(
        children: [
          Row(
            children: [
              _iconBox(Icons.smartphone_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      telemetry.deviceModel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      telemetry.isLeader ? 'LEADER NODE' : 'WORKER NODE',
                      style: const TextStyle(
                        color: _yellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Telemetry updated ${_ageLabel(telemetry.timestamp)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _pill(telemetry.status, active: telemetry.status == 'READY'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'BATTERY',
                  telemetry.batteryLevelKnown
                      ? '${telemetry.batteryLevel}%'
                      : 'Unknown',
                ),
              ),
              Expanded(child: _metric('CORES', '${telemetry.cpuCores}')),
              Expanded(
                child: _metric(
                  'INITIAL WT.',
                  telemetry.computeWeight.toStringAsFixed(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMeasuredTelemetry(telemetry, _snapshot.localPerformance),
        ],
      ),
    );
  }

  Widget _buildMeasuredTelemetry(
    NodeTelemetry telemetry,
    NodePerformance performance, {
    bool remote = false,
  }) {
    final now = DateTime.now();
    final rtt = performance.freshRoundTrip(now);
    final charging = telemetry.isCharging == null
        ? 'Power state unavailable'
        : telemetry.isCharging!
        ? 'External power'
        : 'On battery';
    final measuredKinds = WorkloadKind.values
        .where((kind) => performance.timing(kind).sampleCount > 0)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${remote ? 'Battery: ${telemetry.batteryLevelKnown ? '${telemetry.batteryLevel}%' : 'unavailable'} · ' : ''}'
          '$charging · Thermal: ${telemetry.thermalState.label}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        Text(
          'Live telemetry: updated ${_ageLabel(telemetry.timestamp)}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        if (remote)
          Text(
            rtt == null
                ? 'Heartbeat RTT: not measured or stale'
                : 'Heartbeat RTT: ${rtt.toStringAsFixed(1)} ms (smoothed)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        if (measuredKinds.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Task timing: waiting for work',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        for (final kind in measuredKinds)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _timingDescription(kind, performance.timing(kind)),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        if (telemetry.computePauseReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Compute paused: ${telemetry.computePauseReason}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _timingDescription(WorkloadKind kind, TaskTiming timing) {
    final label = switch (kind) {
      WorkloadKind.images => 'Image decoding',
      WorkloadKind.labels => 'Record validation',
      WorkloadKind.mathematics => 'Mathematical tasks',
    };
    return '$label · ${timing.lastMilliseconds!.toStringAsFixed(2)} ms · '
        '${timing.averageMillisecondsPerItem!.toStringAsFixed(2)} ms/item'
        '${timing.isFresh(DateTime.now()) ? '' : ' · stale'}';
  }

  Widget _buildConnectionApprovals() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'CONNECTION PERMISSION',
            Icons.admin_panel_settings_rounded,
          ),
          const SizedBox(height: 8),
          const Text(
            'Review this device before approving.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          for (final request in _snapshot.pendingRequests)
            _connectionRequestRow(request),
        ],
      ),
    );
  }

  Widget _connectionRequestRow(MeshConnectionRequest request) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.devices_other_rounded, small: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.role} · ${request.telemetry.deviceModel}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${request.nodeId} · ${request.host}:${request.port}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _runtime.rejectConnection(request.requestId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('REJECT', style: TextStyle(fontSize: 10)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      _runtime.approveConnection(request.requestId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _yellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('APPROVE', style: TextStyle(fontSize: 10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeerPanel() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('DISCOVERED PEERS', Icons.radar_rounded),
          const SizedBox(height: 10),
          if (_snapshot.peers.isEmpty && _snapshot.endpoints.isEmpty)
            const Text(
              'No peers found.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            )
          else ...[
            for (final peer in _snapshot.peers) _peerRow(peer),
            for (final endpoint in _snapshot.endpoints.where(
              (endpoint) =>
                  !_snapshot.peers.any((peer) => peer.host == endpoint.host),
            ))
              _endpointRow(endpoint),
          ],
        ],
      ),
    );
  }

  Widget _peerRow(MeshPeer peer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(
                peer.connected ? Icons.phone_android : Icons.phone_disabled,
                small: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.telemetry.deviceModel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${peer.nodeId} · ${peer.host}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                peer.connected ? 'CONNECTED' : 'OFFLINE',
                style: TextStyle(
                  color: peer.connected ? _yellow : AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!peer.connected)
            const Text(
              'Last known measurements',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          _buildMeasuredTelemetry(
            peer.telemetry,
            peer.performance,
            remote: true,
          ),
        ],
      ),
    );
  }

  Widget _endpointRow(MeshEndpoint endpoint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_find, color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${endpoint.name}\n${endpoint.host}:${endpoint.port}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const Text(
            'DISCOVERED',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionFallback() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('HOTSPOT FALLBACK', Icons.link_rounded),
          const SizedBox(height: 8),
          const Text(
            'Use a Worker IP if discovery fails.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (_snapshot.addresses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'This device: ${_snapshot.addresses.map((address) => '$address:${_snapshot.port}').join('  ')}',
              style: const TextStyle(
                color: _yellow,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostController,
                  enabled: _snapshot.active,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Worker IPv4, e.g. 192.168.43.1',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Connect to Worker address',
                onPressed: _snapshot.active ? _connectManually : null,
                style: IconButton.styleFrom(
                  backgroundColor: _yellow,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkloadSelector() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('DISTRIBUTED WORKLOADS', Icons.account_tree_rounded),
          const SizedBox(height: 8),
          const Text(
            'Choose a workload.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final workload in distributedWorkloads)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoiceChip(
                selected: _selectedWorkload == workload.id,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _selectedWorkload = workload.id),
                label: Text(
                  '${workload.title}${workload.availability == WorkloadAvailability.planned ? ' · PLANNED' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
                avatar: Icon(
                  workload.id == 'mathematics'
                      ? Icons.functions
                      : workload.id == 'inventory'
                      ? Icons.inventory_2_outlined
                      : Icons.model_training_outlined,
                  size: 17,
                ),
              ),
            ),
          if (_selectedWorkload != 'model-training')
            Text(
              distributedWorkloads
                  .firstWhere((workload) => workload.id == _selectedWorkload)
                  .summary,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildMathPanel() {
    final result = _snapshot.swarmMathResult ?? _lastMathResult;
    final baseline = _snapshot.singleMathResult;
    final same =
        result != null &&
        baseline != null &&
        result.hasSameCorrectnessAs(baseline);
    final speedup =
        result != null &&
            baseline != null &&
            same &&
            result.isSwarm &&
            result.elapsed.inMicroseconds > 0
        ? baseline.elapsed.inMicroseconds / result.elapsed.inMicroseconds
        : null;
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('MATHEMATICAL COMPUTING', Icons.functions),
          const SizedBox(height: 8),
          const Text(
            'Choose a problem and run it.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MathProblem>(
            initialValue: _mathProblem,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mathematical problem',
            ),
            items: [
              for (final problem in MathProblem.values)
                DropdownMenuItem(value: problem, child: Text(problem.title)),
            ],
            onChanged: _busy
                ? null
                : (problem) {
                    if (problem != null) setState(() => _mathProblem = problem);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            _mathProblem.description,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (_snapshot.running && _selectedWorkload == 'mathematics') ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _snapshot.totalLabels == 0 ? null : _snapshot.progress,
            ),
            const SizedBox(height: 8),
            Text(
              _snapshot.message,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 14),
            Text(
              _mathSummary(result),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${result.mode} · ${(result.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms · ${result.tasks.length} tasks',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (baseline != null)
              Text(
                'Single-device baseline: ${(baseline.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            if (speedup != null)
              Text(
                'Measured speedup: ${speedup.toStringAsFixed(2)}× (matching mathematical result)',
                style: const TextStyle(color: _yellow, fontSize: 12),
              )
            else if (baseline != null && !same)
              const Text(
                'Baseline mismatch: speedup is suppressed.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Text('Contributions: ${result.contributions}'),
            Text(
              'Job bytes sent/received: ${result.sentBytes} / ${result.receivedBytes} · retries: ${result.retries}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _snapshot.active && !_busy && _snapshot.isLeader
                  ? _runMathWorkload
                  : null,
              icon: const Icon(Icons.functions),
              label: const Text(
                'Run distributed mathematical workload',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedWorkloadPanel() => _panelBox(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'MODEL / LLM TRAINING ADAPTER',
          Icons.model_training_outlined,
        ),
        const SizedBox(height: 10),
        const Text(
          'Training support is planned. The adapter contract is ready for a model, dataset and checkpoint policy.',
          style: TextStyle(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 10),
        const Text(
          'Planned flow: task → result → aggregation → report.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );

  String _mathSummary(MathRunResult result) => switch (result.problem) {
    MathProblem.monteCarloPi =>
      'π ≈ ${(result.summary['pi'] as num).toDouble().toStringAsFixed(6)}',
    MathProblem.linearRegression =>
      'y ≈ ${(result.summary['slope'] as num).toDouble().toStringAsFixed(4)}x + ${(result.summary['intercept'] as num).toDouble().toStringAsFixed(2)}',
    MathProblem.primeFactorization =>
      '${result.summary['factored']} integers factored',
  };

  Widget _buildImageInputPanel() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('INVENTORY SESSION', Icons.photo_library_rounded),
          const SizedBox(height: 12),
          TextField(
            controller: _datasetController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Dataset / session name',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Demo Dataset'),
            subtitle: const Text(
              'Generated or sample images, not real inventory evidence.',
            ),
            value: _isDemoDataset,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _demoDatasetChoice = value;
                    _isDemoDataset = value;
                  }),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose label images for this run.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: Text(
                  _imagePaths.isEmpty
                      ? 'SELECT IMAGES'
                      : '${_imagePaths.length} IMAGES SELECTED',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _yellow,
                  side: const BorderSide(color: _yellow),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickExpectedIds,
                icon: const Icon(Icons.list_alt_rounded, size: 17),
                label: Text(
                  _expectedIds.isEmpty
                      ? 'EXPECTED LIST'
                      : '${_expectedIds.length} EXPECTED IDS',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_expectedIds.isNotEmpty)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _expectedIds = const []),
              child: const Text('Clear expected list'),
            ),
          if (_imagePaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _expectedIds.isEmpty
                  ? 'No expected list selected; missing/unexpected checks are disabled for this run.'
                  : 'Ready to decode ${_imagePaths.length} images and compare against ${_expectedIds.length} expected IDs.',
              style: TextStyle(
                color: _expectedIds.isEmpty ? Colors.orangeAccent : _yellow,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkPanel() {
    final result = _snapshot.result;
    final counts = result == null ? null : _counts(result.results);
    final speedup = _speedup(_snapshot.singleResult, _snapshot.swarmResult);
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('INVENTORY COMPUTE', Icons.inventory_2_rounded),
          const SizedBox(height: 8),
          const Text(
            'Run the inventory workload.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (!_snapshot.running && _snapshot.phase == 'WORKLOAD STOPPED')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _snapshot.message,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
            ),
          if (_snapshot.running || result != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: _snapshot.running ? _snapshot.progress : 1,
                backgroundColor: Colors.black45,
                color: _yellow,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _snapshot.running
                  ? _snapshot.message
                  : (counts == null
                        ? ''
                        : '${counts['valid']} valid · ${counts['duplicate']} duplicate · ${counts['invalid']} invalid · ${counts['unreadable']} unreadable'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            if (result != null && result.expectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Missing expected: ${result.report.missingCount} · Unexpected IDs: ${result.report.unexpectedCount}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            if (speedup != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Measured speedup: ${speedup.toStringAsFixed(2)}x (same dataset and correctness)',
                  style: const TextStyle(
                    color: _yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_snapshot.singleResult != null) ...[
              const SizedBox(height: 12),
              _buildBenchmarkComparison(),
              if (_snapshot.swarmResult != null) ...[
                const SizedBox(height: 16),
                RunInsights(
                  baseline: _snapshot.singleResult!,
                  result: _snapshot.swarmResult!,
                ),
              ],
            ],
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _snapshot.active &&
                      !_busy &&
                      _snapshot.isLeader &&
                      _imagePaths.isNotEmpty
                  ? _runImageWorkload
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'Run image workload',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _snapshot.active && !_busy && _snapshot.isLeader
                  ? _runDemoWorkload
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text(
                'Run text Demo Dataset',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 9),
          if (_role == MeshRole.leader)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _snapshot.active && !_busy && _imagePaths.isNotEmpty
                    ? _runRepeatedBenchmark
                    : null,
                icon: const Icon(Icons.repeat),
                label: Text(
                  _benchmarking
                      ? 'Benchmark ${_benchmarkSessions.length}/3 complete'
                      : 'Run 3-pair image benchmark',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (_benchmarking)
            TextButton(
              onPressed: () => setState(() => _benchmarkCancelled = true),
              child: const Text('Finish current pair, then stop benchmark'),
            ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _snapshot.starting ? null : _toggleMesh,
              style: OutlinedButton.styleFrom(
                foregroundColor: _snapshot.active ? Colors.redAccent : _yellow,
                side: BorderSide(
                  color: _snapshot.active ? Colors.redAccent : _yellow,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text(
                _snapshot.active
                    ? 'STOP MESH'
                    : 'START ${_role.name.toUpperCase()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkComparison() {
    final single = _snapshot.singleResult!;
    final swarm = _snapshot.swarmResult;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MEASURED COMPARISON',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _benchmarkRow(
            'Single device',
            _formatDuration(single.elapsed),
            '${single.throughput.toStringAsFixed(1)} labels/s',
          ),
          if (swarm != null) ...[
            const SizedBox(height: 6),
            _benchmarkRow(
              swarm.isSwarm ? 'Approved swarm' : 'Local fallback',
              _formatDuration(swarm.elapsed),
              '${swarm.throughput.toStringAsFixed(1)} labels/s',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Sent: ${_formatBytes(swarm.sentBytes)}'),
                Text('Received: ${_formatBytes(swarm.receivedBytes)}'),
                Text('Total: ${_formatBytes(swarm.totalBytes)}'),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'Job traffic · binary image frames or JSON/base64, including failed attempts. '
                'Sent bytes are queued; network headers and control traffic are excluded.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            if (!swarm.isSwarm)
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Text(
                  'Approve at least one Worker to measure a real multi-device run.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                ),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'The distributed run will appear here after the Leader finishes.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _benchmarkRow(String label, String duration, String throughput) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          duration,
          style: const TextStyle(
            color: _yellow,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          throughput,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final milliseconds = duration.inMicroseconds / 1000;
    if (milliseconds < 1) return '${duration.inMicroseconds} µs';
    return '${milliseconds.toStringAsFixed(2)} ms';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
  }

  Widget _buildEvents() {
    return _panelBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('EVENT LOG', Icons.receipt_long_rounded),
          const SizedBox(height: 8),
          if (_snapshot.events.isEmpty)
            const Text(
              'Protocol events will appear here.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            )
          else
            for (final event in _snapshot.events.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '› $event',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ),
        ],
      ),
    );
  }

  Widget _panelBox(Widget child) => SizedBox(
    width: double.infinity,
    child: Material(
      color: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );

  Widget _sectionTitle(String text, IconData icon) => Row(
    children: [
      Icon(icon, color: _yellow, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
    ],
  );

  Widget _iconBox(IconData icon, {bool small = false}) => Container(
    width: small ? 36 : 44,
    height: small ? 36 : 44,
    decoration: BoxDecoration(
      color: _yellow.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Icon(icon, color: _yellow, size: small ? 19 : 23),
  );

  Widget _pill(String text, {required bool active}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: active ? _yellow : Colors.white24),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: active ? _yellow : AppColors.muted, size: 7),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: active ? _yellow : AppColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _metric(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    ],
  );

  Map<String, int> _counts(List<InventoryLabelResult> results) {
    final seen = <String>{};
    var valid = 0, duplicate = 0, invalid = 0, unreadable = 0;
    for (final item in results) {
      switch (item.status) {
        case InventoryLabelStatus.valid:
          if (item.normalizedId != null && !seen.add(item.normalizedId!)) {
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

  double? _speedup(MeshRunResult? single, MeshRunResult? swarm) {
    if (single == null ||
        swarm == null ||
        !swarm.isSwarm ||
        swarm.elapsed.inMicroseconds == 0 ||
        !single.hasSameCorrectnessAs(swarm)) {
      return null;
    }
    return single.elapsed.inMicroseconds / swarm.elapsed.inMicroseconds;
  }
}
