/// Step 1 of password recovery: send a one-time code to the account's
/// email. Step 2 (entering the code + a new password) is
/// [VerifyCodeScreen].
library;

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/hux_tokens.dart';
import 'auth_scaffold.dart';
import 'verify_code_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthService authService;

  const ForgotPasswordScreen({super.key, required this.authService});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _busy = false;
  String? _error;
  // Supabase's resetPasswordForEmail always succeeds, whether or not the
  // email belongs to a real account — revealing that difference here
  // would let anyone probe which emails have HUX accounts (a user-
  // enumeration attack). So a successful call only means "a code is on
  // its way IF this email is registered," never a guarantee — this
  // screen states that plainly instead of silently jumping to the
  // verify-code screen as if a code is certainly coming.
  String? _sentTo;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.sendPasswordResetCode(email);
      if (!mounted) return;
      setState(() => _sentTo = email);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterCode() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VerifyCodeScreen(authService: widget.authService, email: _sentTo!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    if (sentTo != null) {
      return AuthScaffold(
        headline: 'Check your email',
        subtitle: "If an account exists for $sentTo, a reset code is on its way. "
            "It can take a minute to arrive — check spam too.",
        children: [
          FilledButton(
            onPressed: _enterCode,
            child: const Text('Enter Code'),
          ),
          const SizedBox(height: HuxSpacing.md),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => setState(() => _sentTo = null),
              child: const Text('Use a different email'),
            ),
          ),
        ],
      );
    }
    return AuthScaffold(
      headline: 'Reset your password',
      subtitle: "We'll send a code to your email to continue.",
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _emailController.text.trim().isNotEmpty ? _sendCode() : null,
        ),
        const SizedBox(height: HuxSpacing.lg),
        FilledButton(
          onPressed: (_emailController.text.trim().isEmpty || _busy) ? null : _sendCode,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send Code'),
        ),
      ],
    );
  }
}
