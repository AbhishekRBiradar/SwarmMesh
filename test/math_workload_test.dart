import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/math_workload.dart';

void main() {
  test(
    'Monte Carlo tasks aggregate deterministically independent of order',
    () {
      final tasks = MathWorkloadEngine.createTasks(MathProblem.monteCarloPi);
      final forward = MathWorkloadEngine.aggregate(
        MathProblem.monteCarloPi,
        MathWorkloadEngine.process(MathProblem.monteCarloPi, tasks),
      );
      final reverse = MathWorkloadEngine.aggregate(
        MathProblem.monteCarloPi,
        MathWorkloadEngine.process(MathProblem.monteCarloPi, tasks.reversed),
      );

      expect(forward, reverse);
      expect(forward['samples'], 360000);
      expect((forward['pi'] as num).toDouble(), closeTo(3.14, .02));
    },
  );

  test('linear regression combines partial sufficient statistics', () {
    final tasks = MathWorkloadEngine.createTasks(MathProblem.linearRegression);
    final result = MathWorkloadEngine.aggregate(
      MathProblem.linearRegression,
      MathWorkloadEngine.process(MathProblem.linearRegression, tasks),
    );

    expect(result['count'], 18000);
    expect((result['slope'] as num).toDouble(), closeTo(2.75, .001));
    expect((result['intercept'] as num).toDouble(), closeTo(18, .1));
  });

  test('factorization covers every independent task and wire round-trips', () {
    final tasks = MathWorkloadEngine.createTasks(
      MathProblem.primeFactorization,
    );
    final encoded = tasks.map((task) => task.toJson()).toList();
    final decoded = [
      for (final item in encoded)
        MathTask.fromJson(Map<String, dynamic>.from(item)),
    ];
    final results = MathWorkloadEngine.process(
      MathProblem.primeFactorization,
      decoded,
    );
    final summary = MathWorkloadEngine.aggregate(
      MathProblem.primeFactorization,
      results,
    );

    expect(results, hasLength(12));
    expect(summary['factored'], 144);
    for (final item in summary['numbers'] as List) {
      final number = item['number'] as int;
      final factors = List<int>.from(item['factors'] as List);
      expect(
        factors.fold<int>(1, (product, factor) => product * factor),
        number,
      );
    }
  });
}
