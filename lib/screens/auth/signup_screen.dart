/// Create an account with email/password, Google, or Apple.
library;

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/hux_tokens.dart';
import 'auth_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  final AuthService authService;

  const SignUpScreen({super.key, required this.authService});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Real, checked-before-submit validation — never just left to the
  /// backend to reject, so a mismatched confirm password gets an
  /// immediate, specific message instead of a generic API error.
  String? get _validationError {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) return null;
    if (_passwordController.text.length < 6) return 'Password must be at least 6 characters.';
    if (_passwordController.text != _confirmController.text) return 'Passwords don\'t match.';
    return null;
  }

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmController.text.isNotEmpty &&
      _validationError == null &&
      !_busy;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (widget.authService.currentUser != null) {
        // Email confirmation is off (Supabase dashboard setting): sign-up
        // already started a session. app.dart's auth-state gate swaps
        // the (hidden) home route to AppShell on its own, but
        // WelcomeScreen pushed Login/SignUp on top of that route, so
        // popping back to it is what actually makes AppShell visible.
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      // Email confirmation IS required: no session yet, so tell the user
      // where to look next rather than leaving this form looking like it
      // silently did nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check your email to confirm your account, then log in.')),
      );
      Navigator.of(context).pop();
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
      headline: 'Create your account',
      subtitle: 'A few days of data and HUX starts reading your own patterns.',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: HuxSpacing.md),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
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
          decoration: const InputDecoration(labelText: 'Confirm password'),
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
              : const Text('Sign Up'),
        ),
        const SizedBox(height: HuxSpacing.xl),
        AuthSocialRow(
          busy: _busy,
          onGoogle: () => _run(widget.authService.signInWithGoogle),
          onApple: () => _run(widget.authService.signInWithApple),
        ),
        const SizedBox(height: HuxSpacing.xl),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: const [
                  TextSpan(text: 'Already have an account? '),
                  TextSpan(text: 'Log In', style: TextStyle(color: HuxColors.accentPink)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() => _run(() => widget.authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ));
}
