import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../models/node_telemetry.dart';

class DeviceTelemetryService {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const _thermalChannel = MethodChannel('swarm_mesh/device_telemetry');
  // Hardware identity is stable for this service's lifetime. Resource readings
  // below are always fresh; a cached model never bypasses battery/thermal policy.
  Future<String>? _deviceModel;

  Future<String> createNodeId() async {
    final random = Random.secure();
    final suffix = List.generate(
      4,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'NODE-$suffix';
  }

  Future<NodeTelemetry> collectTelemetry({
    required String nodeId,
    bool isLeader = false,
  }) async {
    final (batteryLevel, isCharging, thermalState, deviceModel) = await (
      _getBatteryLevel(),
      _getChargingState(),
      collectThermalState(),
      _deviceModel ??= _getDeviceModel(),
    ).wait;

    // Android does not expose a reliable "available CPU cores for compute"
    // value through Flutter, so the MVP uses the processor count as an estimate.
    final cpuCores = _getCpuCoreEstimate();

    final weight = NodeTelemetry.calculateWeight(
      cpuCores: cpuCores,
      batteryLevel: batteryLevel ?? 0,
      batteryLevelKnown: batteryLevel != null,
      isCharging: isCharging,
      thermalState: thermalState,
      deviceModel: deviceModel,
    );

    return NodeTelemetry(
      nodeId: nodeId,
      deviceModel: deviceModel,
      batteryLevel: batteryLevel ?? 0,
      batteryLevelKnown: batteryLevel != null,
      isCharging: isCharging,
      thermalState: thermalState,
      cpuCores: cpuCores,
      computeWeight: weight,
      isLeader: isLeader,
      status: batteryLevel != null && batteryLevel < 20
          ? 'ACCESS_BLOCKED'
          : thermalState.pausesCompute
          ? 'THERMAL_PAUSE'
          : batteryLevel != null && batteryLevel <= 10 && isCharging != true
          ? 'LOW_BATTERY'
          : 'READY',
      timestamp: DateTime.now(),
    );
  }

  Future<int?> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level >= 0 && level <= 100 ? level : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _getChargingState() async {
    try {
      final state = await _battery.batteryState;
      if (state == BatteryState.charging || state == BatteryState.full) {
        return true;
      }
      if (state == BatteryState.discharging) return false;
    } catch (_) {
      // Missing/unsupported readings remain unknown, not "not charging".
    }
    return null;
  }

  Future<ThermalState> collectThermalState() async {
    try {
      return ThermalState.fromAndroidStatus(
        await _thermalChannel.invokeMethod<int>('getThermalStatus'),
      );
    } on PlatformException {
      return ThermalState.unknown;
    } on MissingPluginException {
      return ThermalState.unknown;
    }
  }

  Future<String> _getDeviceModel() async {
    try {
      final info = await _deviceInfo.androidInfo;

      final manufacturer = info.manufacturer.trim();
      final model = info.model.trim();

      if (manufacturer.isEmpty) {
        return model.isEmpty ? 'Android Device' : model;
      }

      if (model.isEmpty) {
        return manufacturer;
      }

      return '$manufacturer $model';
    } catch (_) {
      return 'Android Device';
    }
  }

  int _getCpuCoreEstimate() {
    // This is the number of logical processors visible to the app, not a
    // benchmark. The scheduler uses it as one input to its first heuristic.
    try {
      return Platform.numberOfProcessors.clamp(1, 32);
    } catch (_) {
      return 1;
    }
  }
}
