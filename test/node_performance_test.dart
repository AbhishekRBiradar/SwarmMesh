import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/node_performance.dart';
import 'package:swarm_mesh/models/node_telemetry.dart';

void main() {
  final now = DateTime(2026, 10, 3);
  NodeTelemetry telemetry({
    int cores = 4,
    int battery = 100,
    bool? charging,
    ThermalState thermal = ThermalState.none,
    bool batteryKnown = true,
  }) => NodeTelemetry(
    nodeId: 'node',
    deviceModel: 'Test',
    batteryLevel: battery,
    batteryLevelKnown: batteryKnown,
    isCharging: charging,
    thermalState: thermal,
    cpuCores: cores,
    computeWeight: cores.toDouble(),
    isLeader: false,
    status: 'READY',
    timestamp: now,
  );

  TaskTiming timing(int milliseconds, int items) => const TaskTiming().record(
    Duration(milliseconds: milliseconds),
    items,
    now,
  );

  test('thermal mapping and optional telemetry preserve unknown states', () {
    expect(ThermalState.fromAndroidStatus(null), ThermalState.unknown);
    expect(ThermalState.fromAndroidStatus(-1), ThermalState.unknown);
    expect(ThermalState.fromAndroidStatus(7), ThermalState.unknown);
    for (var status = 0; status <= 6; status++) {
      expect(
        ThermalState.fromAndroidStatus(status),
        ThermalState.values[status + 1],
      );
    }
    final source = telemetry(charging: true, thermal: ThermalState.moderate);
    final roundTrip = NodeTelemetry.fromJson(source.toJson());
    expect(roundTrip.thermalState, ThermalState.moderate);
    expect(roundTrip.isCharging, isTrue);
    final legacy = source.toJson()
      ..remove('thermalState')
      ..remove('isCharging');
    expect(NodeTelemetry.fromJson(legacy).thermalState, ThermalState.unknown);
    expect(NodeTelemetry.fromJson(legacy).isCharging, isNull);
    final bad = NodeTelemetry.fromJson({
      ...legacy,
      'cpuCores': 0,
      'computeWeight': 'NaN',
      'batteryLevel': -1,
      'thermalState': 'future-value',
    });
    expect(bad.batteryLevelKnown, isFalse);
    expect(bad.cpuCores, 1);
    expect(bad.computeWeight.isFinite, isTrue);
    expect(bad.thermalState, ThermalState.unknown);
  });

  test('rolling timing normalizes by items and retains only eight batches', () {
    var samples = timing(
      100,
      10,
    ).record(const Duration(milliseconds: 40), 2, now);
    expect(samples.lastMilliseconds, 40);
    expect(samples.lastItemCount, 2);
    expect(samples.averageMillisecondsPerItem, closeTo(140 / 12, .0001));
    for (var i = 0; i < 8; i++) {
      samples = samples.record(const Duration(milliseconds: 9), 3, now);
    }
    expect(samples.sampleCount, 8);
    expect(samples.averageMillisecondsPerItem, 3);
    expect(samples.record(Duration.zero, 1, now).sampleCount, 8);
    expect(
      samples.record(const Duration(milliseconds: 1), 0, now).sampleCount,
      8,
    );
    final later = now.add(const Duration(minutes: 6));
    expect(samples.isFresh(later), isFalse);
    expect(
      samples.record(const Duration(milliseconds: 5), 1, later).sampleCount,
      1,
    );
  });

  test('image/text samples are separate and RTT expires', () {
    final measured = const NodePerformance()
        .recordTask(
          WorkloadKind.labels,
          const Duration(milliseconds: 1),
          900,
          now,
        )
        .recordRoundTrip(const Duration(milliseconds: 20), now)
        .recordRoundTrip(const Duration(milliseconds: 40), now);
    expect(measured.images.averageMillisecondsPerItem, isNull);
    expect(measured.labels.sampleCount, 1);
    expect(measured.freshRoundTrip(now), 25);
    expect(
      measured.freshRoundTrip(now.add(const Duration(seconds: 25))),
      isNull,
    );
  });

  test('measured cost overrides core count; RTT reduces remote allocation', () {
    double weight(NodeTelemetry node, TaskTiming sample, {double? rtt}) =>
        schedulingWeight(
          telemetry: node,
          timing: sample,
          referenceTiming: timing(100, 10),
          referenceCores: 4,
          now: now,
          roundTripMilliseconds: rtt,
        );
    final fast = weight(telemetry(cores: 2), timing(20, 10));
    final slow = weight(telemetry(cores: 16), timing(100, 10));
    expect(fast, greaterThan(slow));
    expect(
      weight(telemetry(cores: 2), timing(20, 10), rtt: 200),
      lessThan(fast),
    );
    expect(weight(telemetry(cores: 4), const TaskTiming()), 100);
    expect(weight(telemetry(cores: 8), const TaskTiming()), 200);
  });

  test(
    'battery, charging and thermal rules apply even to fast measured nodes',
    () {
      double weight(NodeTelemetry node) => schedulingWeight(
        telemetry: node,
        timing: timing(10, 10),
        referenceTiming: timing(10, 10),
        referenceCores: 4,
        now: now,
      );
      final normal = weight(telemetry());
      expect(weight(telemetry(battery: 10)), 0);
      expect(weight(telemetry(battery: 10, charging: true)), 0);
      expect(weight(telemetry(battery: 15)), 0);
      expect(telemetry(battery: 19).accessBlockReason, isNotNull);
      expect(telemetry(battery: 20).accessBlockReason, isNull);
      expect(weight(telemetry(battery: 30)), normal * .75);
      expect(weight(telemetry(battery: 0, batteryKnown: false)), normal * .75);
      expect(weight(telemetry(thermal: ThermalState.light)), normal * .8);
      expect(weight(telemetry(thermal: ThermalState.moderate)), normal * .5);
      for (final state in [
        ThermalState.severe,
        ThermalState.critical,
        ThermalState.emergency,
        ThermalState.shutdown,
      ]) {
        expect(weight(telemetry(charging: true, thermal: state)), 0);
      }
    },
  );
}
