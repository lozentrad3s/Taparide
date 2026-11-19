// GET /api/daily-summary — run once a day by Vercel Cron (see taparide_website/vercel.json "crons").
// Vercel sends "Authorization: Bearer <CRON_SECRET>"; anything else is refused.
// Reads the day's numbers (counts only) with the server secret, emails them to ADMIN_NOTIFY_EMAIL
// and posts them to SUMMARY_WEBHOOK_URL when those are set.
import { timingSafeEqual } from "node:crypto";
import { AiError, handleError, send } from "./_lib/ai.js";
import { brandEmail, esc } from "./_lib/app-mail-layout.js";
import * as mailer from "./_lib/mail.js";

const { sendMail } = mailer;
// The website's copy of mail.js replaces this folder's in the assembled deployment: accept either shape.
const mailReady = () => (typeof mailer.mailReady === "function" ? mailer.mailReady() : !!mailer.mailReady);
import { postWebhook } from "./notify.js";

function cronAllowed(req) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const given = Buffer.from(`${req.headers.authorization || ""}`);
  const expected = Buffer.from(`Bearer ${secret}`);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

const n = (v) => Number(v || 0).toLocaleString("en-NG");
const dayLabel = (d) => new Date(`${d}T12:00:00+01:00`).toLocaleDateString("en-NG", { weekday: "short", day: "numeric", month: "short", timeZone: "Africa/Lagos" });

export function summaryEmail(s, date = new Date()) {
  const today = date.toLocaleDateString("en-NG", { weekday: "long", day: "numeric", month: "long", timeZone: "Africa/Lagos" });
  const rows = (s.by_point || []).map((r) => `<tr><td style="padding:6px 10px;border-bottom:1px solid #DDE6E0">${esc(dayLabel(r.day))}</td><td style="padding:6px 10px;border-bottom:1px solid #DDE6E0">${esc(r.area)}</td><td style="padding:6px 10px;border-bottom:1px solid #DDE6E0;text-align:right;font-weight:600">${n(r.riders)}</td></tr>`).join("");
  const stat = (label, total, day) => `<tr><td style="padding:6px 0">${label}</td><td style="padding:6px 0;text-align:right"><strong>${n(total)}</strong>${day != null ? ` <span style="color:#237A2E">(+${n(day)} today)</span>` : ""}</td></tr>`;
  const html = brandEmail({
    heading: `Daily summary · ${today}`,
    bodyHtml: `<table role="presentation" width="100%" style="font-size:15px;border-collapse:collapse">
${stat("Website sign-ups", s.signups_total, s.signups_24h)}
${stat("App accounts", s.accounts_total, s.accounts_24h)}
${stat("Tech Week passes", s.passes_total, s.passes_24h)}
${stat("Partner applications waiting", s.applications_waiting)}
${stat("Possible duplicate sign-ups", s.possible_duplicates)}
</table>
${rows ? `<p style="margin:20px 0 6px"><strong>Tech Week riders by day and pick-up point</strong></p>
<table role="presentation" width="100%" style="font-size:14px;border-collapse:collapse"><tr style="color:#5B6B62;text-align:left"><th style="padding:6px 10px">Day</th><th style="padding:6px 10px">Pick-up point</th><th style="padding:6px 10px;text-align:right">Riders</th></tr>${rows}</table>` : ""}`,
    cta: { label: "Open the admin dashboard", url: "https://taparide.com/dashboard/" },
    footnote: "Sent every morning by taparide.com. Counts only; names and contacts stay in the dashboard.",
  });
  const text = [
    `Tap A Ride daily summary · ${today}`,
    `Website sign-ups: ${n(s.signups_total)} (+${n(s.signups_24h)} today)`,
    `App accounts: ${n(s.accounts_total)} (+${n(s.accounts_24h)} today)`,
    `Tech Week passes: ${n(s.passes_total)} (+${n(s.passes_24h)} today)`,
    `Partner applications waiting: ${n(s.applications_waiting)}`,
    `Possible duplicate sign-ups: ${n(s.possible_duplicates)}`,
    ...(s.by_point || []).map((r) => `  ${dayLabel(r.day)} · ${r.area}: ${n(r.riders)}`),
    "Dashboard: https://taparide.com/dashboard/",
  ].join("\n");
  return { subject: `Tap A Ride today: ${n(s.signups_24h)} sign-ups, ${n(s.passes_24h)} new passes`, html, text };
}

export default async function handler(req, res) {
  try {
    if (!cronAllowed(req)) throw new AiError(401, "Not allowed.");
    if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY || !process.env.TOPUP_SIGNING_SECRET) throw new AiError(503, "The daily summary is not set up.");
    const r = await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/daily_summary`, {
      method: "POST",
      headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_secret: process.env.TOPUP_SIGNING_SECRET }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new AiError(502, `The database did not answer (${r.status}).`);
    const summary = await r.json();
    const mail = summaryEmail(summary);
    const to = (process.env.ADMIN_NOTIFY_EMAIL || "").split(",").map((e) => e.trim()).filter(Boolean);
    const emailed = mailReady() && to.length ? await sendMail({ to, subject: mail.subject, html: mail.html, text: mail.text }) : { sent: false, reason: "email not configured" };
    const posted = await postWebhook({ event: "daily.summary", at: new Date().toISOString(), summary });
    return send(res, 200, { ok: true, emailed: emailed.sent, posted });
  } catch (error) {
    handleError(res, error);
  }
}
