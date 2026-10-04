import 'dart:convert';
import 'dart:typed_data';

import 'inventory_image_models.dart';

/// SMI1 + big-endian uint32 JSON-header length + UTF-8 metadata + raw image bytes.
/// This application frame is sent only after `image-binary-v1` negotiation.
class BinaryImageJob {
  const BinaryImageJob(this.jobId, this.images);
  static const capability = 'image-binary-v1';
  static const maxFrameBytes = 32 * 1024 * 1024;
  static const maxHeaderBytes = 64 * 1024;
  static const _magic = [83, 77, 73, 49];
  final String jobId;
  final List<InventoryImageTask> images;

  Uint8List encode() {
    if (jobId.isEmpty ||
        jobId.length > 128 ||
        images.isEmpty ||
        images.length > 4) {
      throw const FormatException('Invalid binary image job');
    }
    final bytes = [
      for (final image in images)
        image.bytes ??
            (image.bytesBase64 == null
                ? throw const FormatException('Missing image bytes')
                : base64Decode(image.bytesBase64!)),
    ];
    final header = utf8.encode(
      jsonEncode({
        'version': 1,
        'jobId': jobId,
        'images': [
          for (var i = 0; i < images.length; i++)
            {
              'imageId': images[i].imageId,
              'fileName': images[i].fileName,
              'length': bytes[i].length,
            },
        ],
      }),
    );
    final total =
        8 +
        header.length +
        bytes.fold<int>(0, (sum, data) => sum + data.length);
    if (header.length > maxHeaderBytes || total > maxFrameBytes) {
      throw const FormatException('Image batch exceeds binary frame limit');
    }
    final prefix = Uint8List(8)..setRange(0, 4, _magic);
    ByteData.sublistView(prefix).setUint32(4, header.length, Endian.big);
    final output = BytesBuilder(copy: false)
      ..add(prefix)
      ..add(header);
    for (final data in bytes) {
      output.add(data);
    }
    return output.takeBytes();
  }

  factory BinaryImageJob.decode(Uint8List frame) {
    if (frame.length < 8 || frame.length > maxFrameBytes) {
      throw const FormatException('Invalid binary frame size');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (frame[i] != _magic[i]) {
        throw const FormatException('Unknown binary frame');
      }
    }
    final headerLength = ByteData.sublistView(frame).getUint32(4, Endian.big);
    if (headerLength == 0 ||
        headerLength > maxHeaderBytes ||
        8 + headerLength > frame.length) {
      throw const FormatException('Invalid binary header length');
    }
    final header = jsonDecode(
      utf8.decode(Uint8List.sublistView(frame, 8, 8 + headerLength)),
    );
    if (header is! Map ||
        header['version'] != 1 ||
        header['jobId'] is! String ||
        (header['jobId'] as String).isEmpty ||
        (header['jobId'] as String).length > 128 ||
        header['images'] is! List ||
        (header['images'] as List).isEmpty ||
        (header['images'] as List).length > 4) {
      throw const FormatException('Malformed binary job metadata');
    }
    var offset = 8 + headerLength;
    final images = <InventoryImageTask>[];
    final ids = <String>{};
    for (final entry in header['images'] as List) {
      if (entry is! Map ||
          entry['imageId'] is! String ||
          entry['fileName'] is! String ||
          (entry['imageId'] as String).isEmpty ||
          (entry['fileName'] as String).isEmpty ||
          !ids.add(entry['imageId'] as String) ||
          entry['length'] is! int ||
          (entry['length'] as int) < 0 ||
          offset + (entry['length'] as int) > frame.length) {
        throw const FormatException('Malformed binary image entry');
      }
      final end = offset + (entry['length'] as int);
      images.add(
        InventoryImageTask(
          imageId: entry['imageId'] as String,
          fileName: entry['fileName'] as String,
          bytes: Uint8List.sublistView(frame, offset, end),
        ),
      );
      offset = end;
    }
    if (offset != frame.length) {
      throw const FormatException('Unexpected trailing image bytes');
    }
    return BinaryImageJob(header['jobId'] as String, List.unmodifiable(images));
  }
}
