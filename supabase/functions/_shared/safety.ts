// Server-side red-flag check for coach messages — the same phrases as the
// app's on-phone check (lib/core/coach/safety.dart; keep the two lists in
// step). The app already shows a help card instantly; this makes sure the
// REPLY itself always carries the right help numbers, even if the model
// misses it or an old/modified app skips its own check.

const EMERGENCY = [
  // English / romanised Hindi & Telugu
  "chest pain", "pain in my chest", "chest is hurting", "chest tight", "tightness in chest",
  "seene me dard", "seene mein dard", "chhati me dard", "chaati mein dard", "chathi noppi",
  "can't breathe", "cant breathe", "cannot breathe", "hard to breathe", "breathless at rest",
  "saans nahi", "saans lene me", "saans lene mein",
  "fainted", "passed out", "unconscious", "behosh",
  "face drooping", "slurred speech", "one side weak", "arm is numb", "left arm pain",
  "heart attack", "having a stroke", "stroke symptoms", "heat stroke", "heatstroke",
  "seizure", "fits aa", "heavy bleeding",
  "spo2 below 90", "oxygen below 90", "oxygen is 8",
  // Hindi (Devanagari)
  "सीने में दर्द", "छाती में दर्द", "सांस नहीं", "साँस नहीं", "बेहोश", "दिल का दौरा",
  // Telugu
  "ఛాతీ నొప్పి", "ఊపిరి ఆడటం లేదు", "స్పృహ తప్పి", "గుండెపోటు",
  // Tamil
  "நெஞ்சு வலி", "மூச்சு விட முடியவில்லை", "மாரடைப்பு",
  // Kannada
  "ಎದೆ ನೋವು", "ಉಸಿರಾಡಲು ಆಗುತ್ತಿಲ್ಲ", "ಪ್ರಜ್ಞೆ ತಪ್ಪಿ", "ಹೃದಯಾಘಾತ",
];

const SELF_HARM = [
  "suicide", "suicidal", "kill myself", "killing myself", "end my life", "end it all",
  "want to die", "wanna die", "better off dead", "no reason to live", "hurt myself",
  "harm myself", "self harm", "self-harm", "cut myself",
  "marna chahta", "marna chahti", "mar jaana chahta", "mar jana chahti", "jeena nahi",
  "khudkushi", "aatmahatya", "atmahatya", "chachipovali", "chanipovali",
  // Hindi
  "आत्महत्या", "खुदकुशी", "मरना चाहता", "मरना चाहती", "जीना नहीं",
  // Telugu
  "ఆత్మహత్య", "చనిపోవాలని",
  // Tamil
  "தற்கொலை", "சாக வேண்டும்",
  // Kannada
  "ಆತ್ಮಹತ್ಯೆ", "ಸಾಯಬೇಕು",
];

export type RedFlag = "emergency" | "selfHarm" | null;

export function redFlag(text: string): RedFlag {
  const t = text.toLowerCase().replace(/\s+/g, " ");
  if (SELF_HARM.some((p) => t.includes(p))) return "selfHarm";
  if (EMERGENCY.some((p) => t.includes(p))) return "emergency";
  return null;
}

/** A fixed help line put in FRONT of the model's reply. */
export function helpPrefix(flag: RedFlag): string {
  if (flag === "selfHarm") {
    return "You don't have to face this alone. Please call Tele-MANAS 14416 (free, 24x7, Indian languages), " +
      "or 112 if you might act on these thoughts right now.\n\n";
  }
  if (flag === "emergency") {
    return "This could be an emergency — please call 112 (or 108 for an ambulance) or go to the nearest " +
      "hospital now.\n\n";
  }
  return "";
}
