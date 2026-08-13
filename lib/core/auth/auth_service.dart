/// The wall for authentication — the one interface the app talks to.
/// Never a Supabase/Firebase/etc. type directly outside this file's one
/// real implementation ([SupabaseAuthService]). Same rule as
/// [RingAdapter] for ring hardware: swapping the backend later means
/// writing one new class here, not touching a single screen.
library;

import 'auth_models.dart';

abstract class AuthService {
  /// Fires immediately with the current user (or null) on every
  /// listen, then again whenever sign-in/sign-out happens — the ONE
  /// thing [app.dart]'s auth gate watches to decide which screen to
  /// show.
  Stream<AuthUser?> get authStateChanges;

  AuthUser? get currentUser;

  Future<void> signInWithEmail({required String email, required String password});

  Future<void> signUpWithEmail({required String email, required String password});

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  /// Starts password recovery: sends a one-time code to [email].
  Future<void> sendPasswordResetCode(String email);

  /// Completes password recovery: verifies [code] and sets [newPassword]
  /// in one step, so a wrong code never silently leaves a half-reset
  /// account.
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<void> signOut();
}
