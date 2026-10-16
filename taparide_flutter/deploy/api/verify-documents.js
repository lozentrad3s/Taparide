// POST /api/verify-documents — AI pre-check of a partner application.
// Reads the driver's licence and vehicle documents, extracts their fields and compares them
// with what the applicant typed. The result supports (never replaces) the FCTA/admin reviewer.
import { extractJson, handleError, readJson, send, AiError } from "./_lib/ai.js";
import { requireUser } from "./_lib/auth.js";

const SYSTEM = `You check identity and vehicle documents for Tap A Ride, a transport platform in Abuja, Nigeria, regulated with the FCTA.
You receive photos or PDFs of documents (Nigerian driver's licence, vehicle licence / proof of ownership, roadworthiness certificate, insurance, vehicle photo) plus the details the applicant typed.
Extract only what is actually printed or visible. If a field is unreadable or absent, use null — never guess.
Compare each extracted field with the applicant's entry: names may differ in order or middle names (treat as "partial"); plate numbers and chassis numbers (VIN) must match character for character ignoring spaces and dashes.
Flag anything a human reviewer must look at: expired documents, mismatches, edited-looking images, a document that is not what it claims to be, or a photo where the plate is not visible.
You only advise; a human makes the decision.`;

const field = { type: "string", nullable: true };
const SCHEMA = {
  type: "object",
  properties: {
    documents: {
      type: "array",
      items: {
        type: "object",
        properties: {
          slot: { type: "string" },
          detected_type: { type: "string", enum: ["drivers_licence", "vehicle_licence", "proof_of_ownership", "roadworthiness", "insurance", "vehicle_photo", "id_card", "other", "unreadable"] },
          full_name: field,
          licence_number: field,
          licence_class: field,
          expiry_date: { type: "string", nullable: true, description: "YYYY-MM-DD" },
          plate_number: field,
          chassis_number: field,
          vehicle_make_model: field,
          vehicle_colour: field,
          readable: { type: "boolean" },
        },
        required: ["slot", "detected_type", "readable"],
      },
    },
    checks: {
      type: "array",
      items: {
        type: "object",
        properties: {
          field: { type: "string", enum: ["full_name", "licence_number", "licence_expiry", "plate_number", "chassis_number", "vehicle", "photo"] },
          entered: field,
          found: field,
          result: { type: "string", enum: ["match", "partial", "mismatch", "not_found", "expired"] },
          note: { type: "string" },
        },
        required: ["field", "result", "note"],
      },
    },
    overall: { type: "string", enum: ["pass", "review", "fail"] },
    summary: { type: "string", description: "Two sentences for the reviewer" },
  },
  required: ["documents", "checks", "overall", "summary"],
};

const ALLOWED = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

export default async function handler(req, res) {
  if (req.method !== "POST") return send(res, 405, { error: "Use POST." });
  try {
    await requireUser(req, { perMinute: 6 });
    const body = await readJson(req, 4_200_000);
    const docs = (body.documents || []).filter((d) => d && ALLOWED.has(d.mimeType) && typeof d.data === "string");
    if (!docs.length) throw new AiError(400, "Add at least the driver's licence and one vehicle document.");
    if (docs.length > 6) throw new AiError(400, "Send at most six documents.");

    const applicant = body.applicant || {};
    const today = new Date().toISOString().slice(0, 10);
    const slots = docs.map((d, i) => `${i + 1}. slot "${String(d.slot || "document").slice(0, 40)}"`).join("\n");
    const prompt = `Today is ${today}. The documents are attached in this order:\n${slots}\n\nApplicant's entries:\n${JSON.stringify({
      full_name: applicant.fullName,
      licence_number: applicant.licenceNumber,
      licence_expiry: applicant.licenceExpiry,
      plate_number: applicant.plateNumber,
      chassis_number: applicant.chassisNumber,
      vehicle: [applicant.vehicleMake, applicant.vehicleModel, applicant.vehicleYear, applicant.vehicleColour].filter(Boolean).join(" "),
    })}\n\nExtract each document and run the checks.`;

    const { data, provider, model } = await extractJson({ system: SYSTEM, prompt, images: docs.map((d) => ({ mimeType: d.mimeType, data: d.data })), schema: SCHEMA });
    send(res, 200, { ...data, checkedAt: new Date().toISOString(), provider, model });
  } catch (error) {
    handleError(res, error);
  }
}
