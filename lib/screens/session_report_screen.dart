import 'package:flutter/material.dart';

import '../models/inventory_session.dart';
import '../models/inventory_models.dart';
import '../services/report_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/run_insights.dart';

enum _RecordFilter { all, issues, duplicates, unreadable, retried }

class SessionReportScreen extends StatefulWidget {
  const SessionReportScreen({
    super.key,
    required this.session,
    this.exportReport,
  });
  final InventorySession session;
  final Future<Uri?> Function(InventorySession, ReportFormat)? exportReport;

  @override
  State<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends State<SessionReportScreen> {
  bool _exporting = false;
  final _search = TextEditingController();
  _RecordFilter _filter = _RecordFilter.all;
  late final _allRows = widget.session.rows;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(InventorySessionRow row) {
    final item = row.execution;
    final category = switch (_filter) {
      _RecordFilter.all => true,
      _RecordFilter.issues =>
        !item.label.isValid || row.duplicate || row.unexpected == true,
      _RecordFilter.duplicates => row.duplicate,
      _RecordFilter.unreadable =>
        item.label.status == InventoryLabelStatus.unreadable,
      _RecordFilter.retried => item.retryCount > 0,
    };
    final query = _search.text.trim().toLowerCase();
    return category &&
        (query.isEmpty ||
            [
              item.image?.fileName ?? '',
              item.image?.imageId ?? '',
              item.label.rawLabel,
              item.label.normalizedId ?? '',
              item.nodeId,
              widget.session.devices[item.nodeId] ?? '',
            ].any((value) => value.toLowerCase().contains(query)));
  }

  Future<void> _export(ReportFormat format) async {
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _exporting = true);
    try {
      final location = await (widget.exportReport ?? ReportExportService.save)(
        widget.session,
        format,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            location == null
                ? 'Export cancelled'
                : 'Report exported successfully',
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
    final report = result.report;
    final rows = _allRows.indexed.where((entry) => _matches(entry.$2)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory report'),
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
            PopupMenuButton<ReportFormat>(
              tooltip: 'Export report',
              icon: const Icon(Icons.file_download_outlined),
              onSelected: _export,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: ReportFormat.csv,
                  child: Text('Export CSV'),
                ),
                PopupMenuItem(
                  value: ReportFormat.json,
                  child: Text('Export JSON'),
                ),
                PopupMenuItem(
                  value: ReportFormat.text,
                  child: Text('Export readable text'),
                ),
                PopupMenuItem(
                  value: ReportFormat.pdf,
                  child: Text('Export PDF'),
                ),
              ],
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.datasetName,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${session.createdAt.toLocal()} · ${session.leaderNodeId}',
                ),
                if (session.isDemo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'DEMO DATASET — generated/sample data; not a warehouse performance result.',
                      style: TextStyle(color: Colors.amber),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _summaryChip(
                      '${report.uniqueValidCount} valid',
                      AppColors.success,
                    ),
                    _summaryChip(
                      '${report.duplicateCount} duplicate',
                      AppColors.warning,
                    ),
                    _summaryChip(
                      '${report.invalidCount + report.unreadableCount} to review',
                      AppColors.error,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RunInsights(
                  baseline: session.baseline,
                  result: result,
                  devices: session.devices,
                ),
                const SizedBox(height: 16),
                Text(
                  '${report.totalLabels} items · ${report.uniqueValidCount} unique valid · '
                  '${report.duplicateCount} duplicates · ${report.invalidCount} invalid · ${report.unreadableCount} unreadable',
                ),
                const SizedBox(height: 12),
                Text(
                  'Correctness: ${session.correctnessMatch ? 'matches single-device baseline' : 'MISMATCH'}',
                  style: TextStyle(
                    color: session.correctnessMatch
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                ),
                Text(
                  'Single device: ${(session.baseline.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms',
                ),
                Text(
                  '${result.isSwarm ? 'Swarm' : 'Local fallback'}: ${(result.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms',
                ),
                if (session.speedup != null)
                  Text('Speedup: ${session.speedup!.toStringAsFixed(2)}×'),
                Text(
                  'Job bytes sent/received: ${result.sentBytes} / ${result.receivedBytes}',
                ),
                Text('Failed remote attempts: ${result.retries}'),
                const SizedBox(height: 12),
                const Text(
                  'Completed contributions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final entry in result.contributions.entries)
                  Text(
                    '${session.devices[entry.key] ?? entry.key} (${entry.key}): ${entry.value} items',
                  ),
                const SizedBox(height: 12),
                if (result.expectedIds.isEmpty)
                  const Text(
                    'No expected list: missing/unexpected checks not performed.',
                  )
                else ...[
                  Text(
                    'Missing IDs (${report.missingCount}): ${report.missingExpectedIds.isEmpty ? 'None' : report.missingExpectedIds.join(', ')}',
                  ),
                  Text(
                    'Unexpected IDs (${report.unexpectedCount}): ${report.unexpectedIds.isEmpty ? 'None' : report.unexpectedIds.join(', ')}',
                  ),
                ],
                const Divider(height: 32),
                const Text(
                  'Image / record details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('report-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search ID, filename or device',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final filter in _RecordFilter.values)
                      ChoiceChip(
                        label: Text(switch (filter) {
                          _RecordFilter.all => 'All records',
                          _RecordFilter.issues => 'Needs review',
                          _RecordFilter.duplicates => 'Duplicates',
                          _RecordFilter.unreadable => 'Unreadable',
                          _RecordFilter.retried => 'Retried',
                        }),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    rows.isEmpty
                        ? 'No records match this search and filter.'
                        : '${rows.length} of ${_allRows.length} records · exports always include the complete report',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          }
          final entry = rows[index - 1];
          final row = entry.$2;
          final sourceIndex = entry.$1 + 1;
          final item = row.execution;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              key: ValueKey('record-$sourceIndex'),
              leading: Icon(
                row.duplicate || row.unexpected == true || !item.label.isValid
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline,
                color:
                    row.duplicate ||
                        row.unexpected == true ||
                        !item.label.isValid
                    ? AppColors.warning
                    : AppColors.success,
              ),
              title: Text(item.image?.fileName ?? 'Text record $sourceIndex'),
              subtitle: Text(
                '${item.label.normalizedId ?? 'No decoded ID'} · ${item.label.status.name}'
                '${row.duplicate ? ' · DUPLICATE' : ''}${row.unexpected == true ? ' · UNEXPECTED' : ''}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Source ID: ${item.image?.imageId ?? 'record-$sourceIndex'}',
                ),
                Text('Processed by: ${item.nodeId}'),
                Text(
                  'Processing: ${item.image?.elapsedMilliseconds ?? 'not measured per item'}${item.image == null ? '' : ' ms'}',
                ),
                Text('Reason: ${item.image?.reason ?? item.label.reason}'),
                Text('Retries affecting this item: ${item.retryCount}'),
                for (final attempt in item.attempts)
                  Text(
                    '${attempt.nodeId}: ${attempt.succeeded ? 'completed' : 'failed'}'
                    '${attempt.error == null ? '' : ' — ${attempt.error}'}'
                    '${attempt.processingMicroseconds == null ? '' : ' · batch ${attempt.processingMicroseconds} µs'}',
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
