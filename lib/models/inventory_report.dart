import 'dart:convert';

import 'inventory_models.dart';

/// A complete, immutable inventory result for decoded records, not images.
///
/// Unique valid IDs include unexpected IDs. A duplicate is each valid occurrence
/// after the first, even if it arrived from a different worker. Missing and
/// unexpected IDs are set differences against the expected inventory.
class InventoryReport {
  final List<String> originalLabels;
  final List<InventoryLabelResult> labels;
  final List<String> expectedIds;
  final Map<String, int> validIdOccurrences;
  final List<String> missingExpectedIds;
  final List<String> unexpectedIds;
  final int invalidCount;
  final int unreadableCount;

  const InventoryReport._({
    required this.originalLabels,
    required this.labels,
    required this.expectedIds,
    required this.validIdOccurrences,
    required this.missingExpectedIds,
    required this.unexpectedIds,
    required this.invalidCount,
    required this.unreadableCount,
  });

  /// Aggregates complete worker batches in any completion order.
  ///
  /// Every original raw label occurrence must be returned exactly once. Missing,
  /// extra, altered, or inconsistent results throw [FormatException] rather
  /// than presenting a partial result as complete. Expected IDs must already
  /// be canonical; malformed expected IDs throw [ArgumentError].
  factory InventoryReport.aggregate({
    required Iterable<String> originalLabels,
    required Iterable<InventoryBatchResult> workerBatches,
    required Iterable<String> expectedIds,
  }) {
    return InventoryReport.fromBatches(
      originalLabels: originalLabels,
      batches: workerBatches,
      expectedIds: expectedIds,
    );
  }

  factory InventoryReport.fromBatches({
    required Iterable<String> originalLabels,
    required Iterable<InventoryBatchResult> batches,
    required Iterable<String> expectedIds,
  }) {
    final originals = List<String>.unmodifiable(originalLabels);
    final expected = <String>{};
    for (final id in expectedIds) {
      if (!InventoryProcessor.isValidId(id)) {
        throw ArgumentError.value(
          id,
          'expectedIds',
          'Expected PKG-six-digits IDs',
        );
      }
      expected.add(id);
    }

    final remaining = <String, int>{};
    for (final raw in originals) {
      remaining.update(raw, (count) => count + 1, ifAbsent: () => 1);
    }
    final results = <InventoryLabelResult>[];
    final occurrences = <String, int>{};
    var invalid = 0;
    var unreadable = 0;
    for (final batch in batches) {
      batch.validate();
      for (final label in batch.labels) {
        final count = remaining[label.rawLabel] ?? 0;
        if (count == 0) {
          throw const FormatException(
            'Worker results contain an extra or altered raw label occurrence',
          );
        }
        remaining[label.rawLabel] = count - 1;
        results.add(label);
        switch (label.status) {
          case InventoryLabelStatus.valid:
            occurrences.update(
              label.normalizedId!,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          case InventoryLabelStatus.invalid:
            invalid++;
          case InventoryLabelStatus.unreadable:
            unreadable++;
        }
      }
    }
    if (remaining.values.any((count) => count != 0)) {
      throw const FormatException(
        'Worker results are missing raw label occurrences',
      );
    }

    final validIds = occurrences.keys.toList()..sort();
    return InventoryReport._(
      originalLabels: originals,
      labels: List<InventoryLabelResult>.unmodifiable(results),
      expectedIds: _sortedIds(expected),
      validIdOccurrences: Map<String, int>.unmodifiable({
        for (final id in validIds) id: occurrences[id]!,
      }),
      missingExpectedIds: _sortedIds(
        expected.difference(occurrences.keys.toSet()),
      ),
      unexpectedIds: _sortedIds(occurrences.keys.toSet().difference(expected)),
      invalidCount: invalid,
      unreadableCount: unreadable,
    );
  }

  int get totalLabels => originalLabels.length;
  int get uniqueValidCount => validIdOccurrences.length;
  int get validOccurrenceCount => totalLabels - invalidCount - unreadableCount;
  int get duplicateCount => validOccurrenceCount - uniqueValidCount;
  int get duplicateOccurrences => duplicateCount;
  int get missingCount => missingExpectedIds.length;
  int get unexpectedCount => unexpectedIds.length;
  List<String> get validIds =>
      List<String>.unmodifiable(validIdOccurrences.keys);
  List<String> get duplicateIds => List<String>.unmodifiable(
    validIdOccurrences.keys.where((id) => validIdOccurrences[id]! > 1),
  );

  /// Canonical JSON used as a collision-free correctness signature, not a hash.
  ///
  /// It includes raw records (with whitespace and multiplicity), expected IDs,
  /// statuses, and normalized IDs. It deliberately excludes timings, diagnostic
  /// reason text, record order, and worker/batch boundaries so single-device and
  /// swarm runs of the same dataset can be compared fairly. Equal totals alone
  /// are insufficient: different datasets produce different signatures.
  String get correctnessFingerprint {
    final records =
        labels
            .map(
              (label) => jsonEncode([
                label.rawLabel,
                label.normalizedId,
                label.status.name,
              ]),
            )
            .toList()
          ..sort();
    return jsonEncode({'expectedIds': expectedIds, 'records': records});
  }

  bool hasSameCorrectnessAs(InventoryReport other) =>
      correctnessFingerprint == other.correctnessFingerprint;

  Map<String, dynamic> toJson() => {
    'originalLabels': originalLabels,
    'labels': labels.map((label) => label.toJson()).toList(),
    'expectedIds': expectedIds,
    'totalLabels': totalLabels,
    'uniqueValidCount': uniqueValidCount,
    'validOccurrenceCount': validOccurrenceCount,
    'duplicateCount': duplicateCount,
    'invalidCount': invalidCount,
    'unreadableCount': unreadableCount,
    'validIds': validIds,
    'validIdOccurrences': validIdOccurrences,
    'duplicateIds': duplicateIds,
    'missingExpectedIds': missingExpectedIds,
    'missingCount': missingCount,
    'unexpectedIds': unexpectedIds,
    'unexpectedCount': unexpectedCount,
    'correctnessFingerprint': correctnessFingerprint,
  };

  static List<String> _sortedIds(Iterable<String> ids) =>
      List<String>.unmodifiable(ids.toList()..sort());
}

/// Inputs to decoded-record validation; no image decoding or synthetic work.
class InventoryRecordDataset {
  final String name;
  final List<String> labels;
  final List<String> expectedIds;

  const InventoryRecordDataset({
    required this.name,
    required this.labels,
    required this.expectedIds,
  });
}

/// Deliberately small sample with duplicates, invalid/unreadable records, one
/// missing expected ID (000004), and one unexpected valid ID (000099).
const sampleInventoryRecordDataset = InventoryRecordDataset(
  name: 'Sample decoded inventory records (not image decoding)',
  labels: [
    'PKG-000001',
    ' pkg-000002 ',
    'PKG-000003',
    'PKG-000001',
    'pkg-000001',
    'PKG-000099',
    'BROKEN-LABEL',
    'PKG-ABC123',
    '',
    ' \t\n ',
  ],
  expectedIds: ['PKG-000001', 'PKG-000002', 'PKG-000003', 'PKG-000004'],
);
