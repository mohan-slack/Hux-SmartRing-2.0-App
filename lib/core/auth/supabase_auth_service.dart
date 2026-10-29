/// The real [AuthService]: Supabase's GoTrue backend, Google Sign-In,
/// and Sign in with Apple. This is the ONLY file that imports any of
/// those three packages — everything above [AuthService] stays free of
/// them, same containment rule the ring adapters follow for their plugins.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'auth_models.dart';
import 'auth_service.dart';
import 'supabase_config.dart';

class SupabaseAuthService implements AuthService {
  final supa.SupabaseClient _client;
  final GoogleSignIn _googleSignIn;

  SupabaseAuthService({supa.SupabaseClient? client, GoogleSignIn? googleSignIn})
      : _client = client ?? supa.Supabase.instance.client,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email'],
              // iOS needs its own client ID (see SupabaseConfig).
              clientId: Platform.isIOS && SupabaseConfig.googleIosClientId.isNotEmpty
                  ? SupabaseConfig.googleIosClientId
                  : null,
              serverClientId: SupabaseConfig.googleWebClientId.isEmpty ? null : SupabaseConfig.googleWebClientId,
            );

  AuthUser? _toAuthUser(supa.User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((state) => _toAuthUser(state.session?.user));

  @override
  AuthUser? get currentUser => _toAuthUser(_client.auth.currentUser);

  /// Every GoTrue call goes through this so a raw [supa.AuthException]
  /// message (already written for end users by Supabase) becomes this
  /// app's own [AuthException] — never a Supabase type escaping this
  /// file — and anything unexpected still gets a calm, non-technical
  /// message rather than a raw stack-trace string.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthException {
      // Already OUR exception, with a specific message written for this
      // exact case (e.g. "Google sign-in isn't set up yet") — must be
      // rethrown as-is, before the catch-all below, or it gets silently
      // overwritten with the generic fallback message.
      rethrow;
    } on supa.AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      throw const AuthException("That didn't work — check your connection and try again.");
    }
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) => _guard(() async {
        await _client.auth.signInWithPassword(email: email, password: password);
      });

  @override
  Future<void> signUpWithEmail({required String email, required String password}) => _guard(() async {
        final res = await _client.auth.signUp(email: email, password: password);
        // Supabase doesn't reveal existing accounts: signing up again with a
        // registered email "succeeds" but sends NO email and returns a user
        // with no identities. Say so, instead of waiting for a code that
        // never comes.
        final identities = res.user?.identities;
        if (res.session == null && identities != null && identities.isEmpty) {
          throw const AuthException(
              'This email already has a HUX account. Please log in, or use "Forgot password".');
        }
      });

  @override
  Future<void> signInWithGoogle() => _guard(() async {
        // Calling into the native Google Sign-In SDK with NO client ID
        // configured doesn't throw a catchable Dart exception on iOS —
        // it's a hard native crash (the whole app terminates, seen as
        // macOS's "Runner quit unexpectedly" dialog on a simulator).
        // Refuse before ever reaching the plugin, so an unconfigured
        // build fails as a normal on-screen error instead of a crash.
        // See SupabaseConfig.googleWebClientId's doc comment.
        if (!SupabaseConfig.googleSignInEnabled) {
          throw const AuthException(
              "Google sign-in isn't set up yet — see SupabaseConfig.googleWebClientId in the README.");
        }
        final account = await _googleSignIn.signIn();
        if (account == null) {
          // The user closed the picker — a normal cancellation, not a
          // failure worth an error message.
          return;
        }
        final googleAuth = await account.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null) {
          throw const AuthException(
              "Google didn't return a token — try again, or check the app's Google sign-in setup.");
        }
        await _client.auth.signInWithIdToken(
          provider: supa.OAuthProvider.google,
          idToken: idToken,
          accessToken: googleAuth.accessToken,
        );
      });

  @override
  Future<void> signInWithApple() => _guard(() async {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [AppleIDAuthorizationScopes.email],
        );
        final idToken = credential.identityToken;
        if (idToken == null) {
          throw const AuthException("Apple didn't return a token — try again.");
        }
        await _client.auth.signInWithIdToken(
          provider: supa.OAuthProvider.apple,
          idToken: idToken,
        );
      });

  @override
  Future<void> verifySignUpCode({required String email, required String code}) => _guard(() async {
        await _client.auth.verifyOTP(email: email, token: code, type: supa.OtpType.signup);
      });

  @override
  Future<void> resendSignUpCode(String email) => _guard(() async {
        await _client.auth.resend(type: supa.OtpType.signup, email: email);
      });

  @override
  Future<void> sendPasswordResetCode(String email) => _guard(() async {
        await _client.auth.resetPasswordForEmail(email);
      });

  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _guard(() async {
        // verifyOTP SIGNS THE USER IN. If the password update then fails,
        // sign back out so they aren't left logged in without the new
        // password they think they set.
        await _client.auth.verifyOTP(email: email, token: code, type: supa.OtpType.recovery);
        try {
          await _client.auth.updateUser(supa.UserAttributes(password: newPassword));
        } catch (_) {
          try {
            await _client.auth.signOut();
          } catch (_) {
            // Best-effort: the error below is what the user needs to see.
          }
          throw const AuthException(
              "Your code worked, but the new password couldn't be saved. "
              'Please request a new code and try again.');
        }
      });

  @override
  Future<void> signOut() => _guard(() async {
        // Supabase first: that is the session that actually matters. The
        // Google sign-out is best-effort (it throws when Google sign-in
        // was never configured or used) and must never block sign-out.
        await _client.auth.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {
          // Best-effort: Supabase session is already gone.
        }
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        final user = _client.auth.currentUser;
        if (user == null) {
          throw const AuthException('Please sign in again, then delete your account.');
        }

        // Sign in with Apple: Apple asks apps to REVOKE the user's Apple
        // token on deletion. That needs a fresh authorization code, so
        // iOS shows the Apple sheet once more. If the user cancels, we
        // still delete (they can remove HUX in iOS Settings → Apple ID).
        String? appleCode;
        final providers = <Object?>[
          ...?(user.appMetadata['providers'] as List?),
          user.appMetadata['provider'],
        ];
        if (providers.contains('apple') && defaultTargetPlatform == TargetPlatform.iOS) {
          try {
            final credential = await SignInWithApple.getAppleIDCredential(scopes: const []);
            appleCode = credential.authorizationCode;
          } catch (_) {
            // Cancelled or unavailable: delete without revocation.
          }
        }

        final response = await _client.functions.invoke(
          'delete-account',
          body: {if (appleCode != null) 'appleAuthorizationCode': appleCode},
        );
        final data = response.data;
        if (data is! Map || data['deleted'] != true) {
          throw const AuthException("Couldn't delete your account. Please try again.");
        }

        try {
          await _googleSignIn.disconnect(); // also removes HUX's Google access
        } catch (_) {
          // Best-effort: not signed in with Google, or not configured.
        }
      });
}
