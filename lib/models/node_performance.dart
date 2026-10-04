import 'dart:math' as math;

import 'node_telemetry.dart';

enum WorkloadKind { images, labels, mathematics }

/// Last eight successful batches, normalized by item count. Image decoding and
/// text validation have separate windows; unknown/zero timings are not samples.
class TaskTiming {
  const TaskTiming() : _samples = const [];
  TaskTiming._(Iterable<_TaskSample> samples)
    : _samples = List.unmodifiable(samples);

  final List<_TaskSample> _samples;
  int get sampleCount => _samples.length;
  double? get lastMilliseconds => _samples.lastOrNull?.milliseconds;
  int? get lastItemCount => _samples.lastOrNull?.itemCount;
  double? get averageMillisecondsPerItem => _samples.isEmpty
      ? null
      : _samples.fold<double>(0, (sum, sample) => sum + sample.milliseconds) /
            _samples.fold<int>(0, (sum, sample) => sum + sample.itemCount);

  bool isFresh(DateTime now) =>
      _samples.isNotEmpty &&
      now.difference(_samples.last.at) <= const Duration(minutes: 5);

  TaskTiming record(Duration elapsed, int itemCount, DateTime at) {
    if (elapsed.inMicroseconds <= 0 || itemCount <= 0) return this;
    final samples = [
      if (isFresh(at)) ..._samples,
      _TaskSample(elapsed.inMicroseconds / 1000, itemCount, at),
    ];
    return TaskTiming._(samples.skip(math.max(0, samples.length - 8)));
  }
}

class _TaskSample {
  const _TaskSample(this.milliseconds, this.itemCount, this.at);
  final double milliseconds;
  final int itemCount;
  final DateTime at;
}

/// Measurements made by this runtime, not advertised device specifications.
class NodePerformance {
  const NodePerformance({
    this.images = const TaskTiming(),
    this.labels = const TaskTiming(),
    this.mathematics = const TaskTiming(),
    this.roundTripMilliseconds,
    this.roundTripMeasuredAt,
  });

  final TaskTiming images;
  final TaskTiming labels;
  final TaskTiming mathematics;

  /// Exponentially smoothed application heartbeat RTT (25% latest sample).
  final double? roundTripMilliseconds;
  final DateTime? roundTripMeasuredAt;

  TaskTiming timing(WorkloadKind kind) => switch (kind) {
    WorkloadKind.images => images,
    WorkloadKind.labels => labels,
    WorkloadKind.mathematics => mathematics,
  };

  double? freshRoundTrip(DateTime now) =>
      roundTripMeasuredAt != null &&
          now.difference(roundTripMeasuredAt!) <= const Duration(seconds: 24)
      ? roundTripMilliseconds
      : null;

  NodePerformance recordRoundTrip(Duration elapsed, DateTime at) {
    if (elapsed.inMicroseconds <= 0) return this;
    final previous = freshRoundTrip(at);
    final milliseconds = elapsed.inMicroseconds / 1000;
    return NodePerformance(
      images: images,
      labels: labels,
      mathematics: mathematics,
      roundTripMilliseconds: previous == null
          ? milliseconds
          : previous * .75 + milliseconds * .25,
      roundTripMeasuredAt: at,
    );
  }

  NodePerformance recordTask(
    WorkloadKind kind,
    Duration elapsed,
    int itemCount,
    DateTime at,
  ) => NodePerformance(
    images: kind == WorkloadKind.images
        ? images.record(elapsed, itemCount, at)
        : images,
    labels: kind == WorkloadKind.labels
        ? labels.record(elapsed, itemCount, at)
        : labels,
    mathematics: kind == WorkloadKind.mathematics
        ? mathematics.record(elapsed, itemCount, at)
        : mathematics,
    roundTripMilliseconds: roundTripMilliseconds,
    roundTripMeasuredAt: roundTripMeasuredAt,
  );
}

/// Relative predicted throughput, not a benchmark score. With no sample for a
/// node, infer its cost from the Leader baseline and logical-core ratio. Until
/// that baseline exists, use the initial core estimate. RTT is amortized across
/// a batch; transfer bandwidth and image complexity are not modeled yet.
double schedulingWeight({
  required NodeTelemetry telemetry,
  required TaskTiming timing,
  required TaskTiming referenceTiming,
  required int referenceCores,
  required DateTime now,
  double? roundTripMilliseconds,
  int batchSize = 4,
}) {
  final headroom = telemetry.schedulingHeadroom;
  if (headroom == 0) return 0;
  final cores = telemetry.cpuCores.clamp(1, 32);
  final measured = timing.isFresh(now)
      ? timing.averageMillisecondsPerItem
      : null;
  final reference = referenceTiming.isFresh(now)
      ? referenceTiming.averageMillisecondsPerItem
      : null;
  final cost =
      measured ??
      (reference == null
          ? null
          : reference * referenceCores.clamp(1, 32) / cores);
  final rtt =
      roundTripMilliseconds != null &&
          roundTripMilliseconds.isFinite &&
          roundTripMilliseconds >= 0
      ? roundTripMilliseconds
      : 0.0;
  if (cost == null) return cores * headroom / (1 + rtt / 250);
  return headroom *
      1000 /
      (math.max(.001, cost) + rtt / math.max(1, batchSize));
}
