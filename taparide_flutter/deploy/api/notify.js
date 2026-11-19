// POST /api/notify  { type: "application", id }   Authorization: Bearer <admin's Supabase access token>
// After an admin reviews a partner application in the dashboard, emails the applicant the decision.
// Every read uses the caller's own token, so Supabase's row-level security and role checks decide
// what they may see: only platform admins (signed in with their second step) get past my_role().
import { AiError, handleError, send } from "./_lib/ai.js";
import { brandEmail, esc } from "./_lib/app-mail-layout.js";
import { limitByIp } from "./_lib/auth.js";
import * as mailer from "./_lib/mail.js";

const { sendMail } = mailer;
// The website's copy of mail.js replaces this folder's in the assembled deployment: accept either shape.
const mailReady = () => (typeof mailer.mailReady === "function" ? mailer.mailReady() : !!mailer.mailReady);

const ALLOWED_ORIGINS = new Set(["https://taparide.com", "https://www.taparide.com", "https://taparide.vercel.app"]);
const originOk = (o) => !o || ALLOWED_ORIGINS.has(o) || /^https:\/\/taparide-[a-z0-9-]+-lozen-s-projects\.vercel\.app$/.test(o) || /^http:\/\/localhost(:\d+)?$/.test(o);

async function supabase(path, token, init = {}) {
  const res = await fetch(`${process.env.SUPABASE_URL}${path}`, {
    ...init,
    headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers || {}) },
    signal: AbortSignal.timeout(6000),
  });
  const body = await res.json().catch(() => null);
  if (res.status === 401) throw new AiError(401, "Your session has ended. Please sign in again.");
  if (!res.ok) throw new AiError(502, "The database did not answer. Try again.");
  return body;
}

const TYPE_LABEL = {
  private_driver: "private driver",
  fleet_owner: "fleet owner",
  bus_operator: "bus operator",
  ev_operator: "electric vehicle operator",
  government_agency: "government agency",
};

