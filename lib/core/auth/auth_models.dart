/// Auth data contract — deliberately thin. Screens and the rest of the
/// app see only [AuthUser]/[AuthException], never a Supabase type
/// directly, same "one interface, swappable backend" rule [RingAdapter]
/// already follows for ring hardware.

/// The signed-in person, as far as this app needs to know: enough to
/// greet them and to gate access, nothing else.
class AuthUser {
  final String id;
  final String? email;

  const AuthUser({required this.id, this.email});
}

/// A failed auth operation, with a message already safe to show a user
/// (see each [AuthService] implementation for how backend-specific
/// errors get translated here).
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
