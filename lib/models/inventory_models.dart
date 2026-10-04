enum InventoryLabelStatus { valid, invalid, unreadable }

class InventoryLabelResult {
  final String rawLabel;
  final String? normalizedId;
  final InventoryLabelStatus status;
  final String reason;

  const InventoryLabelResult({
    required this.rawLabel,
    required this.normalizedId,
    required this.status,
    required this.reason,
  });

  bool get isValid => status == InventoryLabelStatus.valid;

  Map<String, dynamic> toJson() {
    return {
      'rawLabel': rawLabel,
      'normalizedId': normalizedId,
      'status': status.name,
      'reason': reason,
    };
  }

  /// Rejects incomplete, unknown, or internally inconsistent worker results.
  factory InventoryLabelResult.fromJson(Map<String, dynamic> json) {
    final rawLabel = json['rawLabel'];
    final normalizedId = json['normalizedId'];
    final statusName = json['status'];
    final reason = json['reason'];
    if (rawLabel is! String ||
        !json.containsKey('normalizedId') ||
        (normalizedId != null && normalizedId is! String) ||
        statusName is! String ||
        reason is! String) {
      throw const FormatException('Malformed inventory label result');
    }

    final status = InventoryLabelStatus.values.where(
      (value) => value.name == statusName,
    );
    if (status.isEmpty) {
      throw FormatException('Unknown inventory label status: $statusName');
    }

    final result = InventoryLabelResult(
      rawLabel: rawLabel,
      normalizedId: normalizedId as String?,
      status: status.single,
      reason: reason,
    );
    result.validate();
    return result;
  }

  /// Also validates results created with the compatible const constructor.
  void validate() {
    final value = rawLabel.trim().toUpperCase();
    final expectedStatus = value.isEmpty
        ? InventoryLabelStatus.unreadable
        : InventoryProcessor.isValidId(value)
        ? InventoryLabelStatus.valid
        : InventoryLabelStatus.invalid;
    if (status != expectedStatus ||
        normalizedId != (value.isEmpty ? null : value)) {
      throw const FormatException(
        'Inventory label status or normalized ID does not match the raw label',
      );
    }
  }
}

class InventoryBatchResult {
  final List<InventoryLabelResult> labels;
  final int elapsedMilliseconds;

  const InventoryBatchResult({
    required this.labels,
    required this.elapsedMilliseconds,
  });

  Map<String, dynamic> toJson() {
    return {
      'labels': labels.map((label) => label.toJson()).toList(),
      'elapsedMilliseconds': elapsedMilliseconds,
    };
  }

  factory InventoryBatchResult.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    final elapsedMilliseconds = json['elapsedMilliseconds'];
    if (rawLabels is! List) {
      throw const FormatException('Inventory batch labels must be a list');
    }
    if (elapsedMilliseconds is! int || elapsedMilliseconds < 0) {
      throw const FormatException(
        'Inventory batch elapsedMilliseconds must be a non-negative integer',
      );
    }

    final labels = <InventoryLabelResult>[];
    for (final label in rawLabels) {
      if (label is! Map || label.keys.any((key) => key is! String)) {
        throw const FormatException(
          'Every inventory batch label must be an object',
        );
      }
      labels.add(
        InventoryLabelResult.fromJson(Map<String, dynamic>.from(label)),
      );
    }
    return InventoryBatchResult(
      labels: List<InventoryLabelResult>.unmodifiable(labels),
      elapsedMilliseconds: elapsedMilliseconds,
    );
  }

  void validate() {
    if (elapsedMilliseconds < 0) {
      throw const FormatException(
        'Inventory batch elapsedMilliseconds must be a non-negative integer',
      );
    }
    for (final label in labels) {
      label.validate();
    }
  }
}

/// Processes the first SwarmMesh workload: a batch of decoded label IDs.
///
/// The image/QR decoding adapter will feed this processor later. Keeping the
/// validation step pure means the same logic runs on a Leader or a Worker and
/// can be tested without a phone, camera, or network.
class InventoryProcessor {
  static final RegExp _packageId = RegExp(r'^PKG-[0-9]{6}$');

  /// Whether [id] is already in canonical PKG-six-ASCII-digits form.
  static bool isValidId(String id) =>
      id.length == 10 && _packageId.hasMatch(id);

  static InventoryBatchResult process(Iterable<String> labels) {
    final stopwatch = Stopwatch()..start();
    final results = labels.map(_processOne).toList(growable: false);
    stopwatch.stop();

    return InventoryBatchResult(
      labels: results,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  static InventoryLabelResult _processOne(String rawLabel) {
    final value = rawLabel.trim().toUpperCase();

    if (value.isEmpty) {
      return InventoryLabelResult(
        rawLabel: rawLabel,
        normalizedId: null,
        status: InventoryLabelStatus.unreadable,
        reason: 'Label could not be decoded',
      );
    }

    if (!isValidId(value)) {
      return InventoryLabelResult(
        rawLabel: rawLabel,
        normalizedId: value,
        status: InventoryLabelStatus.invalid,
        reason: 'Expected an ID such as PKG-000123',
      );
    }

    return InventoryLabelResult(
      rawLabel: rawLabel,
      normalizedId: value,
      status: InventoryLabelStatus.valid,
      reason: 'Valid package ID',
    );
  }
}
