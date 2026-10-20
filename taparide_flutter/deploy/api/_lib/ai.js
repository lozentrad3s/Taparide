// AI provider layer for Tap A Ride. Two providers behind one interface:
//   AI_PROVIDER=gemini (default)  -> Google Gemini REST API
//   AI_PROVIDER=anthropic         -> Claude via the official Anthropic SDK
//
// The conversation history is kept in each provider's NATIVE format and passed back
// verbatim on every turn (append-only), so tool calls and reasoning signatures stay valid.
import Anthropic from "@anthropic-ai/sdk";

export const provider = () => (process.env.AI_PROVIDER || "gemini").toLowerCase();

export class AiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ---------------------------------------------------------------- Gemini

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";
let cachedGeminiModel = null;

async function geminiModel() {
  if (process.env.GEMINI_MODEL) return process.env.GEMINI_MODEL;
  if (cachedGeminiModel) return cachedGeminiModel;
  // Pick the newest "flash" model this key can use (fast + vision + tools).
  const res = await fetch(`${GEMINI_BASE}/models?pageSize=200`, { headers: { "x-goog-api-key": geminiKey() } });
  if (!res.ok) throw new AiError(502, `Gemini model list failed (${res.status})`);
  const { models = [] } = await res.json();
  const usable = models
    .filter((m) => (m.supportedGenerationMethods || []).includes("generateContent"))
    .map((m) => m.name.replace(/^models\//, ""))
    .filter((n) => /^gemini-\d+(\.\d+)?-flash$/.test(n) || /^gemini-\d+(\.\d+)?-flash-latest$/.test(n));
  const version = (n) => parseFloat(n.match(/gemini-(\d+(?:\.\d+)?)/)[1]);
  usable.sort((a, b) => version(b) - version(a));
  cachedGeminiModel = usable[0] || "gemini-flash-latest";
  return cachedGeminiModel;
}

function geminiKey() {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new AiError(503, "The AI assistant is not configured yet (missing GEMINI_API_KEY).");
  return key;
}

function toGeminiSchema(schema) {
  // Gemini accepts an OpenAPI subset: drop keys it rejects.
  if (Array.isArray(schema)) return schema.map(toGeminiSchema);
  if (!schema || typeof schema !== "object") return schema;
  const out = {};
  for (const [k, v] of Object.entries(schema)) {
    if (k === "additionalProperties" || k === "$schema") continue;
    out[k] = toGeminiSchema(v);
  }
  return out;
}

async function geminiGenerate({ system, contents, tools, json }) {
  const model = await geminiModel();
  const body = {
    systemInstruction: { parts: [{ text: system }] },
    contents,
    generationConfig: { temperature: 0.3, maxOutputTokens: 4096 },
  };
  if (tools?.length) {
    body.tools = [{ functionDeclarations: tools.map((t) => ({ name: t.name, description: t.description, parameters: toGeminiSchema(t.input_schema) })) }];
  }
  if (json) {
    body.generationConfig.responseMimeType = "application/json";
    body.generationConfig.responseSchema = toGeminiSchema(json);
  }
  const res = await fetch(`${GEMINI_BASE}/models/${model}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey() },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new AiError(res.status === 429 ? 429 : 502, data?.error?.message || `Gemini error ${res.status}`);
  const candidate = data.candidates?.[0];
  if (!candidate?.content) {
    const reason = candidate?.finishReason || data.promptFeedback?.blockReason || "EMPTY";
    throw new AiError(502, `The AI returned no answer (${reason}).`);
  }
  return { model, content: candidate.content };
}

// ---------------------------------------------------------------- Anthropic

let anthropicClient = null;
const ANTHROPIC_MODEL = () => process.env.ANTHROPIC_MODEL || "claude-opus-5-5";

function anthropic() {
  if (!process.env.ANTHROPIC_API_KEY) throw new AiError(503, "The AI assistant is not configured yet (missing ANTHROPIC_API_KEY).");
  anthropicClient ??= new Anthropic();
  return anthropicClient;
}

async function anthropicCreate({ system, messages, tools, json, effort = "low" }) {
  try {
    const params = {
      model: ANTHROPIC_MODEL(),
      max_tokens: 16000,
      system,
      messages,
      output_config: { effort },
      // Server-side refusal fallback: if a safety classifier declines, the API retries on a fallback model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    };
    if (tools?.length) params.tools = tools;
    if (json) params.output_config.format = { type: "json_schema", schema: toAnthropicSchema(json) };
    const response = await anthropic().beta.messages.create(params);
    if (response.stop_reason === "refusal") throw new AiError(422, "The assistant couldn't help with that request.");
    return response;
  } catch (error) {
    if (error instanceof AiError) throw error;
    if (error instanceof Anthropic.RateLimitError) throw new AiError(429, "The assistant is busy. Try again in a moment.");
    if (error instanceof Anthropic.AuthenticationError) throw new AiError(503, "The Anthropic API key is invalid.");
    if (error instanceof Anthropic.BadRequestError) throw new AiError(400, error.message);
    if (error instanceof Anthropic.APIError) throw new AiError(502, `Anthropic error ${error.status}`);
    throw new AiError(502, "Could not reach the AI service.");
  }
}

/** JSON Schema for Anthropic structured outputs: nullable -> type union, objects closed. */
function toAnthropicSchema(schema) {
  if (Array.isArray(schema)) return schema.map(toAnthropicSchema);
  if (!schema || typeof schema !== "object") return schema;
  const out = {};
  for (const [k, v] of Object.entries(schema)) {
    if (k === "nullable") continue;
    out[k] = toAnthropicSchema(v);
  }
  if (schema.nullable && typeof schema.type === "string") out.type = [schema.type, "null"];
  if (out.type === "object" && out.additionalProperties === undefined) out.additionalProperties = false;
  return out;
}

// ---------------------------------------------------------------- chat turn (tool loop step)

/**
 * One assistant step. `history` is the provider-native transcript the client stored;
 * `input` is either {text, images?} (a user message) or {toolResults:[{id,name,result}]}.
 * Returns {history, text, toolCalls:[{id,name,args}], provider, model}.
 */
async function chatStepWith(p, { system, tools, history = [], input }) {
  if (p === "anthropic") {
    const messages = [...history];
    if (input.toolResults) {
      messages.push({
        role: "user",
        content: input.toolResults.map((r) => ({ type: "tool_result", tool_use_id: r.id, content: JSON.stringify(r.result ?? null), is_error: !!r.error })),
      });
    } else {
      messages.push({ role: "user", content: [...imageBlocksAnthropic(input.images), { type: "text", text: input.text }] });
    }
    const response = await anthropicCreate({ system, messages, tools });
    messages.push({ role: "assistant", content: response.content });
    const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("\n").trim();
    const toolCalls = response.content.filter((b) => b.type === "tool_use").map((b) => ({ id: b.id, name: b.name, args: b.input || {} }));
    return { history: messages, text, toolCalls, provider: p, model: response.model };
  }

  const contents = [...history];
  if (input.toolResults) {
    contents.push({
      role: "user",
      parts: input.toolResults.map((r) => ({ functionResponse: { name: r.name, response: { result: r.result ?? null, error: r.error || undefined } } })),
    });
  } else {
    contents.push({ role: "user", parts: [...imagePartsGemini(input.images), { text: input.text }] });
  }
  const { model, content } = await geminiGenerate({ system, contents, tools });
  contents.push(content);
  const parts = content.parts || [];
  const text = parts.filter((x) => typeof x.text === "string" && !x.thought).map((x) => x.text).join("\n").trim();
  const toolCalls = parts.filter((x) => x.functionCall).map((x, i) => ({ id: `${x.functionCall.name}-${contents.length}-${i}`, name: x.functionCall.name, args: x.functionCall.args || {} }));
  return { history: contents, text, toolCalls, provider: "gemini", model };
}

/** Single structured-output call with optional images/PDFs (document verification). */
async function extractJsonWith(p, { system, prompt, images = [], schema }) {
  if (p === "anthropic") {
    const response = await anthropicCreate({
      system,
      messages: [{ role: "user", content: [...imageBlocksAnthropic(images), { type: "text", text: prompt }] }],
      json: schema,
      effort: "medium",
    });
    const text = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
    return { data: JSON.parse(text), provider: "anthropic", model: response.model };
  }
  const { model, content } = await geminiGenerate({
    system,
    contents: [{ role: "user", parts: [...imagePartsGemini(images), { text: prompt }] }],
    json: schema,
  });
  const text = (content.parts || []).filter((x) => typeof x.text === "string" && !x.thought).map((x) => x.text).join("");
  return { data: JSON.parse(text), provider: "gemini", model };
}

function imageBlocksAnthropic(images = []) {
  return (images || []).map((img) =>
    img.mimeType === "application/pdf"
      ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: img.data } }
      : { type: "image", source: { type: "base64", media_type: img.mimeType, data: img.data } },
  );
}

function imagePartsGemini(images = []) {
  return (images || []).map((img) => ({ inlineData: { mimeType: img.mimeType, data: img.data } }));
}

// ---------------------------------------------------------------- HTTP helpers

export async function readJson(req, limitBytes = 8_000_000) {
  if (req.body && typeof req.body === "object") return req.body;
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limitBytes) throw new AiError(413, "Upload too large. Use photos under 3 MB.");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

export function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

export function handleError(res, error) {
  const status = error instanceof AiError ? error.status : 500;
  if (!(error instanceof AiError)) console.error(error);
  send(res, status, { error: error instanceof AiError ? error.message : "Something went wrong on the server." });
}

// ---------------------------------------------------------------- provider choice
// Gemini first (AI_PROVIDER, default "gemini"). If it is down or rate-limited and the
// other provider has a key, a new conversation falls back to it. A conversation that has
// started stays on the provider whose native history it carries.

function fallbackFor(p, error) {
  if (error instanceof AiError && error.status < 500 && error.status !== 429) return null;
  if (p === "gemini" && process.env.ANTHROPIC_API_KEY) return "anthropic";
  if (p === "anthropic" && process.env.GEMINI_API_KEY) return "gemini";
  return null;
}

async function withFallback(run) {
  const first = provider();
  try {
    return await run(first);
  } catch (error) {
    const other = fallbackFor(first, error);
    if (!other) throw error;
    console.warn(`AI provider ${first} failed (${error?.message}); using ${other}`);
    return run(other);
  }
}

export async function chatStep(args) {
  const history = args.history || [];
  if (history.length) return chatStepWith(history[0]?.parts ? "gemini" : "anthropic", args);
  return withFallback((p) => chatStepWith(p, args));
}

export const extractJson = (args) => withFallback((p) => extractJsonWith(p, args));
