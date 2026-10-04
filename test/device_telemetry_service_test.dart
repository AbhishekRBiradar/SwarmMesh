import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/node_telemetry.dart';
import 'package:swarm_mesh/services/device_telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('swarm_mesh/device_telemetry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = DeviceTelemetryService();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads Android thermal status through the native channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getThermalStatus');
      return 3;
    });
    expect(await service.collectThermalState(), ThermalState.severe);
  });

  test('unsupported or failed thermal readings remain unknown', () async {
    for (final value in [null, -1, 7]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      expect(await service.collectThermalState(), ThermalState.unknown);
    }
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'THERMAL_UNAVAILABLE'),
    );
    expect(await service.collectThermalState(), ThermalState.unknown);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await service.collectThermalState(), ThermalState.unknown);
  });

  test('resource reads overlap and each collection refreshes battery and thermal policy', () async {
    const battery = MethodChannel('dev.fluttercommunity.plus/battery');
    final batteryGate = Completer<int>();
    final thermalStarted = Completer<void>();
    var first = true;
    var chargingReads = 0;
    var thermalReads = 0;
    messenger.setMockMethodCallHandler(battery, (call) async {
      if (call.method == 'getBatteryLevel') {
        return first ? batteryGate.future : 8;
      }
      if (call.method == 'getBatteryState') {
        chargingReads++;
        return 'discharging';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (_) async {
      thermalReads++;
      if (!thermalStarted.isCompleted) thermalStarted.complete();
      return first ? 0 : 3;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(battery, null));
    final freshService = DeviceTelemetryService();
    final pending = freshService.collectTelemetry(nodeId: 'DEVICE');
    try {
      // A blocked battery call must not prevent independent thermal collection.
      await thermalStarted.future.timeout(const Duration(seconds: 2));
      expect(chargingReads, 1);
    } finally {
      batteryGate.complete(90);
    }
    final initial = await pending;
    expect(initial.batteryLevel, 90);
    expect(initial.computePauseReason, isNull);
    first = false;
    final updated = await freshService.collectTelemetry(nodeId: 'DEVICE');
    expect(updated.batteryLevel, 8);
    expect(updated.thermalState, ThermalState.severe);
    expect(updated.computePauseReason, isNotNull);
    expect(chargingReads, 2);
    expect(thermalReads, 2);
  });
}
