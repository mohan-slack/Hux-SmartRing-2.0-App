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

  /// Confirms a new email/password account with the code from the
  /// "Confirm signup" email (needs `{{ .Token }}` in that Supabase
  /// template). Signs the user in on success.
  Future<void> verifySignUpCode({required String email, required String code});

  /// Sends the sign-up confirmation code again.
  Future<void> resendSignUpCode(String email);

  Future<void> signOut();

  /// Permanently deletes the account and everything linked to it on
  /// HUX's servers (Apple 5.1.1(v), Google Play account deletion, DPDP
  /// erasure). Throws [AuthException] with a user-safe message on
  /// failure; the user stays signed in so they can retry.
  Future<void> deleteAccount();
}
