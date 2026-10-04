import 'dart:convert';
import 'dart:math';

enum MathProblem {
  monteCarloPi(
    'monte-carlo-pi',
    'Monte Carlo π',
    'Estimate π by distributing independent random samples across devices.',
  ),
  linearRegression(
    'linear-regression',
    'Linear regression',
    'Fit a straight line to a synthetic sensor-calibration dataset.',
  ),
  primeFactorization(
    'prime-factorization',
    'Prime factorization',
    'Factor independent integers, a small model of cryptographic workloads.',
  );

  const MathProblem(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;

  static MathProblem fromId(String id) => values.firstWhere(
    (problem) => problem.id == id,
    orElse: () => throw FormatException('Unknown mathematical problem: $id'),
  );
}

class MathTask {
  const MathTask({
    required this.taskId,
    required this.start,
    required this.count,
  });
  final String taskId;
  final int start;
  final int count;

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'start': start,
    'count': count,
  };

  factory MathTask.fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'];
    final start = json['start'];
    final count = json['count'];
    if (taskId is! String ||
        start is! int ||
        count is! int ||
        taskId.isEmpty ||
        start < 0 ||
        count < 1) {
      throw const FormatException('Invalid mathematical task');
    }
    return MathTask(taskId: taskId, start: start, count: count);
  }
}

class MathTaskResult {
  const MathTaskResult({required this.taskId, required this.values});
  final String taskId;
  final Map<String, dynamic> values;

  Map<String, dynamic> toJson() => {'taskId': taskId, 'values': values};

  factory MathTaskResult.fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'];
    final values = json['values'];
    if (taskId is! String || values is! Map) {
      throw const FormatException('Invalid mathematical task result');
    }
    return MathTaskResult(
      taskId: taskId,
      values: Map<String, dynamic>.from(values),
    );
  }
}

class MathRunResult {
  const MathRunResult({
    required this.mode,
    required this.problem,
    required this.tasks,
    required this.results,
    required this.summary,
    required this.elapsed,
    required this.contributions,
    required this.retries,
    required this.sentBytes,
    required this.receivedBytes,
  });

  final String mode;
  final MathProblem problem;
  final List<MathTask> tasks;
  final List<MathTaskResult> results;
  final Map<String, dynamic> summary;
  final Duration elapsed;
  final Map<String, int> contributions;
  final int retries;
  final int sentBytes;
  final int receivedBytes;

  bool get isSwarm => mode == 'math-swarm';
  int get totalBytes => sentBytes + receivedBytes;
  double get throughput => elapsed.inMicroseconds == 0
      ? 0
      : tasks.length * 1000000 / elapsed.inMicroseconds;

  bool hasSameCorrectnessAs(MathRunResult other) =>
      problem == other.problem &&
      tasks.length == other.tasks.length &&
      _canonical(summary) == _canonical(other.summary) &&
      _canonical(results.map((result) => result.toJson()).toList()) ==
          _canonical(other.results.map((result) => result.toJson()).toList());

