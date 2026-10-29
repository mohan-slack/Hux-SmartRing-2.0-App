/// Step 2 of email sign-up: type the code from the "Confirm signup"
/// email. Codes, not links: a link opens a browser, not the app.
/// Supabase template "Confirm signup" must contain `{{ .Token }}`
/// (see docs/release/EMAIL_SETUP.md).
library;

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/hux_tokens.dart';
import 'auth_scaffold.dart';

class ConfirmSignUpScreen extends StatefulWidget {
  final AuthService authService;
  final String email;

  const ConfirmSignUpScreen({super.key, required this.authService, required this.email});

  @override
  State<ConfirmSignUpScreen> createState() => _ConfirmSignUpScreenState();
}

class _ConfirmSignUpScreenState extends State<ConfirmSignUpScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (done != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() => _run(() async {
        await widget.authService.verifySignUpCode(email: widget.email, code: _codeController.text.trim());
        if (!mounted) return;
        // Signed in now: app.dart's auth gate shows the app underneath.
        Navigator.of(context).popUntil((route) => route.isFirst);
      });

  @override
  Widget build(BuildContext context) {
    final code = _codeController.text.trim();
    return AuthScaffold(
      headline: 'Confirm your email',
      subtitle: 'We sent a code to ${widget.email}. It can take a minute — check spam too.',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 10, // Supabase email OTP length is 6–10 (project setting)
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: 'Code', counterText: ''),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => code.length >= 6 && !_busy ? _verify() : null,
        ),
        const SizedBox(height: HuxSpacing.lg),
        FilledButton(
          onPressed: code.length >= 6 && !_busy ? _verify : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm'),
        ),
        const SizedBox(height: HuxSpacing.md),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() => widget.authService.resendSignUpCode(widget.email),
                  done: 'New code sent — check your email.'),
          child: const Text('Send a new code'),
        ),
      ],
    );
  }
}
