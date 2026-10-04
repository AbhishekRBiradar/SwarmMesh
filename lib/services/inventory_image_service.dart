import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../models/inventory_image_models.dart';

/// Decodes stored image files on the phone. The runtime sends image bytes to a
/// Worker, which uses the same service against a temporary local file.
class InventoryImageService {
  InventoryImageService()
    : _scanner = BarcodeScanner(
        formats: const [
          BarcodeFormat.qrCode,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upca,
          BarcodeFormat.upce,
          BarcodeFormat.dataMatrix,
        ],
      );

  final BarcodeScanner _scanner;

  Future<InventoryImageDecodeResult> decodeFile({
    required String imageId,
    required String fileName,
    required String path,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final barcodes = await _scanner.processImage(
        InputImage.fromFilePath(path),
      );
      final value = _firstValue(barcodes);
      stopwatch.stop();
      if (value == null || value.trim().isEmpty) {
        return InventoryImageDecodeResult(
          imageId: imageId,
          fileName: fileName,
          decodedValue: null,
          status: 'unreadable',
          reason: 'No QR code or barcode was detected',
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        );
      }
      return InventoryImageDecodeResult(
        imageId: imageId,
        fileName: fileName,
        decodedValue: value,
        status: 'decoded',
        reason: 'Barcode decoded locally',
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      return InventoryImageDecodeResult(
        imageId: imageId,
        fileName: fileName,
        decodedValue: null,
        status: 'error',
        reason: 'Image decode failed: ${_short(error)}',
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<InventoryImageDecodeResult> decodeTask(InventoryImageTask task) async {
    final path = task.localPath;
    if (path != null) {
      return decodeFile(
        imageId: task.imageId,
        fileName: task.fileName,
        path: path,
      );
    }
    final encoded = task.bytesBase64;
    if (encoded == null && task.bytes == null) {
      return InventoryImageDecodeResult(
        imageId: task.imageId,
        fileName: task.fileName,
        decodedValue: null,
        status: 'error',
        reason: 'Worker received no image bytes',
        elapsedMilliseconds: 0,
      );
    }

    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await Directory.systemTemp.createTemp('swarmmesh-');
      final extension = _extension(task.fileName);
      final file = File('${temporaryDirectory.path}/input.$extension');
      await file.writeAsBytes(
        task.bytes ?? base64Decode(encoded!),
        flush: true,
      );
      return await decodeFile(
        imageId: task.imageId,
        fileName: task.fileName,
        path: file.path,
      );
    } catch (error) {
      return InventoryImageDecodeResult(
        imageId: task.imageId,
        fileName: task.fileName,
        decodedValue: null,
        status: 'error',
        reason: 'Image transfer failed: ${_short(error)}',
        elapsedMilliseconds: 0,
      );
    } finally {
      if (temporaryDirectory != null) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  Future<List<InventoryImageDecodeResult>> decodeFiles(
    Iterable<InventoryImageTask> tasks,
  ) async {
    final results = <InventoryImageDecodeResult>[];
    for (final task in tasks) {
      results.add(await decodeTask(task));
    }
    return results;
  }

  Future<void> dispose() => _scanner.close();

  String? _firstValue(List<Barcode> barcodes) {
    for (final barcode in barcodes) {
      final value = barcode.rawValue ?? barcode.displayValue;
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'jpg';
    final extension = fileName.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension) ? extension : 'jpg';
  }

  String _short(Object error) => error.toString().split('\n').first;
}