  static String _canonical(Object? value) => jsonEncode(value);

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'problem': problem.id,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'results': results.map((result) => result.toJson()).toList(),
    'summary': summary,
    'elapsedMicroseconds': elapsed.inMicroseconds,
    'contributions': contributions,
    'retries': retries,
    'sentBytes': sentBytes,
    'receivedBytes': receivedBytes,
  };

  factory MathRunResult.fromJson(Map<String, dynamic> json) {
    final elapsed = json['elapsedMicroseconds'];
    final retries = json['retries'];
    final sentBytes = json['sentBytes'];
    final receivedBytes = json['receivedBytes'];
    final rawTasks = json['tasks'];
    final rawResults = json['results'];
    final rawSummary = json['summary'];
    final rawContributions = json['contributions'];
    if (json['mode'] is! String ||
        json['problem'] is! String ||
        elapsed is! int ||
        elapsed < 0 ||
        retries is! int ||
        retries < 0 ||
        sentBytes is! int ||
        sentBytes < 0 ||
        receivedBytes is! int ||
        receivedBytes < 0 ||
        rawTasks is! List ||
        rawResults is! List ||
        rawSummary is! Map ||
        rawContributions is! Map) {
      throw const FormatException('Invalid saved mathematical run');
    }
    final tasks = [
      for (final item in rawTasks)
        MathTask.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    final results = [
      for (final item in rawResults)
        MathTaskResult.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    final contributions = Map<String, int>.from(rawContributions);
    if (tasks.length != results.length ||
        contributions.values.any((value) => value < 0) ||
        contributions.values.fold<int>(0, (sum, value) => sum + value) !=
            tasks.length) {
      throw const FormatException('Incomplete saved mathematical run');
    }
    return MathRunResult(
      mode: json['mode'] as String,
      problem: MathProblem.fromId(json['problem'] as String),
      tasks: List.unmodifiable(tasks),
      results: List.unmodifiable(results),
      summary: Map<String, dynamic>.unmodifiable(rawSummary),
      elapsed: Duration(microseconds: elapsed),
      contributions: Map.unmodifiable(contributions),
      retries: retries,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
    );
  }
}

class MathSession {
  const MathSession({
    required this.id,
    required this.createdAt,
    required this.baseline,
    required this.result,
  });

  final String id;
  final DateTime createdAt;
  final MathRunResult baseline;
  final MathRunResult result;

  MathProblem get problem => result.problem;
  bool get correctnessMatch => baseline.hasSameCorrectnessAs(result);
  double? get speedup =>
      correctnessMatch && result.isSwarm && result.elapsed.inMicroseconds > 0
      ? baseline.elapsed.inMicroseconds / result.elapsed.inMicroseconds
      : null;

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  factory MathSession.capture(MathRunResult baseline, MathRunResult result) =>
      MathSession(
        id: newId(),
        createdAt: DateTime.now().toUtc(),
        baseline: baseline,
        result: result,
      );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'baseline': baseline.toJson(),
    'result': result.toJson(),
    'correctnessMatch': correctnessMatch,
    'speedup': speedup,
  };

  factory MathSession.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (json['schemaVersion'] != 1 ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Unsupported or invalid math session');
    }
    final baseline = MathRunResult.fromJson(
      Map<String, dynamic>.from(json['baseline'] as Map),
    );
    final result = MathRunResult.fromJson(
      Map<String, dynamic>.from(json['result'] as Map),
    );
    if (baseline.problem != result.problem ||
        baseline.tasks.length != result.tasks.length) {
      throw const FormatException('Mismatched mathematical session runs');
    }
    return MathSession(
      id: id,
      createdAt: DateTime.parse(json['createdAt'] as String),
      baseline: baseline,
      result: result,
    );
  }
}

class MathWorkloadEngine {
  static const defaultTaskCount = 12;

  static List<MathTask> createTasks(
    MathProblem problem, {
    int taskCount = defaultTaskCount,
  }) {
    if (taskCount < 1) throw ArgumentError.value(taskCount, 'taskCount');
    return [
      for (var index = 0; index < taskCount; index++)
        MathTask(
          taskId: 'MATH-${index + 1}',
          start: index,
          count: switch (problem) {
            MathProblem.monteCarloPi => 30000,
            MathProblem.linearRegression => 1500,
            MathProblem.primeFactorization => 12,
          },
        ),
    ];
  }

  static List<MathTaskResult> process(
    MathProblem problem,
    Iterable<MathTask> tasks,
  ) => [for (final task in tasks) _processTask(problem, task)];

  static Map<String, dynamic> aggregate(
    MathProblem problem,
    Iterable<MathTaskResult> results,
  ) {
    final items = results.toList()
      ..sort((a, b) => a.taskId.compareTo(b.taskId));
    return switch (problem) {
      MathProblem.monteCarloPi => _aggregatePi(items),
      MathProblem.linearRegression => _aggregateRegression(items),
      MathProblem.primeFactorization => _aggregateFactors(items),
    };
  }

