/// The real [AuthService]: Supabase's GoTrue backend, Google Sign-In,
/// and Sign in with Apple. This is the ONLY file that imports any of
/// those three packages — everything above [AuthService] stays free of
/// them, same containment rule [AizoBleRingAdapter] follows for its one
/// BLE plugin.
library;

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
        await _client.auth.signUp(email: email, password: password);
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
        if (SupabaseConfig.googleWebClientId.isEmpty) {
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
        await _client.auth.verifyOTP(email: email, token: code, type: supa.OtpType.recovery);
        await _client.auth.updateUser(supa.UserAttributes(password: newPassword));
      });

  @override
  Future<void> signOut() => _guard(() async {
        await _googleSignIn.signOut();
        await _client.auth.signOut();
      });
}
