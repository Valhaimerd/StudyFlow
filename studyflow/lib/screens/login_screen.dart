import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/auth_service.dart';
import '../theme/study_flow_theme.dart';
import '../widgets/modal_sheet_header.dart';
import '../widgets/study_flow_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialMessage, this.onSignInSucceeded});

  final String? initialMessage;
  final VoidCallback? onSignInSucceeded;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _message;
  bool _isErrorMessage = false;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialMessage != null &&
        widget.initialMessage != oldWidget.initialMessage) {
      _message = widget.initialMessage;
      _isErrorMessage = false;
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _message = null;
      _isErrorMessage = false;
    });

    try {
      await AuthService.instance.signInWithGoogle();
      widget.onSignInSucceeded?.call();

      if (!mounted) return;

      setState(() {
        _message = 'Signing you in and preparing your workspace.';
        _isErrorMessage = false;
      });
    } on AuthMessageException catch (e) {
      if (!mounted) return;

      setState(() {
        _message = e.message;
        _isErrorMessage = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message =
            'Could not sign you in right now. Please try again in a moment.';
        _isErrorMessage = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showInfoSheet({required String title, required String body}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModalSheetHeader(title: title, subtitle: body),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isError = _isErrorMessage;
    final panelColor = isDark
        ? colorScheme.surface.withValues(alpha: 0.94)
        : theme.cardColor.withValues(alpha: 0.96);
    final panelBorderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.86);
    final panelShadowColor = isDark
        ? Colors.black.withValues(alpha: 0.28)
        : const Color(0x190F172A);

    return Scaffold(
      body: StudyFlowBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: panelColor,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: panelBorderColor),
                  boxShadow: [
                    BoxShadow(
                      color: panelShadowColor,
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/book.svg',
                          width: 34,
                          height: 34,
                          colorFilter: ColorFilter.mode(
                            colorScheme.primary,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'StudyFlow',
                          style: textTheme.titleLarge?.copyWith(
                            color: colorScheme.primary,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Access your\nworkspace',
                      style: textTheme.headlineLarge?.copyWith(
                        fontSize: 36,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sign in with Google to sync your schedules, tasks, and Classroom work when your account has access.',
                      style: textTheme.bodyLarge?.copyWith(
                        fontSize: 18,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isLoading)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            else
                              SvgPicture.asset(
                                'assets/icons/google.svg',
                                width: 26,
                                height: 26,
                              ),
                            const SizedBox(width: 16),
                            Text(
                              _isLoading
                                  ? 'Signing in...'
                                  : 'Sign in with Google',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Theme.of(context).dividerColor,
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            'OR',
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.62,
                              ),
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Theme.of(context).dividerColor,
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => _showInfoSheet(
                          title: 'Google account access',
                          body:
                              'Use any Google account for StudyFlow. Google Classroom sync depends on whether that account is enrolled in Classroom courses and has granted the requested access.',
                        ),
                        child: const Text('Google account access'),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              (isError
                                      ? StudyFlowTheme.warning
                                      : StudyFlowTheme.primary)
                                  .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                (isError
                                        ? StudyFlowTheme.warning
                                        : StudyFlowTheme.primary)
                                    .withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          _message!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: isError
                                ? StudyFlowTheme.warning
                                : StudyFlowTheme.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: StudyFlowTheme.softSurface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: SvgPicture.asset(
                              'assets/icons/shieldcheck.svg',
                              width: 24,
                              height: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Use the Google account that owns the schedules and Classroom work you want StudyFlow to sync.',
                              style: textTheme.bodyLarge?.copyWith(
                                fontSize: 16,
                                color: const Color(0xFF555D6D),
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _FooterLink(
                          label: 'Privacy Policy',
                          onTap: () => _showInfoSheet(
                            title: 'Privacy Policy',
                            body:
                                'StudyFlow stores your planner data only for your authenticated account. Academic records are scoped to your user ID and are used to power dashboard, calendar, task, subject, and sync features.',
                          ),
                        ),
                        _FooterLink(
                          label: 'Terms of Service',
                          onTap: () => _showInfoSheet(
                            title: 'Terms of Service',
                            body:
                                'Use StudyFlow as a personal academic planner. It does not replace official school systems, Google Classroom, grading, attendance, or submission portals.',
                          ),
                        ),
                        _FooterLink(
                          label: 'Google FAQ',
                          onTap: () => _showInfoSheet(
                            title: 'Google FAQ',
                            body:
                                'You can sign in with a personal or school Google account. Classroom data appears only when that account has Classroom courses and grants access.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF9BA2AD),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
