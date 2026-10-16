// POST /api/insights — the AI analyst's written summary of a partner's figures.
// The app computes every number from real platform data; the model only interprets them.
import { extractJson, handleError, readJson, send, AiError } from "./_lib/ai.js";
import { requireUser } from "./_lib/auth.js";

const SYSTEM = `You are the Tap A Ride AI analyst for transport partners and the FCTA in Abuja, Nigeria.
You receive figures already computed from the platform (routes, revenue in naira, fleet status, demand by area, live road times versus timetables).
Write a short, specific analysis a busy transport manager can act on today:
- Use only the numbers given; never invent figures. Quote naira with the ₦ sign.
- Lead with what matters most (money lost or gained, safety, crowding, delays).
- Each action must be concrete (which route, which vehicle, which area, what time) and say why.
Keep the tone plain and professional.`;

const SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string", description: "One sentence, max 20 words" },
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: { title: { type: "string" }, detail: { type: "string" }, kind: { type: "string", enum: ["income", "fleet", "demand", "traffic", "routing", "safety"] } },
        required: ["title", "detail", "kind"],
      },
    },
    actions: {
      type: "array",
      items: {
        type: "object",
        properties: { title: { type: "string" }, why: { type: "string" }, impact: { type: "string", enum: ["high", "medium", "low"] } },
        required: ["title", "why", "impact"],
      },
    },
  },
  required: ["headline", "findings", "actions"],
};

export default async function handler(req, res) {
  if (req.method !== "POST") return send(res, 405, { error: "Use POST." });
  try {
    await requireUser(req, { perMinute: 10 });
    const body = await readJson(req, 200_000);
    if (!body.metrics || typeof body.metrics !== "object") throw new AiError(400, "No figures to analyse.");
    const prompt = `Figures for ${String(body.metrics.scope || "this operation").slice(0, 80)} (today is ${new Date().toISOString().slice(0, 10)}):\n${JSON.stringify(body.metrics).slice(0, 12000)}\n\nGive 3-5 findings and 3-4 actions.`;
    const { data, model } = await extractJson({ system: SYSTEM, prompt, schema: SCHEMA });
    send(res, 200, { ...data, model });
  } catch (error) {
    handleError(res, error);
  }
}
