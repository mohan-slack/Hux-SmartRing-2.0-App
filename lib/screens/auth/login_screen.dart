/// Sign in with email/password, Google, or Apple. Talks only to
/// [AuthService] — never a Supabase type — same containment rule every
/// other screen in this app follows for its own backing service.
library;

import 'package:flutter/material.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/hux_tokens.dart';
import 'auth_scaffold.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _emailController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty && !_busy;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      // A successful sign-in flips app.dart's auth-state gate to
      // AppShell underneath — but WelcomeScreen pushed this screen on
      // top, so that swap is invisible until this pushed route pops
      // back to the (now-AppShell) home route. Checking currentUser
      // (rather than popping unconditionally) keeps a cancelled
      // Google/Apple picker — which returns normally, no exception,
      // but no session either — from popping this screen for nothing.
      if (widget.authService.currentUser != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
      headline: 'Welcome back',
      subtitle: 'Sign in to see today\'s readout.',
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
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSubmit ? _submit() : null,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ForgotPasswordScreen(authService: widget.authService),
                    )),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: HuxSpacing.md),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Log In'),
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
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SignUpScreen(authService: widget.authService),
                    )),
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: const [
                  TextSpan(text: "Don't have an account? "),
                  TextSpan(text: 'Sign Up', style: TextStyle(color: HuxColors.accentPink)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() => _run(() => widget.authService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ));
}
