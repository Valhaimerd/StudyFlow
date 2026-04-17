import 'package:flutter/material.dart';

import '../theme/study_flow_theme.dart';
import '../widgets/study_flow_background.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    this.progressLabel = 'INITIALIZING WORKSPACE',
    this.progressValue,
  });

  final String progressLabel;
  final double? progressValue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: StudyFlowBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Image.asset(
                    'assets/images/studyflowlogo.png',
                    width: 144,
                    height: 144,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'StudyFlow',
                    style: textTheme.displayMedium?.copyWith(
                      color: StudyFlowTheme.primary,
                      fontSize: 46,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Plan smarter. Submit on\ntime.',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      color: StudyFlowTheme.textMuted,
                      fontSize: 24,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: progressValue?.clamp(0.0, 1.0).toDouble() ?? 0,
                      ),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: progressValue == null ? null : value,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(999),
                          backgroundColor: const Color(0xFFE8ECF3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            StudyFlowTheme.primary,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    progressLabel,
                    textAlign: TextAlign.center,
                    style: textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFA0A7B2),
                      fontSize: 14,
                      letterSpacing: 3.2,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: StudyFlowTheme.textMuted.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'YOUR ACADEMIC SANCTUARY',
                        style: textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFA6ADB8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
