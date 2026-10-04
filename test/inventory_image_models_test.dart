import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/inventory_image_models.dart';
import 'package:swarm_mesh/models/inventory_models.dart';

void main() {
  test('image tasks round-trip wire-safe base64 without a local path', () {
    final task = InventoryImageTask(
      imageId: 'label-001',
      fileName: 'label-001.jpg',
      bytesBase64: base64Encode([1, 2, 3]),
    );

    final decoded = InventoryImageTask.fromJson(task.toJson());

    expect(decoded.imageId, 'label-001');
    expect(decoded.fileName, 'label-001.jpg');
    expect(base64Decode(decoded.bytesBase64!), [1, 2, 3]);
    expect(decoded.localPath, isNull);
  });

  test('image task rejects malformed bytes', () {
    expect(
      () => InventoryImageTask.fromJson({
        'imageId': 'label-001',
        'fileName': 'label-001.jpg',
        'bytesBase64': 'not base64!',
      }),
      throwsFormatException,
    );
  });

  test('decoded image becomes an inventory label result', () {
    const result = InventoryImageDecodeResult(
      imageId: 'label-001',
      fileName: 'label-001.jpg',
      decodedValue: 'pkg-000123',
      status: 'decoded',
      reason: 'Barcode decoded locally',
      elapsedMilliseconds: 12,
    );

    expect(result.toLabelResult().status, InventoryLabelStatus.valid);
    expect(result.toLabelResult().normalizedId, 'PKG-000123');
  });

  test('unreadable image becomes an unreadable inventory result', () {
    const result = InventoryImageDecodeResult(
      imageId: 'label-002',
      fileName: 'label-002.jpg',
      decodedValue: null,
      status: 'unreadable',
      reason: 'No barcode detected',
      elapsedMilliseconds: 8,
    );

    expect(result.toLabelResult().status, InventoryLabelStatus.unreadable);
  });
}
