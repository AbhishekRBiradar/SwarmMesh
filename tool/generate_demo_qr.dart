import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:qr_image_exporter/qr_image_exporter.dart';

Future<void> main() async {
  final output = Directory('sample_images');
  await output.create(recursive: true);

  for (final entity in output.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
      await entity.delete();
    }
  }

  final payloads = <String, String>{
    for (var index = 1; index <= 12; index++)
      'label_${index.toString().padLeft(2, '0')}.png':
          'PKG-${index.toString().padLeft(6, '0')}',
    'duplicate_01.png': 'PKG-000001',
    'duplicate_02.png': 'PKG-000005',
    'unexpected.png': 'PKG-999901',
    'invalid_01.png': 'BROKEN-LABEL',
    'invalid_02.png': 'PKG-ABC123',
  };

  for (final entry in payloads.entries) {
    final qr = QrCode.fromData(
      data: entry.value,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final bytes = QrImage(qr).toPngBytes(moduleSize: 10, margin: 40);
    if (bytes == null) {
      throw StateError('Could not encode ${entry.key}');
    }
    await File('${output.path}/${entry.key}').writeAsBytes(bytes);
  }

  for (var index = 1; index <= 3; index++) {
    final blank = img.Image(width: 800, height: 800);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    await File(
      '${output.path}/unreadable_${index.toString().padLeft(2, '0')}.png',
    ).writeAsBytes(img.encodePng(blank));
  }

  final expected = StringBuffer();
  for (var index = 1; index <= 13; index++) {
    expected.writeln('PKG-${index.toString().padLeft(6, '0')}');
  }
  await File('${output.path}/expected_ids.txt')
      .writeAsString(expected.toString());

  stdout.writeln(
    'Generated ${payloads.length + 3} PNG images in ${output.path}/',
  );
  stdout.writeln(
    'Generated ${expected.toString().trim().split('\n').length} expected IDs',
  );
}
