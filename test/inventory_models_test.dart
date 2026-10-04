import 'package:flutter_test/flutter_test.dart';

import 'package:swarm_mesh/models/inventory_models.dart';
import 'package:swarm_mesh/models/inventory_report.dart';
import 'package:swarm_mesh/models/work_allocation.dart';

void main() {
  group('InventoryProcessor', () {
    test('preserves raw whitespace for unreadable labels', () {
      const raw = ' \t\n ';
      final result = InventoryProcessor.process([raw]).labels.single;

      expect(result.status, InventoryLabelStatus.unreadable);
      expect(result.normalizedId, isNull);
      expect(result.rawLabel, raw);
    });

    test('keeps canonical IDs strict and invalid values separate', () {
      final results = InventoryProcessor.process([
        ' pkg-000123 ',
        'PKG-123',
        'PKG-１２３４５６',
        'PKG-000124x',
      ]).labels;

      expect(results[0].normalizedId, 'PKG-000123');
      expect(results[0].status, InventoryLabelStatus.valid);
      expect(
        results
            .skip(1)
            .every((label) => label.status == InventoryLabelStatus.invalid),
        isTrue,
      );
    });
  });

  group('strict JSON', () {
    final validLabel = <String, dynamic>{
      'rawLabel': 'PKG-000001',
      'normalizedId': 'PKG-000001',
      'status': 'valid',
      'reason': 'Valid package ID',
    };

    test('rejects malformed status, label entries, and timing', () {
      expect(
        () => InventoryLabelResult.fromJson({...validLabel, 'status': 'wat'}),
        throwsFormatException,
      );
      expect(
        () => InventoryBatchResult.fromJson({
          'labels': [validLabel, 'not an object'],
          'elapsedMilliseconds': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => InventoryBatchResult.fromJson({
          'labels': [validLabel],
          'elapsedMilliseconds': 1.5,
        }),
        throwsFormatException,
      );
      expect(
        () => InventoryBatchResult.fromJson({
          'labels': [validLabel],
          'elapsedMilliseconds': -1,
        }),
        throwsFormatException,
      );
    });

    test('rejects inconsistent status and normalized ID', () {
      expect(
        () => InventoryLabelResult.fromJson({
          ...validLabel,
          'normalizedId': null,
        }),
        throwsFormatException,
      );
    });
  });

  group('InventoryReport', () {
    test('aggregates sample records and exposes expected differences', () {
      final source = sampleInventoryRecordDataset;
      final batch = InventoryProcessor.process(source.labels);
      final report = InventoryReport.aggregate(
        originalLabels: source.labels,
        workerBatches: [batch],
        expectedIds: source.expectedIds,
      );

      expect(report.totalLabels, 10);
      expect(report.uniqueValidCount, 4);
      expect(report.validOccurrenceCount, 6);
      expect(report.duplicateCount, 2);
      expect(report.duplicateOccurrences, 2);
      expect(report.duplicateIds, ['PKG-000001']);
      expect(report.invalidCount, 2);
      expect(report.unreadableCount, 2);
      expect(report.missingExpectedIds, ['PKG-000004']);
      expect(report.unexpectedIds, ['PKG-000099']);
      expect(
        report.toJson()['correctnessFingerprint'],
        report.correctnessFingerprint,
      );
    });

    test('compares single and reordered worker batches deterministically', () {
      final source = sampleInventoryRecordDataset;
      final results = InventoryProcessor.process(source.labels).labels;
      final single = InventoryReport.fromBatches(
        originalLabels: source.labels,
        batches: [
          InventoryBatchResult(labels: results, elapsedMilliseconds: 1),
        ],
        expectedIds: source.expectedIds,
      );
      final swarm = InventoryReport.fromBatches(
        originalLabels: source.labels,
        batches: [
          InventoryBatchResult(
            labels: [
              results[4],
              results[5],
              results[6],
              results[7],
              results[8],
            ],
            elapsedMilliseconds: 99,
          ),
          InventoryBatchResult(
            labels: [
              results[0],
              results[1],
              results[2],
              results[3],
              results[9],
            ],
            elapsedMilliseconds: 2,
          ),
        ],
        expectedIds: source.expectedIds,
      );

      expect(swarm.hasSameCorrectnessAs(single), isTrue);
      expect(swarm.correctnessFingerprint, single.correctnessFingerprint);
    });

    test('requires exact original label occurrence coverage', () {
      final batch = InventoryProcessor.process(['PKG-000001']);
      expect(
        () => InventoryReport.fromBatches(
          originalLabels: ['PKG-000001', 'PKG-000002'],
          batches: [batch],
          expectedIds: const ['PKG-000001'],
        ),
        throwsFormatException,
      );
      expect(
        () => InventoryReport.fromBatches(
          originalLabels: ['PKG-000001'],
          batches: [
            InventoryBatchResult(
              labels: [...batch.labels, batch.labels.single],
              elapsedMilliseconds: 0,
            ),
          ],
          expectedIds: const ['PKG-000001'],
        ),
        throwsFormatException,
      );
    });
  });

  group('partitionByResourceWeight', () {
    test('covers every input exactly once in stable order', () {
      final allocations = partitionByResourceWeight<int, String>(
        items: List<int>.generate(10, (index) => index),
        resources: const [
          WorkResource(resource: 'slow', weight: 1),
          WorkResource(resource: 'fast', weight: 3),
        ],
      );

      expect(allocations.map((part) => part.items.length), [3, 7]);
      expect(
        allocations.expand((part) => part.items),
        orderedEquals(List<int>.generate(10, (index) => index)),
      );
    });

    test('handles empty input and more resources than input', () {
      expect(
        partitionByResourceWeight<int, String>(
          items: const [],
          resources: const [WorkResource(resource: 'a', weight: 1)],
        ),
        isEmpty,
      );
      final allocations = partitionByResourceWeight<int, String>(
        items: const [1, 2],
        resources: const [
          WorkResource(resource: 'a', weight: 1),
          WorkResource(resource: 'b', weight: 1),
          WorkResource(resource: 'c', weight: 1),
        ],
      );
      expect(allocations.map((part) => part.items.length), [1, 1]);
    });

    test('rejects zero, infinite, and NaN weights', () {
      for (final weight in <double>[0, double.infinity, double.nan, -1]) {
        expect(
          () => partitionByResourceWeight<int, String>(
            items: const [1],
            resources: [WorkResource(resource: 'a', weight: weight)],
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
