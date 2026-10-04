import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/math_workload.dart';
import '../models/inventory_session.dart';

class SessionHistory {
  const SessionHistory(
    this.sessions,
    this.unreadableFiles, {
    this.mathSessions = const [],
  });
  final List<InventorySession> sessions;
  final List<String> unreadableFiles;
  final List<MathSession> mathSessions;
}

/// Report-only files in Android's private no-backup directory. Source images are
/// never copied here. Saves/deletes/reads are serialized to avoid resurrection.
class SessionHistoryService {
  SessionHistoryService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _nativeDirectory;
  final Future<Directory> Function() _directoryProvider;
  Future<void> _pending = Future<void>.value();

  static Future<Directory> _nativeDirectory() async {
    final path = await const MethodChannel('swarm_mesh/storage')
        .invokeMethod<String>('getReportDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('Private report storage unavailable');
    }
    return Directory(path);
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  String _fileName(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw ArgumentError('Invalid session ID');
    }
    return '$id.json';
  }

  Future<void> save(InventorySession session) => _serialized(() async {
    final name = _fileName(session.id);
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/$name.tmp');
    try {
      await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
      await temporary.rename('${directory.path}/$name');
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });

  Future<SessionHistory> load() => _serialized(() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return const SessionHistory([], []);
    final sessions = <InventorySession>[];
    final mathSessions = <MathSession>[];
    final unreadable = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final name = entry.uri.pathSegments.last;
      try {
        final json = Map<String, dynamic>.from(
          jsonDecode(await entry.readAsString()) as Map,
        );
        if (name.startsWith('math-')) {
          final session = MathSession.fromJson(json);
          if (_mathFileName(session.id) != name) {
            throw const FormatException('Math session filename mismatch');
          }
          mathSessions.add(session);
        } else {
          final session = InventorySession.fromJson(json);
          if (_fileName(session.id) != name) {
            throw const FormatException('Session filename mismatch');
          }
          sessions.add(session);
        }
      } catch (_) {
        unreadable.add(name);
      }
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    mathSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SessionHistory(
      List.unmodifiable(sessions),
      List.unmodifiable(unreadable),
      mathSessions: List.unmodifiable(mathSessions),
    );
  });

  String _mathFileName(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw ArgumentError('Invalid mathematical session ID');
    }
    return 'math-$id.json';
  }

  Future<void> saveMath(MathSession session) => _serialized(() async {
    final name = _mathFileName(session.id);
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/$name.tmp');
    try {
      await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
      await temporary.rename('${directory.path}/$name');
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });

  Future<void> delete(String id) => _serialized(() async {
    final name = _fileName(id);
    final directory = await _directoryProvider();
    final file = File('${directory.path}/$name');
    if (await file.exists()) await file.delete();
  });

  Future<void> deleteMath(String id) => _serialized(() async {
    final name = _mathFileName(id);
    final directory = await _directoryProvider();
    final file = File('${directory.path}/$name');
    if (await file.exists()) await file.delete();
  });
}
