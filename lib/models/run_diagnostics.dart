enum RunPhase {
  scheduling('Scheduling'),
  batchPreparation('Batch preparation'),
  queueWait('Device queue wait'),
  telemetry('Local telemetry refresh'),
  imageRead('Image materialization'),
  encodeAndQueue('Encoding / socket enqueue'),
  remoteWait('Remote result wait'),
  localProcessing('Local processing'),
  aggregation('Report aggregation');

  const RunPhase(this.label);
  final String label;
}

class PhaseTiming {
  const PhaseTiming({
    required this.microseconds,
    required this.samples,
    required this.maxMicroseconds,
  });
  final int microseconds, samples, maxMicroseconds;
  double get milliseconds => microseconds / 1000;
  Map<String, int> toJson() => {
    'microseconds': microseconds,
    'samples': samples,
    'maxMicroseconds': maxMicroseconds,
  };

  factory PhaseTiming.fromJson(Map<String, dynamic> json) {
    final total = json['microseconds'],
        count = json['samples'],
        max = json['maxMicroseconds'];
    if (total is! int ||
        count is! int ||
        max is! int ||
        total < 0 ||
        count < 1 ||
        max < 0 ||
        max > total ||
        total > max * count) {
      throw const FormatException('Invalid diagnostic timing');
    }
    return PhaseTiming(
      microseconds: total,
      samples: count,
      maxMicroseconds: max,
    );
  }
}

/// Summed task spans may overlap across nodes. They are NOT wall-time shares,
/// CPU utilization, or isolated network latency. Old reports have no samples.
class RunDiagnostics {
  const RunDiagnostics([this.phases = const {}]);
  final Map<RunPhase, PhaseTiming> phases;
  static const measurementNote =
      'Phase totals sum measured task spans and can overlap across nodes. '
      'They are not additive wall time. Remote result wait includes transport, Worker telemetry, '
      'queueing, decoding and reply handling; it is not network latency. '
      'Pre-run telemetry, input selection, history and export are outside these spans.';

  Map<String, dynamic> toJson() => {
    for (final entry in phases.entries) entry.key.name: entry.value.toJson(),
  };

  factory RunDiagnostics.fromJson(Map<String, dynamic> json) => RunDiagnostics(
    Map.unmodifiable({
      for (final phase in RunPhase.values)
        if (json.containsKey(phase.name))
          phase: PhaseTiming.fromJson(
            Map<String, dynamic>.from(json[phase.name] as Map),
          ),
    }),
  );
}

class RunProfiler {
  final _phases = <RunPhase, PhaseTiming>{};

  void record(RunPhase phase, Duration elapsed) {
    final value = elapsed.inMicroseconds;
    final previous = _phases[phase];
    _phases[phase] = PhaseTiming(
      microseconds: (previous?.microseconds ?? 0) + value,
      samples: (previous?.samples ?? 0) + 1,
      maxMicroseconds: previous == null || value > previous.maxMicroseconds
          ? value
          : previous.maxMicroseconds,
    );
  }

  Future<T> measure<T>(RunPhase phase, Future<T> Function() operation) async {
    final watch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      watch.stop();
      record(phase, watch.elapsed);
    }
  }

  RunDiagnostics snapshot() => RunDiagnostics(Map.unmodifiable(_phases));
}
