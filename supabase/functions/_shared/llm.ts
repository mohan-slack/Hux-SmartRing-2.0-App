// One place that talks to the AI provider, so switching provider is a
// secret change, not a code change.
//
//   AI_PROVIDER = "groq" (default) | "anthropic"
//   groq:      GROQ_API_KEY      (OpenAI-compatible Chat Completions API)
//   anthropic: ANTHROPIC_API_KEY (Messages API)
//
// Model ids come from the caller (COACH_MODEL / MEAL_MODEL secrets).

export type ChatMsg = { role: "user" | "assistant"; content: string };

export interface ChatRequest {
  model: string;
  system: string;
  messages: ChatMsg[];
  maxTokens: number;
  /** Optional image for the LAST user message (meal photos). */
  image?: { base64: string; mediaType: string };
  temperature?: number;
}

function provider(): "groq" | "anthropic" {
  return (Deno.env.get("AI_PROVIDER") ?? "groq").toLowerCase() === "anthropic" ? "anthropic" : "groq";
}

/** Returns the model's text reply. Throws "model error <status>" or "server not configured". */
export async function chat(req: ChatRequest): Promise<string> {
  return provider() === "anthropic" ? anthropicChat(req) : groqChat(req);
}

async function fail(res: Response, label: string): Promise<never> {
  // Provider error text (no user data, no key) helps fix setup issues.
  const detail = (await res.text()).slice(0, 300);
  console.error(`${label} error:`, res.status, detail);
  throw new Error(`model error ${res.status}`);
}

async function groqChat(req: ChatRequest): Promise<string> {
  const key = Deno.env.get("GROQ_API_KEY");
  if (!key || !req.model) throw new Error("server not configured");

  const msgs: unknown[] = [{ role: "system", content: req.system }];
  req.messages.forEach((m, i) => {
    const isLast = i === req.messages.length - 1;
    if (isLast && req.image && m.role === "user") {
      msgs.push({
        role: "user",
        content: [
          { type: "text", text: m.content },
          { type: "image_url", image_url: { url: `data:${req.image.mediaType};base64,${req.image.base64}` } },
        ],
      });
    } else {
      msgs.push({ role: m.role, content: m.content });
    }
  });

  const body: Record<string, unknown> = {
    model: req.model,
    messages: msgs,
    max_completion_tokens: req.maxTokens,
    temperature: req.temperature ?? 0.6,
  };
  // gpt-oss models think before answering; keep that short and hidden.
  if (req.model.startsWith("openai/gpt-oss")) {
    body.reasoning_effort = "low";
    body.include_reasoning = false;
  }

  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) await fail(res, "groq");
  const data = await res.json();
  const text = data?.choices?.[0]?.message?.content;
  // Some open models (e.g. Qwen) may put their thinking in <think>…</think>
  // inside the answer; never show that to users or let it break JSON parsing.
  return typeof text === "string" ? text.replace(/<think>[\s\S]*?<\/think>/g, "").trim() : "";
}

async function anthropicChat(req: ChatRequest): Promise<string> {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key || !req.model) throw new Error("server not configured");

  const messages = req.messages.map((m, i) => {
    const isLast = i === req.messages.length - 1;
    if (isLast && req.image && m.role === "user") {
      return {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: req.image.mediaType, data: req.image.base64 } },
          { type: "text", text: m.content },
        ],
      };
    }
    return m;
  });

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: req.model, max_tokens: req.maxTokens, system: req.system, messages }),
  });
  if (!res.ok) await fail(res, "anthropic");
  const data = await res.json();
  return (data?.content ?? [])
    .filter((c: { type: string }) => c.type === "text")
    .map((c: { text: string }) => c.text)
    .join("")
    .trim();
}
