// Sends email through Resend (resend.com) over its REST API. Set RESEND_API_KEY (and MAIL_FROM,
// e.g. "Tap A Ride <no-reply@taparide.com>", once taparide.com is verified in Resend).
// Without a key nothing is sent and callers carry on: sendMail never throws.
// The same interface lives in taparide_website/api/_lib/mail.js.
import { reportError } from "./sentry.js";

export const mailReady = () => !!process.env.RESEND_API_KEY;

/** @returns {Promise<{sent: true, id: string} | {sent: false, reason: string}>} */
export async function sendMail({ to, subject, html, text, replyTo } = {}) {
  if (!mailReady()) return { sent: false, reason: "email not configured" };
  if (!to || !subject || (!html && !text)) return { sent: false, reason: "missing fields" };
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: process.env.MAIL_FROM || "Tap A Ride <no-reply@taparide.com>",
        to: Array.isArray(to) ? to : [to],
        subject,
        html,
        text,
        reply_to: replyTo || "info@taparide.com",
      }),
      signal: AbortSignal.timeout(5000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      // No addresses or content in the report: only the status and Resend's error name.
      reportError(new Error(`Resend ${res.status}: ${body.name || body.message || "error"}`), { route: "mail" });
      return { sent: false, reason: `provider ${res.status}` };
    }
    return { sent: true, id: body.id };
  } catch (e) {
    reportError(new Error(`Resend unreachable: ${e?.name || "error"}`), { route: "mail" });
    return { sent: false, reason: "provider unreachable" };
  }
}