  static MathTaskResult _processTask(MathProblem problem, MathTask task) =>
      switch (problem) {
        MathProblem.monteCarloPi => _piTask(task),
        MathProblem.linearRegression => _regressionTask(task),
        MathProblem.primeFactorization => _factorTask(task),
      };

  static MathTaskResult _piTask(MathTask task) {
    var state = 0x9E3779B9 ^ (task.start * 0x45D9F3B);
    var inside = 0;
    for (var index = 0; index < task.count; index++) {
      state = _next(state);
      final x = (state & 0xFFFF) / 65536.0;
      state = _next(state);
      final y = (state & 0xFFFF) / 65536.0;
      if (x * x + y * y <= 1) inside++;
    }
    return MathTaskResult(
      taskId: task.taskId,
      values: {'samples': task.count, 'inside': inside},
    );
  }

  static int _next(int state) => (state * 1664525 + 1013904223) & 0x7FFFFFFF;

  static Map<String, dynamic> _aggregatePi(List<MathTaskResult> results) {
    final samples = results.fold<int>(
      0,
      (sum, result) => sum + result.values['samples'] as int,
    );
    final inside = results.fold<int>(
      0,
      (sum, result) => sum + result.values['inside'] as int,
    );
    return {
      'samples': samples,
      'inside': inside,
      'pi': samples == 0 ? 0.0 : 4 * inside / samples,
    };
  }

  static MathTaskResult _regressionTask(MathTask task) {
    var sumX = 0.0;
    var sumY = 0.0;
    var sumXX = 0.0;
    var sumXY = 0.0;
    for (var offset = 0; offset < task.count; offset++) {
      final x = (task.start * 1500 + offset).toDouble();
      final noise = ((offset * 17 + task.start * 11) % 21 - 10) / 10;
      final y = 2.75 * x + 18 + noise;
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
    }
    return MathTaskResult(
      taskId: task.taskId,
      values: {
        'count': task.count,
        'sumX': sumX,
        'sumY': sumY,
        'sumXX': sumXX,
        'sumXY': sumXY,
      },
    );
  }

  static Map<String, dynamic> _aggregateRegression(
    List<MathTaskResult> results,
  ) {
    final count = results.fold<int>(
      0,
      (sum, result) => sum + result.values['count'] as int,
    );
    final sumX = _sum(results, 'sumX');
    final sumY = _sum(results, 'sumY');
    final sumXX = _sum(results, 'sumXX');
    final sumXY = _sum(results, 'sumXY');
    final denominator = count * sumXX - sumX * sumX;
    final slope = denominator == 0
        ? 0.0
        : (count * sumXY - sumX * sumY) / denominator;
    final intercept = count == 0 ? 0.0 : (sumY - slope * sumX) / count;
    return {'count': count, 'slope': slope, 'intercept': intercept};
  }

  static double _sum(List<MathTaskResult> results, String key) => results.fold(
    0.0,
    (sum, result) => sum + (result.values[key] as num).toDouble(),
  );

  static MathTaskResult _factorTask(MathTask task) {
    final numbers = <Map<String, dynamic>>[];
    for (var offset = 0; offset < task.count; offset++) {
      var value = 1000003 + (task.start * task.count + offset) * 1009;
      final original = value;
      final factors = <int>[];
      for (var divisor = 2; divisor * divisor <= value; divisor++) {
        while (value % divisor == 0) {
          factors.add(divisor);
          value ~/= divisor;
        }
      }
      if (value > 1) factors.add(value);
      numbers.add({'number': original, 'factors': factors});
    }
    return MathTaskResult(taskId: task.taskId, values: {'numbers': numbers});
  }

  static Map<String, dynamic> _aggregateFactors(List<MathTaskResult> results) {
    final numbers = [
      for (final result in results)
        ...(result.values['numbers'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
    ];
    return {
      'numbers': numbers,
      'factored': numbers.length,
      'checksum': numbers.fold<int>(
        0,
        (sum, item) => sum + (item['number'] as int),
      ),
    };
  }
}
