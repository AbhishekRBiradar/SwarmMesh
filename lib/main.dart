import 'package:flutter/material.dart';

import 'screens/radar_home_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/swarm_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const SwarmMeshApp());
}

class SwarmMeshApp extends StatelessWidget {
  const SwarmMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SWARM MESH',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SwarmLogoIntro(child: RadarHomeScreen()),
    );
  }
}

class SwarmLogoIntro extends StatefulWidget {
  const SwarmLogoIntro({super.key, required this.child});
  final Widget child;

  @override
  State<SwarmLogoIntro> createState() => _SwarmLogoIntroState();
}

class _SwarmLogoIntroState extends State<SwarmLogoIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    Future<void>.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_visible)
        IgnorePointer(
          child: ColoredBox(
            color: AppTheme.dark.scaffoldBackgroundColor,
            child: Center(
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwarmLogo(size: 132),
                      SizedBox(height: 24),
                      Text(
                        'SWARM MESH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
