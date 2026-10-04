import 'inventory_image_models.dart';
import 'inventory_models.dart';

/// One actual execution attempt. A missing processing duration is unknown.
class InventoryAttempt {
  const InventoryAttempt({
    required this.nodeId,
    required this.succeeded,
    this.error,
    this.processingMicroseconds,
  });

  final String nodeId;
  final bool succeeded;
  final String? error;
  final int? processingMicroseconds;

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'succeeded': succeeded,
    'error': error,
    'processingMicroseconds': processingMicroseconds,
  };

  factory InventoryAttempt.fromJson(Map<String, dynamic> json) {
    final duration = json['processingMicroseconds'];
    if (json['nodeId'] is! String ||
        json['succeeded'] is! bool ||
        (json['error'] != null && json['error'] is! String) ||
        (duration != null && (duration is! int || duration < 0))) {
      throw const FormatException('Invalid execution attempt');
    }
    return InventoryAttempt(
      nodeId: json['nodeId'] as String,
      succeeded: json['succeeded'] as bool,
      error: json['error'] as String?,
      processingMicroseconds: duration as int?,
    );
  }
}

/// Input-order record retained for export/history, with no source image bytes.
class InventoryExecution {
  const InventoryExecution({
    required this.label,
    required this.nodeId,
    required this.attempts,
    this.image,
  });

  final InventoryLabelResult label;
  final InventoryImageDecodeResult? image;
  final String nodeId;
  final List<InventoryAttempt> attempts;
  int get retryCount => attempts.where((attempt) => !attempt.succeeded).length;

  Map<String, dynamic> toJson() => {
    'label': label.toJson(),
    'image': image?.toJson(),
    'nodeId': nodeId,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };

  factory InventoryExecution.fromJson(Map<String, dynamic> json) =>
      InventoryExecution(
        label: InventoryLabelResult.fromJson(
          Map<String, dynamic>.from(json['label'] as Map),
        ),
        image: json['image'] == null
            ? null
            : InventoryImageDecodeResult.fromJson(
                Map<String, dynamic>.from(json['image'] as Map),
              ),
        nodeId: json['nodeId'] as String,
        attempts: List.unmodifiable(
          (json['attempts'] as List).map(
            (attempt) => InventoryAttempt.fromJson(
              Map<String, dynamic>.from(attempt as Map),
            ),
          ),
        ),
      );
}
