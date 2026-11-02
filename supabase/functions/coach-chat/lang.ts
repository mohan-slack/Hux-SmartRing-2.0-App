// Which language (and script) is the user writing in right now?
// Indian users often type their own language in English letters
// ("Baku chala akali indi" = Telugu). The model guesses poorly on short
// romanized text and drifts into Hindi, so we detect it here and tell
// the model plainly. Pure function, no I/O. Tests: lang_test.ts.

export type LangCode =
  | "english"
  | "hindi"
  | "hinglish"
  | "telugu"
  | "tenglish"
  | "tamil"
  | "tanglish"
  | "kannada"
  | "kanglish"
  | "malayalam"
  | "manglish"
  | "bengali"
  | "marathi"
  | "gujarati"
  | "punjabi";

const SCRIPTS: [RegExp, LangCode][] = [
  [/[ఀ-౿]/, "telugu"],
  [/[஀-௿]/, "tamil"],
  [/[ಀ-೿]/, "kannada"],
  [/[ഀ-ൿ]/, "malayalam"],
  [/[ঀ-৿]/, "bengali"],
  [/[઀-૿]/, "gujarati"],
  [/[਀-੿]/, "punjabi"],
  [/[ऀ-ॿ]/, "hindi"], // Devanagari: Hindi or Marathi; see below
];

// Everyday words people type in English letters. Words shared between
// languages (illa, amma, ra) are left out on purpose.
const ROMAN: Record<"tenglish" | "hinglish" | "tanglish" | "kanglish" | "manglish", string[]> = {
  tenglish: [
    "em", "emi", "enti", "emiti", "ela", "elaa", "chala", "chaala", "akali", "aakali", "tinali", "tinaali",
    "tinamantaru", "tinochha", "tinocha", "tinte", "tinna", "tinnanu", "tindi", "cheyyali", "cheyyandi",
    "cheyali", "chey", "nidra", "padukovali", "padukunna", "nenu", "naaku", "naku", "meeru", "miru", "kadha",
    "kada", "ledu", "ledhu", "undi", "unnanu", "unnadi", "bagundi", "baagundi", "baga", "baaga", "ippudu",
    "eppudu", "epudu", "enduku", "kavali", "kaavali", "vaddu", "annam", "koora", "kura", "pappu", "perugu",
    "roju", "nadaka", "nadavali", "cheppu", "cheppandi", "ayyindi", "avutundi", "inka", "mari", "baku", "babu",
    "bava", "andi", "vachindi", "tagali", "neellu", "ikkada", "akkada", "kuda", "kooda", "konchem", "koncham",
    "emaina", "evaru", "ante", "anni", "indi", "ayindi", "raavatledu", "avvatledu", "cheyyanu", "raatri", "ratri", "podduna", "sayantram", "nooru", "noppi",
  ],
  hinglish: [
    "kya", "kaise", "kyu", "kyun", "kuch", "nahi", "nahin", "hai", "hain", "mujhe", "mera", "meri", "khana",
    "khaun", "khau", "neend", "bahut", "bohot", "thoda", "abhi", "aaj", "chahiye", "karna", "karu", "karun",
    "bhook", "bhukh", "sona", "chalna", "theek", "thik", "accha", "acha", "yaar", "kitna", "kab", "kaun", "aur",
    "lekin", "matlab", "hoon", "hu", "tha", "thi", "raat", "subah", "shaam", "kal", "pet", "dard",
  ],
  tanglish: [
    "enna", "epdi", "eppadi", "saapdu", "saapadu", "saapidalam", "sapadu", "saapten", "romba", "pasi",
    "thookam", "thoongu", "thoongala", "naan", "enakku", "neenga", "irukku", "irukka", "venum", "vendam",
    "inniku", "innaikku", "ippo", "nalla", "konjam", "panna", "pannalama", "sollunga", "machan", "seri",
    "aamaa", "theriyala", "kaalaila", "raathiri", "vali",
  ],
  kanglish: [
    "enu", "yenu", "hege", "hegide", "oota", "oota", "nidde", "nanage", "nanna", "neevu", "beku", "beda",
    "tumba", "swalpa", "ide", "maadi", "maadbeku", "hasivu", "eega", "ivattu", "chennagide", "guru", "maga",
    "gottilla", "aaytu", "bartini", "hogi", "raatri", "belagge", "novu",
  ],
  manglish: [
    "enthu", "entha", "engane", "kazhikkan", "kazhikkanam", "kazhichu", "vishakkunnu", "vishappu", "urakkam",
    "njan", "enikku", "ningal", "venam", "venda", "valare", "kurachu", "ippol", "innu", "nannayi", "alle",
    "undo", "cheyyanam", "cheyyam", "sheri", "pinne", "raathri", "vedana",
  ],
};

const LABELS: Record<LangCode, string> = {
  english: "English",
  hindi: "Hindi in Devanagari script",
  hinglish: "Hinglish: Hindi written in English letters, mixed with simple English",
  telugu: "Telugu in Telugu script",
  tenglish: "Telugu written in English letters (Tenglish), mixed with simple English",
  tamil: "Tamil in Tamil script",
  tanglish: "Tamil written in English letters (Tanglish), mixed with simple English",
  kannada: "Kannada in Kannada script",
  kanglish: "Kannada written in English letters, mixed with simple English",
  malayalam: "Malayalam in Malayalam script",
  manglish: "Malayalam written in English letters (Manglish), mixed with simple English",
  bengali: "Bengali in Bengali script",
  marathi: "Marathi in Devanagari script",
  gujarati: "Gujarati in Gujarati script",
  punjabi: "Punjabi in Gurmukhi script",
};

export function languageLabel(code: LangCode): string {
  return LABELS[code];
}

const MARATHI = ["आहे", "काय", "मला", "नाही", "आणि", "झोप", "जेवण", "कसं", "करू"];

/** Best guess for [text]; null when it's too short or unclear to say. */
export function detectLanguage(text: string): LangCode | null {
  const t = text.trim();
  if (!t) return null;
  for (const [re, code] of SCRIPTS) {
    if (re.test(t)) {
      if (code === "hindi" && MARATHI.some((w) => t.includes(w))) return "marathi";
      return code;
    }
  }
  const words = t.toLowerCase().normalize("NFKD").replace(/[^a-z\s]/g, " ").split(/\s+/).filter(Boolean);
  if (!words.length) return null;
  let best: LangCode | null = null;
  let bestHits = 0;
  for (const [code, list] of Object.entries(ROMAN) as [LangCode, string[]][]) {
    const set = new Set(list);
    const hits = words.filter((w) => set.has(w)).length;
    if (hits > bestHits) {
      best = code;
      bestHits = hits;
    }
  }
  // One hit is enough in a short message ("em tinali?"), two in a long one.
  if (best && (bestHits >= 2 || (bestHits === 1 && words.length <= 4))) return best;
  return words.length >= 3 ? "english" : null;
}