/** The applicant's email for a decision; null when the status has nothing to tell them. */
export function applicationEmail(a) {
  const first = esc(String(a.full_name || "").trim().split(/\s+/)[0] || "there");
  const kind = TYPE_LABEL[a.partner_type] || "partner";
  const note = a.reviewer_note ? `<p style="margin:0 0 12px;padding:12px 14px;background:#F7FAF8;border-left:3px solid #0B5A3A;border-radius:6px"><strong>Note from our team:</strong><br>${esc(a.reviewer_note)}</p>` : "";
  const noteText = a.reviewer_note ? `\nNote from our team: ${a.reviewer_note}\n` : "";
  if (a.status === "approved") {
    return {
      subject: "You're approved: welcome to Tap A Ride",
      html: brandEmail({
        heading: `Welcome aboard, ${first}`,
        bodyHtml: `<p style="margin:0 0 12px">Your application as a ${esc(kind)} is <strong>approved</strong>. Your partner dashboard is ready.</p>${note}
<p style="margin:0 0 6px"><strong>Next steps</strong></p>
<ol style="margin:0 0 12px;padding-left:20px">
<li>Sign in at <a href="https://taparide.com/dashboard/" style="color:#0B5A3A">taparide.com/dashboard</a> with the email and password you registered with.</li>
<li>Check your details, vehicles and routes, and add your drivers if you run a fleet.</li>
<li>Your collection wallet is already set up: fares riders pay with Tap to Pay arrive there after each trip.</li>
</ol>
<p style="margin:0">Your partnership follows the Tap A Ride partner agreement you accepted when you applied. If anything in it is unclear, reply to this email before your first trip.</p>`,
        cta: { label: "Open my dashboard", url: "https://taparide.com/dashboard/" },
      }),
      text: `Welcome aboard, ${a.full_name || ""}\n\nYour application as a ${kind} is approved. Your partner dashboard is ready.\n${noteText}\nNext steps:\n1. Sign in at https://taparide.com/dashboard/ with the email and password you registered with.\n2. Check your details, vehicles and routes, and add your drivers if you run a fleet.\n3. Fares riders pay with Tap to Pay arrive in your collection wallet after each trip.\n\nYour partnership follows the Tap A Ride partner agreement you accepted when you applied.\n\nQuestions: info@taparide.com · WhatsApp +234 911 050 2561`,
    };
  }
  if (a.status === "needs_changes" || a.status === "rejected") {
    const changes = a.status === "needs_changes";
    return {
      subject: changes ? "Your Tap A Ride application needs a few changes" : "Your Tap A Ride partner application",
      html: brandEmail({
        heading: changes ? `Almost there, ${first}` : `Thank you for applying, ${first}`,
        bodyHtml: `<p style="margin:0 0 12px">${changes ? `We reviewed your application as a ${esc(kind)} and need a few changes before we can approve it.` : `We reviewed your application as a ${esc(kind)} and can't approve it at this time.`}</p>${note}
<p style="margin:0">${changes ? "Sign in to the partner portal, update the details or documents mentioned above and send it again. We review updated applications quickly." : "You're welcome to apply again once the points above are sorted. Sign in to the partner portal to start a new application."}</p>`,
        cta: { label: changes ? "Update my application" : "Go to the partner portal", url: "https://taparide.com/dashboard/#/partner/status" },
      }),
      text: `${changes ? "Almost there" : "Thank you for applying"}, ${a.full_name || ""}\n\n${changes ? `We reviewed your application as a ${kind} and need a few changes before we can approve it.` : `We reviewed your application as a ${kind} and can't approve it at this time.`}\n${noteText}\nSign in at https://taparide.com/dashboard/#/partner/status to ${changes ? "update and resend it" : "apply again"}.\n\nQuestions: info@taparide.com · WhatsApp +234 911 050 2561`,
    };
  }
  return null;
}

export async function postWebhook(payload) {
  const url = process.env.SUMMARY_WEBHOOK_URL;
  if (!url) return false;
  try {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload), signal: AbortSignal.timeout(5000) });
    return r.ok;
  } catch {
    return false;
  }
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") throw new AiError(405, "POST only.");
    if (!originOk(req.headers.origin)) throw new AiError(403, "This service is only available from Tap A Ride.");
    await limitByIp(req, "notify", 20);
    if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) throw new AiError(503, "Notifications are not set up.");
    const token = `${req.headers.authorization || ""}`.replace(/^Bearer\s+/i, "");
    if (!token) throw new AiError(401, "Sign in to continue.");
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};

    if (body.type !== "application") throw new AiError(400, "Unknown notification.");
    const id = `${body.id || ""}`;
    if (!/^[0-9a-f-]{36}$/i.test(id)) throw new AiError(400, "Unknown application.");

    // The caller's role, as the database sees it with their own session.
    const role = await supabase("/rest/v1/rpc/my_role", token, { method: "POST", body: "{}" });
    if (role !== "admin") throw new AiError(403, "Only platform admins can send decisions.");

    const rows = await supabase(`/rest/v1/partner_applications?id=eq.${id}&select=id,full_name,email,partner_type,status,reviewer_note,reviewed_at`, token);
    const app = Array.isArray(rows) ? rows[0] : null;
    if (!app) throw new AiError(404, "Application not found.");

    const mail = applicationEmail(app);
    if (!mail) return send(res, 200, { sent: false, reason: `nothing to send for status "${app.status}"` });
    const result = mailReady() ? await sendMail({ to: app.email, subject: mail.subject, html: mail.html, text: mail.text }) : { sent: false, reason: "email not configured" };
    await postWebhook({ event: "application.reviewed", status: app.status, at: new Date().toISOString() });
    return send(res, 200, result);
  } catch (error) {
    if (error instanceof SyntaxError) return send(res, 400, { error: "That request could not be read." });
    handleError(res, error);
  }
}
