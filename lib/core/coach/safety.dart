/// On-phone safety check for coach messages. Runs BEFORE anything is
/// sent, so help numbers show instantly — even offline, and even if the
/// AI misses it. The AI is also told to handle these (see the backend
/// prompt); this is the second, independent layer.
///
/// Numbers (India): 112 = national emergency, 108 = ambulance,
/// Tele-MANAS 14416 / 1-800-891-4416 = free 24×7 government mental
/// health line in many Indian languages. Re-check before each release.
library;

enum SafetyKind { emergency, selfHarm }

class SafetyCard {
  final SafetyKind kind;
  final String title;
  final String body;

  /// Numbers to offer as tap-to-call buttons, first = most urgent.
  final List<({String label, String number})> calls;

  const SafetyCard({required this.kind, required this.title, required this.body, required this.calls});
}

class SafetyCheck {
  const SafetyCheck._();

  static const emergencyCard = SafetyCard(
    kind: SafetyKind.emergency,
    title: 'This could be an emergency',
    body: 'Chest pain, trouble breathing, fainting, or sudden weakness, numbness or slurred '
        'speech need a doctor now. Call 112 (or 108 for an ambulance), or go to the nearest '
        'hospital. Please don\'t wait for an app.',
    calls: [(label: 'Call 112', number: '112'), (label: 'Ambulance 108', number: '108')],
  );

  static const selfHarmCard = SafetyCard(
    kind: SafetyKind.selfHarm,
    title: "You don't have to face this alone",
    body: 'Talking to someone helps. Tele-MANAS is free, 24×7 and speaks many Indian languages. '
        'If you might act on these thoughts right now, call 112.',
    calls: [
      (label: 'Tele-MANAS 14416', number: '14416'),
      (label: '1-800-891-4416', number: '18008914416'),
      (label: 'Emergency 112', number: '112'),
    ],
  );

  // Lower-case phrases. English plus common Hinglish / Hindi / Telugu
  // romanisations people actually type.
  static const _emergency = [
    'chest pain', 'pain in my chest', 'chest is hurting', 'chest tight', 'tightness in chest',
    'seene me dard', 'seene mein dard', 'chhati me dard', 'chaati mein dard', 'chathi noppi',
    "can't breathe", 'cant breathe', 'cannot breathe', 'hard to breathe', 'breathless at rest',
    'saans nahi', 'saans lene me', 'saans lene mein',
    'fainted', 'passed out', 'unconscious', 'behosh',
    'face drooping', 'slurred speech', 'one side weak', 'arm is numb', 'left arm pain',
    'heart attack', 'having a stroke', 'stroke symptoms', 'heat stroke', 'heatstroke',
    'seizure', 'fits aa', 'heavy bleeding',
    'spo2 below 90', 'oxygen below 90', 'oxygen is 8',
  ];

  static const _selfHarm = [
    'suicide', 'suicidal', 'kill myself', 'killing myself', 'end my life', 'end it all',
    'want to die', 'wanna die', 'better off dead', 'no reason to live', 'hurt myself',
    'harm myself', 'self harm', 'self-harm', 'cut myself',
    'marna chahta', 'marna chahti', 'mar jaana chahta', 'mar jana chahti', 'jeena nahi',
    'khudkushi', 'aatmahatya', 'atmahatya', 'chachipovali', 'chanipovali',
  ];

  /// The card to show for [text], or null. Self-harm wins over
  /// emergency (it needs the specific helpline).
  static SafetyCard? check(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (_selfHarm.any(t.contains)) return selfHarmCard;
    if (_emergency.any(t.contains)) return emergencyCard;
    return null;
  }
}
