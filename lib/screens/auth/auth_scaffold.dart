/// Shared chrome for the four auth screens (Login/Sign Up/Forgot
/// Password/Verify Code): the HUX wordmark, a headline, and a
/// scrollable body so a small phone + the keyboard never overflows.
library;

import 'package:flutter/material.dart';

import '../../theme/hux_tokens.dart';

class AuthScaffold extends StatelessWidget {
  final String headline;
  final String subtitle;
  final List<Widget> children;

  const AuthScaffold({
    super.key,
    required this.headline,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, HuxSpacing.xxl, HuxSpacing.xl, HuxSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Center(
                  child: Image.asset(
                    'assets/images/brand/hux-wordmark-white.png',
                    height: 22,
                    fit: BoxFit.contain,
                    semanticLabel: 'HUX',
                  ),
                ),
              ),
              const SizedBox(height: HuxSpacing.xl),
              Text(headline, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: HuxSpacing.sm),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HuxColors.mutedText)),
              const SizedBox(height: HuxSpacing.xxl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// An inline error banner — same "calm, not a red alert dialog" register
/// the rest of the app uses for a failed ring sync.
class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: HuxSpacing.lg),
      padding: const EdgeInsets.all(HuxSpacing.md),
      decoration: BoxDecoration(
        color: HuxColors.rundown.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
        border: Border.all(color: HuxColors.rundown.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HuxColors.ink)),
    );
  }
}

/// "Or continue with" divider + Google/Apple buttons — identical on
/// Login and Sign Up, so it's factored out once.
class AuthSocialRow extends StatelessWidget {
  final bool busy;
  final Future<void> Function() onGoogle;
  final Future<void> Function() onApple;

  const AuthSocialRow({super.key, required this.busy, required this.onGoogle, required this.onApple});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md),
              child: Text('Or continue with',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HuxColors.mutedText)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: HuxSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onGoogle,
                child: const Text('Google'),
              ),
            ),
            const SizedBox(width: HuxSpacing.md),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onApple,
                child: const Text('Apple'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
