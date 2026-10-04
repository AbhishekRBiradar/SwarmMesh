import 'package:flutter/material.dart';

import '../models/math_workload.dart';
import '../models/inventory_session.dart';
import '../services/session_history_service.dart';
import 'math_report_screen.dart';
import 'session_report_screen.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key, required this.history});
  final SessionHistoryService history;

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  late Future<SessionHistory> _sessions;
  final _deleting = <String>{};

  @override
  void initState() {
    super.initState();
    _sessions = widget.history.load();
  }

  Future<void> _delete(InventorySession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved session?'),
        content: Text(
          'Remove "${session.datasetName}" from this app’s history? '
          'Source images and separately exported files are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(session.id));
    try {
      await widget.history.delete(session.id);
      if (mounted) setState(() => _sessions = widget.history.load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(session.id));
    }
  }

  Future<void> _deleteMath(MathSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete mathematical report?'),
        content: Text(
          'Remove "${session.problem.title}" from this app\'s history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(session.id));
    try {
      await widget.history.deleteMath(session.id);
      if (mounted) setState(() => _sessions = widget.history.load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(session.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved inventory sessions')),
    body: FutureBuilder<SessionHistory>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load session history: ${snapshot.error}'),
                  TextButton(
                    onPressed: () =>
                        setState(() => _sessions = widget.history.load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final groups = <String, List<InventorySession>>{};
        for (final session in data.sessions) {
          if (session.benchmarkGroupId != null) {
            groups
                .putIfAbsent(session.benchmarkGroupId!, () => [])
                .add(session);
          }
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Reports are saved only on this Leader in private app storage until deleted. '
              'Source image files are not copied into history.',
            ),
            const SizedBox(height: 16),
            for (final group in groups.values) _benchmarkCard(group),
            if (data.unreadableFiles.isNotEmpty)
              Text(
                '${data.unreadableFiles.length} saved report(s) could not be opened. '
                'Their files have been retained.',
                style: const TextStyle(color: Colors.amber),
              ),
            if (data.sessions.isEmpty && data.mathSessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'No saved sessions yet. Complete an inventory run on this Leader to create one.',
                ),
              ),
            for (final session in data.sessions)
              Card(
                child: ListTile(
                  title: Text(session.datasetName),
                  subtitle: Text(
                    '${session.isDemo ? 'Demo Dataset · ' : ''}${session.result.report.totalLabels} items\n'
                    '${session.createdAt.toLocal()}',
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SessionReportScreen(session: session),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete ${session.datasetName}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _deleting.contains(session.id)
                        ? null
                        : () => _delete(session),
                  ),
                ),
              ),
            if (data.mathSessions.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 20, bottom: 6),
                child: Text(
                  'Mathematical runs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              for (final session in data.mathSessions)
                Card(
                  child: ListTile(
                    title: Text(session.problem.title),
                    subtitle: Text(
                      '${session.result.mode} · ${session.result.tasks.length} tasks\n'
                      '${session.createdAt.toLocal()}',
                    ),
                    isThreeLine: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MathReportScreen(session: session),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete ${session.problem.title}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _deleting.contains(session.id)
                          ? null
                          : () => _deleteMath(session),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );

  Widget _benchmarkCard(List<InventorySession> sessions) {
    final summary = BenchmarkSummary(sessions);
    return Card(
      child: ExpansionTile(
        title: Text('Benchmark: ${sessions.first.datasetName}'),
        subtitle: Text(
          '${sessions.length} saved pairs · ${summary.comparable ? 'correctness matches' : 'mismatch'}',
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Median single / distributed: ${(summary.medianSingleMicroseconds / 1000).toStringAsFixed(2)} / '
            '${(summary.medianSwarmMicroseconds / 1000).toStringAsFixed(2)} ms',
          ),
          Text(
            'Best / worst single: ${(summary.bestSingleMicroseconds / 1000).toStringAsFixed(2)} / '
            '${(summary.worstSingleMicroseconds / 1000).toStringAsFixed(2)} ms',
          ),
          Text(
            'Best / worst distributed: ${(summary.bestSwarmMicroseconds / 1000).toStringAsFixed(2)} / '
            '${(summary.worstSwarmMicroseconds / 1000).toStringAsFixed(2)} ms',
          ),
          if (summary.speedup != null)
            Text('Median speedup: ${summary.speedup!.toStringAsFixed(2)}×'),
          if (!summary.allSwarm)
            const Text('Includes local fallback; no swarm speedup claimed.'),
          const Text(
            'Open individual saved pairs below for exports, contributions, bytes and retries.',
          ),
        ],
      ),
    );
  }
}
