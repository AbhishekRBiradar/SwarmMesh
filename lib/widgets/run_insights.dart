import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mesh_models.dart';
import '../models/run_diagnostics.dart';
import '../theme/app_theme.dart';

class RunInsights extends StatelessWidget {
  const RunInsights({
    super.key,
    required this.baseline,
    required this.result,
    this.devices = const {},
  });
  final MeshRunResult baseline, result;
  final Map<String, String> devices;

  @override
  Widget build(BuildContext context) {
    final matches = result.hasSameCorrectnessAs(baseline);
    final comparable =
        matches && result.isSwarm && result.elapsed.inMicroseconds > 0;
    final ratio = comparable
        ? baseline.elapsed.inMicroseconds / result.elapsed.inMicroseconds
        : null;
    final ceiling = math.max(
      1,
      math.max(baseline.elapsed.inMicroseconds, result.elapsed.inMicroseconds),
    );
    final color = !matches
        ? AppColors.error
        : ratio != null && ratio < 1
        ? AppColors.warning
        : AppColors.success;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RUN INTELLIGENCE',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              !matches
                  ? 'Results need investigation'
                  : ratio == null
                  ? 'Completed on the local path'
                  : ratio >= 1
                  ? 'Distribution helped this run'
                  : 'One phone was faster this run',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ratio == null
                  ? 'A speed ratio requires matching results and remote participation.'
                  : '${ratio.toStringAsFixed(2)}× baseline / distributed elapsed time. '
                        'Use repeated runs before drawing conclusions.',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            _bar('Single device', baseline.elapsed, ceiling, AppColors.muted),
            const SizedBox(height: 14),
            _bar(
              result.isSwarm ? 'Distributed' : 'Local fallback',
              result.elapsed,
              ceiling,
              AppColors.cyan,
            ),
            const SizedBox(height: 20),
            const Text(
              'Completed work by device',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final entry in result.contributions.entries) ...[
              Text(
                '${devices[entry.key] ?? entry.key} · ${entry.value} items',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: result.results.isEmpty
                    ? 0
                    : (entry.value / result.results.length).clamp(0, 1),
                color: AppColors.accent,
                backgroundColor: AppColors.elevated,
                borderRadius: BorderRadius.circular(8),
                minHeight: 5,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '${result.retries} failed remote attempts · ${result.totalBytes} application bytes',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Divider(height: 28),
            ExpansionTile(
              key: const PageStorageKey('run-diagnostics'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                'Performance diagnostics',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                result.diagnostics.phases.isEmpty
                    ? 'Not recorded for this run'
                    : '${result.diagnostics.phases.length} measured phases · tap to inspect',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  RunDiagnostics.measurementNote,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in result.diagnostics.phases.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${entry.value.milliseconds.toStringAsFixed(2)} ms total · '
                          '${entry.value.samples} spans · '
                          '${(entry.value.maxMicroseconds / 1000).toStringAsFixed(2)} ms max',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(String label, Duration duration, int ceiling, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${(duration.inMicroseconds / 1000).toStringAsFixed(2)} ms',
                style: TextStyle(color: color),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: (duration.inMicroseconds / ceiling).clamp(0, 1),
            color: color,
            backgroundColor: AppColors.elevated,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      );
}
