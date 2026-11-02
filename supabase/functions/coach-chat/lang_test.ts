// deno test supabase/functions/coach-chat/lang_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { detectLanguage } from "./lang.ts";

Deno.test("romanized Telugu", () => {
  assertEquals(detectLanguage("Baku chala akali indi em tinamantaru?"), "tenglish");
  assertEquals(detectLanguage("nidra raavatledu em cheyyali"), "tenglish");
});
Deno.test("Hinglish", () => assertEquals(detectLanguage("mujhe neend nahi aa rahi kya karu"), "hinglish"));
Deno.test("Tanglish", () => assertEquals(detectLanguage("romba pasi ippo enna saapdu"), "tanglish"));
Deno.test("Kannada in English letters", () => assertEquals(detectLanguage("tumba hasivu enu oota maadli"), "kanglish"));
Deno.test("Manglish", () => assertEquals(detectLanguage("valare vishakkunnu enthu kazhikkanam"), "manglish"));
Deno.test("scripts", () => {
  assertEquals(detectLanguage("నాకు ఆకలిగా ఉంది"), "telugu");
  assertEquals(detectLanguage("मुझे भूख लगी है"), "hindi");
  assertEquals(detectLanguage("எனக்கு பசிக்குது"), "tamil");
});
Deno.test("English", () => assertEquals(detectLanguage("what should I eat for dinner tonight"), "english"));
