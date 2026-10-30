/// The in-app privacy notice, in ONE place: the first-run consent screen,
/// the Privacy & account screen, and the hosted policy
/// (docs/legal/PRIVACY_POLICY.md) must all say the same thing.
///
/// Written for India's DPDP Act 2023 / DPDP Rules 2025 (itemised data,
/// purpose, how to withdraw, how to complain), Google Play's User Data
/// and Health apps policies, and Apple guideline 5.1. NOT legal advice —
/// have a lawyer review before launch. Bump [noticeVersion] whenever the
/// meaning changes: every user is asked to agree again.
library;

class LegalConfig {
  const LegalConfig._();

  // TODO(before launch): confirm these pages exist and the inbox is monitored.
  static const company = 'Viveon Gizit Private Limited';
  static const appName = 'HUX';
  static const privacyPolicyUrl = 'https://hux.co.in/privacy';
  static const termsUrl = 'https://hux.co.in/terms';
  static const deleteAccountUrl = 'https://hux.co.in/delete-account';

  /// Grievance / privacy contact (DPDP requires one to be published).
  static const privacyEmail = 'privacy@hux.co.in';

  /// Minimum age. Under DPDP, under-18s need verifiable parental
  /// consent; v1 is 18+ only.
  static const minAge = 18;
}

class DataUse {
  /// What data.
  final String what;

  /// Why HUX uses it.
  final String why;

  /// Where it goes.
  final String where;

  /// Only when the user turns the feature on.
  final bool optional;

  const DataUse({required this.what, required this.why, required this.where, this.optional = false});
}

class PrivacyNotice {
  const PrivacyNotice._();

  /// Change this when the notice's meaning changes (forces re-consent).
  // v2: names the AI provider (Groq, USA) and its retention.
  // v3: adds Cycle (period data, on this phone only).
  static const noticeVersion = '2026-11-v3';

  static const uses = <DataUse>[
    DataUse(
      what: 'Email and sign-in details',
      why: 'To create your account and keep it secure',
      where: 'HUX account service (Supabase)',
    ),
    DataUse(
      what: 'Health readings you allow: steps, heart rate, HRV, sleep, SpO₂, calories, breathing rate',
      why: 'To show your charge, sleep, trends, streaks and plans',
      where: 'Read from Apple Health / Health Connect and kept on this phone only',
    ),
    DataUse(
      what: 'Your answers, journal, meals, plans and settings',
      why: 'To personalise the app',
      where: 'On this phone only',
    ),
    DataUse(
      what: 'Period dates, flow and symptoms — only if you turn on Cycle',
      why: 'To show your cycle phase, a likely range for your next period, and scores that compare you with your own same-phase days',
      where: 'On this phone only. The coach gets only the phase word, and only if you allow it in Cycle',
      optional: true,
    ),
    DataUse(
      what: 'A short summary of your numbers + your coach messages',
      why: 'To answer you in the HUX coach',
      where: 'HUX server, then Groq Inc. (AI provider, USA) to write the reply. Neither stores it '
          '(Groq zero data retention) — your chat stays on this phone',
      optional: true,
    ),
    DataUse(
      what: 'Meal photos you choose to analyse',
      why: 'To estimate protein and calories',
      where: 'HUX server, then Groq Inc. (AI provider, USA). Location data is removed first; '
          'neither stores the photo (Groq zero data retention)',
      optional: true,
    ),
    DataUse(
      what: 'The city you pick (not GPS)',
      why: 'For air-quality and heat alerts',
      where: 'Open-Meteo weather service',
      optional: true,
    ),
    DataUse(
      what: 'A coach reply you report, and the question before it',
      why: 'To review and improve the coach',
      where: 'HUX server, kept for 90 days',
      optional: true,
    ),
    DataUse(
      what: 'A daily count of coach messages',
      why: 'Fair-use limit',
      where: 'HUX server, kept for 7 days',
      optional: true,
    ),
  ];

  static const neverDone = <String>[
    'No ads, and your data is never sold.',
    'Health data is never used for advertising or credit/insurance decisions.',
    'No GPS location, contacts or microphone.',
  ];

  static const rights = <String>[
    'See and download a copy of your data (Privacy & account → Download my data).',
    'Turn off the coach, meal photos or alerts at any time — the feature simply stops.',
    'Delete everything on this phone, or delete your account, from inside the app.',
    'Questions or complaints: write to ${LegalConfig.privacyEmail}. If we can\'t resolve it, '
        'you may complain to the Data Protection Board of India.',
  ];
}
