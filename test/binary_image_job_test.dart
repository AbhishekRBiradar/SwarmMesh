import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swarm_mesh/models/binary_image_job.dart';
import 'package:swarm_mesh/models/inventory_image_models.dart';
import 'package:swarm_mesh/services/inventory_image_service.dart';

void main() {
  final bytes = Uint8List.fromList(List.generate(4096, (index) => index % 256));
  final job = BinaryImageJob('job-1', [
    InventoryImageTask(imageId: 'image-1', fileName: '标签.png', bytes: bytes),
    InventoryImageTask(
      imageId: 'image-2',
      fileName: 'second.png',
      bytes: Uint8List.fromList([0, 255, 42]),
    ),
  ]);

  test(
    'raw image bytes reach the decoder file and temporary files are removed',
    () async {
      final decoder = _FileProbe();
      await decoder.decodeTask(job.images.first);
      expect(decoder.received, bytes);
      expect(await File(decoder.path!).exists(), isFalse);
    },
  );

  test('binary transfer preserves exact bytes and Unicode metadata with less overhead', () {
    final frame = job.encode();
    final decoded = BinaryImageJob.decode(frame);
    expect(decoded.jobId, 'job-1');
    expect(decoded.images.first.fileName, '标签.png');
    expect(decoded.images.first.bytes, bytes);
    expect(decoded.images.last.bytes, [0, 255, 42]);
    expect(decoded.images.first.localPath, isNull);
    expect(
      frame.length,
      lessThan(
        utf8
            .encode(
              jsonEncode({
                'jobId': job.jobId,
                'images': job.images.map((image) => image.toJson()).toList(),
              }),
            )
            .length,
      ),
    );
  });

  test('truncation, wrong version, trailing bytes and oversized headers are rejected', () {
    final frame = job.encode();
    expect(
      () => BinaryImageJob.decode(
        Uint8List.sublistView(frame, 0, frame.length - 1),
      ),
      throwsFormatException,
    );
    expect(
      () => BinaryImageJob.decode(Uint8List.fromList([...frame, 0])),
      throwsFormatException,
    );
    final wrongMagic = Uint8List.fromList(frame)..[0] = 0;
    expect(() => BinaryImageJob.decode(wrongMagic), throwsFormatException);
    final wrongLength = Uint8List.fromList(frame);
    ByteData.sublistView(wrongLength)
        .setUint32(4, BinaryImageJob.maxHeaderBytes + 1, Endian.big);
    expect(() => BinaryImageJob.decode(wrongLength), throwsFormatException);
    expect(
      () => BinaryImageJob('empty', const []).encode(),
      throwsFormatException,
    );
    expect(
      () => BinaryImageJob('many', List.filled(5, job.images.first)).encode(),
      throwsFormatException,
    );
  });
}

class _FileProbe extends InventoryImageService {
  String? path;
  List<int>? received;
  @override
  Future<InventoryImageDecodeResult> decodeFile({
    required String imageId,
    required String fileName,
    required String path,
  }) async {
    this.path = path;
    received = await File(path).readAsBytes();
    return InventoryImageDecodeResult(
      imageId: imageId,
      fileName: fileName,
      decodedValue: 'PKG-000001',
      status: 'decoded',
      reason: 'Test',
      elapsedMilliseconds: 1,
    );
  }
}
