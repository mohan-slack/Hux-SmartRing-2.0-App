/// Supabase project connection — the ONE place these two values live.
///
/// The anon/publishable key below is NOT a secret: Supabase's own model
/// is that this key is safe to ship inside a client app (unlike a
/// service-role key, which must never appear here). Access control is
/// enforced server-side by Postgres Row Level Security policies, not by
/// hiding this key. See https://supabase.com/docs/guides/api/api-keys.
library;

class SupabaseConfig {
  const SupabaseConfig._();

  static const url = 'https://zhidrdwrrohifhqarpkb.supabase.co';
  static const anonKey = 'sb_publishable_mmes93MDNRsidfnKT6QhQg_Drgy6gfa';

  /// Google Sign-In's WEB client ID (not the iOS/Android one) — passed
  /// as `serverClientId` so the ID token's audience is something
  /// Supabase can verify. Get this from Google Cloud Console (APIs &
  /// Services > Credentials > OAuth 2.0 Client IDs > the "Web client"
  /// entry), paste it here, then enable the Google provider in the
  /// Supabase dashboard (Authentication > Providers) with the SAME
  /// client ID. [SupabaseAuthService.signInWithGoogle] refuses to call
  /// the native SDK at all while this is empty — see its doc comment
  /// for why (an unconfigured call crashes the whole app on iOS, not a
  /// catchable Dart error).
  ///
  /// This web client ID alone is NOT enough to make the iOS build work
  /// end to end — iOS additionally needs its OWN iOS-type OAuth client
  /// ID (a second, separate ID from Google Cloud Console) registered as
  /// a URL scheme in `ios/Runner/Info.plist` (`CFBundleURLTypes`, using
  /// the client ID's REVERSED form, e.g.
  /// `com.googleusercontent.apps.XXXX`) — see
  /// https://pub.dev/packages/google_sign_in#ios-integration. Android
  /// needs its own separate setup (`google-services.json`) per
  /// https://pub.dev/packages/google_sign_in#android-integration.
  /// Neither is done here — this repo has no Google Cloud project
  /// credentials to add them with.
  static const googleWebClientId = '';
}
