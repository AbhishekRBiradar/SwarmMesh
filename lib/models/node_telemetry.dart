/// Android PowerManager thermal status (API 29+). Unknown is not "normal".
enum ThermalState {
  unknown,
  none,
  light,
  moderate,
  severe,
  critical,
  emergency,
  shutdown;

  static ThermalState fromAndroidStatus(int? status) =>
      status != null && status >= 0 && status <= 6
      ? values[status + 1]
      : unknown;

  static ThermalState fromName(Object? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => unknown);

  String get label => this == unknown ? 'Unavailable' : name.toUpperCase();
  bool get pausesCompute => index >= severe.index;
}

class NodeTelemetry {
  final String nodeId;
  final String deviceModel;
  final int batteryLevel;
  final int cpuCores;
  final double computeWeight;
  final bool isLeader;
  final String status;
  final DateTime timestamp;
  final bool batteryLevelKnown;
  final bool? isCharging;
  final ThermalState thermalState;

  const NodeTelemetry({
    required this.nodeId,
    required this.deviceModel,
    required this.batteryLevel,
    required this.cpuCores,
    required this.computeWeight,
    required this.isLeader,
    required this.status,
    required this.timestamp,
    this.batteryLevelKnown = true,
    this.isCharging,
    this.thermalState = ThermalState.unknown,
  });

  /// Creates telemetry from a JSON payload received over WebSocket.
  factory NodeTelemetry.fromJson(Map<String, dynamic> json) {
    return NodeTelemetry(
      nodeId: json['nodeId'] as String? ?? 'unknown',
      deviceModel: json['deviceModel'] as String? ?? 'Unknown Device',
      batteryLevel: _toInt(json['batteryLevel'], fallback: 0).clamp(0, 100),
      batteryLevelKnown:
          json['batteryLevelKnown'] != false &&
          _toInt(json['batteryLevel'], fallback: -1) >= 0 &&
          _toInt(json['batteryLevel'], fallback: -1) <= 100,
      isCharging: json['isCharging'] is bool
          ? json['isCharging'] as bool
          : null,
      thermalState: ThermalState.fromName(json['thermalState']),
      cpuCores: _toInt(json['cpuCores'], fallback: 1).clamp(1, 32),
      computeWeight: _toDouble(json['computeWeight'], fallback: 1.0),
      isLeader: json['isLeader'] as bool? ?? false,
      status: json['status'] as String? ?? 'UNKNOWN',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Converts this telemetry object into a JSON-safe payload.
  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'deviceModel': deviceModel,
      'batteryLevel': batteryLevel,
      'cpuCores': cpuCores,
      'computeWeight': computeWeight,
      'isLeader': isLeader,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'batteryLevelKnown': batteryLevelKnown,
      'isCharging': isCharging,
      'thermalState': thermalState.name,
    };
  }

  /// Creates a copy while changing only the fields supplied.
  NodeTelemetry copyWith({
    String? nodeId,
    String? deviceModel,
    int? batteryLevel,
    int? cpuCores,
    double? computeWeight,
    bool? isLeader,
    String? status,
    DateTime? timestamp,
    bool? batteryLevelKnown,
    bool? isCharging,
    ThermalState? thermalState,
  }) {
    return NodeTelemetry(
      nodeId: nodeId ?? this.nodeId,
      deviceModel: deviceModel ?? this.deviceModel,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      cpuCores: cpuCores ?? this.cpuCores,
      computeWeight: computeWeight ?? this.computeWeight,
      isLeader: isLeader ?? this.isLeader,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      batteryLevelKnown: batteryLevelKnown ?? this.batteryLevelKnown,
      isCharging: isCharging ?? this.isCharging,
      thermalState: thermalState ?? this.thermalState,
    );
  }

  String? get computePauseReason {
    if (accessBlockReason != null) return accessBlockReason;
    if (thermalState.pausesCompute) {
      return 'Thermal state: ${thermalState.label}';
    }
    if (batteryLevelKnown && batteryLevel <= 10 && isCharging != true) {
      return 'Battery at or below 10%; connect power';
    }
    return null;
  }

  /// The app remains inaccessible until the battery reaches 20 percent.
  String? get accessBlockReason => batteryLevelKnown && batteryLevel < 20
      ? 'Battery below 20%; connect power before using SwarmMesh'
      : null;

  /// Headroom policy applied to both measured and initial scheduling weights.
  double get schedulingHeadroom => _headroom(
    batteryLevel: batteryLevel,
    batteryLevelKnown: batteryLevelKnown,
    isCharging: isCharging,
    thermalState: thermalState,
  );

  /// Initial estimate only; task measurements supersede it in the scheduler.
  static double calculateWeight({
    required int cpuCores,
    required int batteryLevel,
    String? deviceModel,
    bool batteryLevelKnown = true,
    bool? isCharging,
    ThermalState thermalState = ThermalState.unknown,
  }) {
    final safeCores = cpuCores.clamp(1, 32);
    return safeCores *
        _headroom(
          batteryLevel: batteryLevel,
          batteryLevelKnown: batteryLevelKnown,
          isCharging: isCharging,
          thermalState: thermalState,
        );
  }

  static double _headroom({
    required int batteryLevel,
    required bool batteryLevelKnown,
    required bool? isCharging,
    required ThermalState thermalState,
  }) {
    if (thermalState.pausesCompute ||
        (batteryLevelKnown && batteryLevel < 20)) {
      return 0;
    }
    final batteryFactor = !batteryLevelKnown
        ? 0.75
        : isCharging == true
        ? 1.0
        : batteryLevel < 20
        ? 0.5
        : batteryLevel < 40
        ? 0.75
        : 1.0;
    final thermalFactor = thermalState == ThermalState.moderate
        ? 0.5
        : thermalState == ThermalState.light
        ? 0.8
        : 1.0;
    return batteryFactor * thermalFactor;
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();

    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static double _toDouble(dynamic value, {required double fallback}) {
    final parsed = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value)
        : null;
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : fallback;
  }

  @override
  String toString() {
    return 'NodeTelemetry('
        'nodeId: $nodeId, '
        'deviceModel: $deviceModel, '
        'batteryLevel: $batteryLevel%, '
        'cpuCores: $cpuCores, '
        'computeWeight: $computeWeight, '
        'isLeader: $isLeader, '
        'status: $status'
        ')';
  }
}
