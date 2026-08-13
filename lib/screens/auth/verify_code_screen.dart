/// Step 2 of password recovery: the code sent to [email], plus a new
/// password, verified and applied in one call — see
/// [AuthService.verifyPasswordResetCode]'s doc comment for why this
/// isn't two separate steps (a wrong code must never leave the account
/// half-reset).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/hux_tokens.dart';
import 'auth_scaffold.dart';

/// Matches the "OTP Expiration" (seconds) setting on the Supabase
/// project's Auth settings — purely a countdown display, since the
/// server is what actually enforces expiry. If that dashboard setting
/// changes, update this to match or the countdown will mislead.
const _codeValiditySeconds = 90;

class VerifyCodeScreen extends StatefulWidget {
  final AuthService authService;
  final String email;

  const VerifyCodeScreen({super.key, required this.authService, required this.email});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _resending = false;
  String? _error;
  Timer? _countdown;
  int _secondsLeft = _codeValiditySeconds;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  // A ticking Timer.periodic, not a repeating animation — the codebase's
  // "every animation completes" rule is about the animation system
  // (pumpAndSettle-safety); this is a real, finite countdown that stops
  // itself dead at zero, same shape as HuxPulseDot's damped halo.
  void _startCountdown() {
    _countdown?.cancel();
    setState(() => _secondsLeft = _codeValiditySeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  String get _countdownLabel {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _resendCode() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await widget.authService.sendPasswordResetCode(widget.email);
      if (!mounted) return;
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New code sent — check your email.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? get _validationError {
    if (_passwordController.text.isEmpty) return null;
    if (_passwordController.text.length < 6) return 'Password must be at least 6 characters.';
    if (_passwordController.text != _confirmController.text) return 'Passwords don\'t match.';
    return null;
  }

  bool get _canSubmit =>
      _codeController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmController.text.isNotEmpty &&
      _validationError == null &&
      !_busy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.verifyPasswordResetCode(
        email: widget.email,
        code: _codeController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset — you\'re signed in.')),
      );
      // verifyPasswordResetCode leaves the user signed in (GoTrue starts
      // a session on a successful OTP verify) — pop back to whichever
      // screen is under this whole recovery flow; the auth-state gate
      // in app.dart takes it from there.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      headline: 'Enter your code',
      subtitle: 'Sent to ${widget.email}.',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          // Supabase's recovery OTP is 8 digits (GoTrue's default for the
          // `recovery` type, unlike the 6-digit signup/magic-link OTP) —
          // capping this at 6 silently truncated real codes.
          maxLength: 8,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: 'Verification code', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: HuxSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _secondsLeft > 0 ? 'Code expires in $_countdownLabel' : 'Code has expired',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _secondsLeft > 10 ? HuxColors.mutedText : HuxColors.rundown,
                  ),
            ),
            TextButton(
              onPressed: (_secondsLeft > 0 || _resending) ? null : _resendCode,
              child: _resending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Resend code'),
            ),
          ],
        ),
        const SizedBox(height: HuxSpacing.md),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: HuxSpacing.md),
        TextField(
          controller: _confirmController,
          obscureText: _obscure,
          decoration: const InputDecoration(labelText: 'Confirm new password'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSubmit ? _submit() : null,
        ),
        if (_validationError != null) ...[
          const SizedBox(height: HuxSpacing.sm),
          Text(_validationError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HuxColors.rundown)),
        ],
        const SizedBox(height: HuxSpacing.lg),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}
