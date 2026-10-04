import 'package:flutter/material.dart';

import '../models/math_workload.dart';
import '../services/math_report_export_service.dart';
import '../theme/app_theme.dart';

class MathReportScreen extends StatefulWidget {
  const MathReportScreen({super.key, required this.session, this.exportReport});

  final MathSession session;
  final Future<Uri?> Function(MathSession, MathReportFormat)? exportReport;

  @override
  State<MathReportScreen> createState() => _MathReportScreenState();
}

class _MathReportScreenState extends State<MathReportScreen> {
  bool _exporting = false;

  Future<void> _export(MathReportFormat format) async {
    setState(() => _exporting = true);
    try {
      final location =
          await (widget.exportReport ?? MathReportExportService.save)(
            widget.session,
            format,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            location == null
                ? 'Export cancelled'
                : 'Mathematical report exported',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final result = session.result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mathematical report'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<MathReportFormat>(
              tooltip: 'Export mathematical report',
              icon: const Icon(Icons.file_download_outlined),
              onSelected: _export,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: MathReportFormat.csv,
                  child: Text('Export CSV'),
                ),
                PopupMenuItem(
                  value: MathReportFormat.json,
                  child: Text('Export JSON'),
                ),
                PopupMenuItem(
                  value: MathReportFormat.text,
                  child: Text('Export readable text'),
                ),
                PopupMenuItem(
                  value: MathReportFormat.pdf,
                  child: Text('Export PDF'),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            session.problem.title,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('${session.createdAt.toLocal()} · ${session.id}'),
          const SizedBox(height: 16),
          _metricCard('Aggregate result', _summary(session)),
          _metricCard(
            'Correctness',
            session.correctnessMatch
                ? 'Matches single-device baseline'
                : 'MISMATCH',
            color: session.correctnessMatch
                ? AppColors.success
                : AppColors.error,
          ),
          _metricCard(
            'Timing',
            'Single: ${_milliseconds(session.baseline)}\n'
                'Distributed: ${_milliseconds(result)}\n'
                'Speedup: ${session.speedup?.toStringAsFixed(2) ?? 'not applicable'}',
          ),
          _metricCard(
            'Execution',
            'Mode: ${result.mode}\n'
                'Contributions: ${result.contributions}\n'
                'Retries: ${result.retries}\n'
                'Bytes sent/received: ${result.sentBytes}/${result.receivedBytes}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Task results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          for (final task in result.tasks)
            Card(
              child: ListTile(
                title: Text(task.taskId),
                subtitle: Text(
                  '${task.count} items · ${result.results.firstWhere((item) => item.taskId == task.taskId).values}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, {Color? color}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, height: 1.4)),
        ],
      ),
    ),
  );

  String _summary(MathSession session) => switch (session.problem) {
    MathProblem.monteCarloPi =>
      'π ≈ ${(session.result.summary['pi'] as num).toDouble().toStringAsFixed(6)}',
    MathProblem.linearRegression =>
      'y ≈ ${(session.result.summary['slope'] as num).toDouble().toStringAsFixed(4)}x + ${(session.result.summary['intercept'] as num).toDouble().toStringAsFixed(2)}',
    MathProblem.primeFactorization =>
      '${session.result.summary['factored']} integers factored',
  };

  String _milliseconds(MathRunResult result) =>
      '${(result.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms';
}
