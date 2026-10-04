import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mesh_models.dart';
import '../theme/app_theme.dart';

/// A logical connection diagram, not an estimate of physical device positions.
class MeshTopology extends StatelessWidget {
  const MeshTopology({
    super.key,
    required this.snapshot,
    required this.animation,
  });

  final MeshRuntimeSnapshot snapshot;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final peers = snapshot.peers.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LOCAL FABRIC',
            style: TextStyle(
              letterSpacing: 2,
              fontSize: 11,
              color: AppColors.cyan,
            ),
          ),
          Semantics(
            label:
                'Logical topology. This ${snapshot.isLeader ? 'Leader' : 'Worker'} '
                'has ${snapshot.connectedPeers} connected peers.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => CustomPaint(
                      painter: _TopologyPainter(
                        peers: peers,
                        progress: animation.value,
                        active: snapshot.active,
                        running: snapshot.running,
                        leader: snapshot.isLeader,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            snapshot.active
                ? peers.isEmpty
                      ? 'Searching for peers'
                      : '${snapshot.connectedPeers} connected · ${snapshot.pendingRequests.length} awaiting approval'
                : 'This phone',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (peers.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (var i = 0; i < peers.length; i++)
                  Text(
                    '${i + 1} · ${peers[i].telemetry.deviceModel}',
                    style: TextStyle(
                      fontSize: 12,
                      color: peers[i].connected
                          ? AppColors.cyan
                          : AppColors.muted,
                    ),
                  ),
                if (snapshot.peers.length > peers.length)
                  Text('+${snapshot.peers.length - peers.length} in Network'),
              ],
            ),
          const SizedBox(height: 8),
          const Text(
            'Logical view only',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _TopologyPainter extends CustomPainter {
  _TopologyPainter({
    required this.peers,
    required this.progress,
    required this.active,
    required this.running,
    required this.leader,
  });
  final List<MeshPeer> peers;
  final double progress;
  final bool active, running, leader;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2 - 28, 80.0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final factor in [.55, 1.0, 1.2]) {
      canvas.drawCircle(
        center,
        radius * factor,
        stroke..color = AppColors.border.withValues(alpha: .5),
      );
    }
    if (active) {
      canvas.drawCircle(
        center,
        30 + progress * 22,
        stroke
          ..color = AppColors.accent.withValues(alpha: .35 * (1 - progress)),
      );
    }
    for (var i = 0; i < peers.length; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / peers.length;
      final end = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final color = peers[i].connected ? AppColors.cyan : AppColors.border;
      canvas.drawLine(center, end, stroke..color = color.withValues(alpha: .5));
      if (running && peers[i].connected) {
        canvas.drawCircle(
          Offset.lerp(center, end, progress)!,
          3,
          Paint()..color = color,
        );
      }
      canvas.drawCircle(end, 17, Paint()..color = AppColors.elevated);
      canvas.drawCircle(end, 17, stroke..color = color);
      _label(canvas, '${i + 1}', end, color, 12);
    }
    canvas.drawCircle(
      center,
      29,
      Paint()..color = active ? AppColors.accent : AppColors.elevated,
    );
    _label(
      canvas,
      leader ? 'LEAD' : 'WORK',
      center,
      active ? AppColors.background : AppColors.muted,
      10,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset point,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      point - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_TopologyPainter old) => true;
}
