import 'package:flutter/material.dart';

class StudyFlowBackground extends StatelessWidget {
  const StudyFlowBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scaffoldBackground = theme.scaffoldBackgroundColor;
    final isDark = theme.brightness == Brightness.dark;
    final gradientColors = isDark
        ? [
            Color.alphaBlend(
              colorScheme.primary.withValues(alpha: 0.1),
              scaffoldBackground,
            ),
            scaffoldBackground,
            Color.alphaBlend(
              colorScheme.secondary.withValues(alpha: 0.08),
              scaffoldBackground,
            ),
          ]
        : [
            Color.alphaBlend(
              colorScheme.primary.withValues(alpha: 0.06),
              scaffoldBackground,
            ),
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.82),
              scaffoldBackground,
            ),
            Color.alphaBlend(
              colorScheme.secondary.withValues(alpha: 0.05),
              scaffoldBackground,
            ),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -160,
            child: _GlowBubble(
              size: 380,
              colors: [
                colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
                colorScheme.primary.withValues(alpha: 0),
              ],
            ),
          ),
          Positioned(
            right: -170,
            bottom: -160,
            child: _GlowBubble(
              size: 360,
              colors: [
                colorScheme.secondary.withValues(alpha: isDark ? 0.12 : 0.1),
                colorScheme.secondary.withValues(alpha: 0),
              ],
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  const _GlowBubble({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
