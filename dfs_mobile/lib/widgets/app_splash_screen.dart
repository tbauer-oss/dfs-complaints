import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Branded Flutter hand-off while preferences, sessions and push state load.
class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0, .72, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _scale = Tween<double>(begin: .94, end: 1)
      .animate(
        CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      _entranceController.value = 1;
      _ambientController.stop();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Semantics(
        label: 'DFS Connect wird gestartet',
        liveRegion: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          AppColors.canvasDark,
                          Color(0xFF0C2234),
                          Color(0xFF07111C),
                        ]
                      : const [
                          Color(0xFFF7FAFD),
                          Color(0xFFEAF3FA),
                          Color(0xFFF4F7FB),
                        ],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                final phase = _ambientController.value * math.pi * 2;
                return Stack(
                  children: [
                    Positioned(
                      left: -110 + math.sin(phase) * 16,
                      top: -90 + math.cos(phase) * 12,
                      child: _AmbientOrb(
                        size: 310,
                        color: scheme.primary.withOpacity(isDark ? .18 : .11),
                      ),
                    ),
                    Positioned(
                      right: -130 + math.cos(phase) * 18,
                      bottom: -120 + math.sin(phase) * 14,
                      child: _AmbientOrb(
                        size: 360,
                        color: scheme.secondary.withOpacity(isDark ? .13 : .09),
                      ),
                    ),
                  ],
                );
              },
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 116,
                              height: 116,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.96),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: scheme.outlineVariant.withOpacity(.56),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withOpacity(
                                      isDark ? .26 : .15,
                                    ),
                                    blurRadius: 44,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: SvgPicture.asset(
                                'assets/dfs_logo.svg',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'DFS Connect',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Quality · Compliance · Service',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: .7,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 38),
                            SizedBox(
                              width: 172,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: const LinearProgressIndicator(
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Sicherer Arbeitsbereich wird vorbereitet …',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant.withOpacity(.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}
