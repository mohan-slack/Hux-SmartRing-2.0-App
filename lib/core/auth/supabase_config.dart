/// Supabase project connection — the ONE place these values are read.
///
/// Values come from `.env` at BUILD time:
///   flutter run --dart-define-from-file=.env
/// (see `.env.example`). Nothing is hard-coded, so switching Supabase
/// projects/accounts = edit `.env`, rebuild. `.env` is git-ignored.
///
/// The anon/publishable key below is NOT a secret: Supabase's own model
/// is that this key is safe to ship inside a client app (unlike a
/// service-role key, which must never appear here). Access control is
/// enforced server-side by Postgres Row Level Security policies, not by
/// hiding this key. See https://supabase.com/docs/guides/api/api-keys.
library;

import 'dart:io';

class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// True when the build was given a Supabase project (see main.dart,
  /// which shows a clear setup error instead of crashing when false).
  static bool get isConfigured => url.startsWith('https://') && anonKey.isNotEmpty;

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
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// The iOS-type OAuth client ID (Google Cloud → Credentials → "iOS"
  /// client). Required on iOS: without it — and without its REVERSED
  /// form added as a URL scheme in ios/Runner/Info.plist
  /// (CFBundleURLTypes) — the Google SDK crashes the app natively.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Whether to offer "Continue with Google" on this device at all.
  static bool get googleSignInEnabled =>
      googleWebClientId.isNotEmpty && (!Platform.isIOS || googleIosClientId.isNotEmpty);

  /// Sign in with Apple is offered on iOS only (on Android it needs a
  /// separate web flow this app doesn't set up, and fails).
  static bool get appleSignInEnabled => Platform.isIOS;

  /// Optional Open-Meteo commercial key (free tier is non-commercial).
  static const openMeteoApiKey = String.fromEnvironment('OPEN_METEO_API_KEY');
}
