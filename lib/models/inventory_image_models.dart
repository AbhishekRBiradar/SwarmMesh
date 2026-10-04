import 'dart:convert';
import 'dart:typed_data';

import 'inventory_models.dart';

class InventoryImageTask {
  const InventoryImageTask({
    required this.imageId,
    required this.fileName,
    this.localPath,
    this.bytesBase64,
    this.bytes,
  });

  final String imageId;
  final String fileName;
  final String? localPath;
  final String? bytesBase64;
  final Uint8List? bytes;

  bool get hasBytes => bytes != null || bytesBase64 != null;

  factory InventoryImageTask.fromPath(String path, {String? imageId}) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    return InventoryImageTask(
      imageId: imageId ?? fileName,
      fileName: fileName,
      localPath: path,
    );
  }

  factory InventoryImageTask.fromJson(Map<String, dynamic> json) {
    final imageId = json['imageId'];
    final fileName = json['fileName'];
    final bytesBase64 = json['bytesBase64'];
    if (imageId is! String ||
        imageId.isEmpty ||
        fileName is! String ||
        fileName.isEmpty ||
        (bytesBase64 != null && bytesBase64 is! String)) {
      throw const FormatException('Malformed inventory image task');
    }
    if (bytesBase64 != null) {
      try {
        base64Decode(bytesBase64);
      } catch (_) {
        throw const FormatException('Inventory image bytes are not base64');
      }
    }
    return InventoryImageTask(
      imageId: imageId,
      fileName: fileName,
      bytesBase64: bytesBase64 as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'fileName': fileName,
      if (bytes != null || bytesBase64 != null)
        'bytesBase64': bytesBase64 ?? base64Encode(bytes!),
    };
  }
}

class InventoryImageDecodeResult {
  const InventoryImageDecodeResult({
    required this.imageId,
    required this.fileName,
    required this.decodedValue,
    required this.status,
    required this.reason,
    required this.elapsedMilliseconds,
  });

  final String imageId;
  final String fileName;
  final String? decodedValue;
  final String status;
  final String reason;
  final int elapsedMilliseconds;

  bool get decoded => status == 'decoded' && decodedValue != null;

  InventoryLabelResult toLabelResult() {
    if (!decoded || decodedValue!.trim().isEmpty) {
      return InventoryLabelResult(
        rawLabel: '',
        normalizedId: null,
        status: InventoryLabelStatus.unreadable,
        reason: reason,
      );
    }
    return InventoryProcessor.process([decodedValue!]).labels.single;
  }

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'fileName': fileName,
      'decodedValue': decodedValue,
      'status': status,
      'reason': reason,
      'elapsedMilliseconds': elapsedMilliseconds,
    };
  }

  factory InventoryImageDecodeResult.fromJson(Map<String, dynamic> json) {
    final imageId = json['imageId'];
    final fileName = json['fileName'];
    final decodedValue = json['decodedValue'];
    final status = json['status'];
    final reason = json['reason'];
    final elapsed = json['elapsedMilliseconds'];
    if (imageId is! String ||
        fileName is! String ||
        (decodedValue != null && decodedValue is! String) ||
        status is! String ||
        !{'decoded', 'unreadable', 'error'}.contains(status) ||
        reason is! String ||
        elapsed is! int ||
        elapsed < 0) {
      throw const FormatException('Malformed inventory image result');
    }
    if (status == 'decoded' && (decodedValue as String?) == null) {
      throw const FormatException('Decoded image result has no value');
    }
    return InventoryImageDecodeResult(
      imageId: imageId,
      fileName: fileName,
      decodedValue: decodedValue as String?,
      status: status,
      reason: reason,
      elapsedMilliseconds: elapsed,
    );
  }
}
