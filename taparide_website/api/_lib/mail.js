// Sends email through Resend (resend.com) when RESEND_API_KEY is set; otherwise does nothing.
// Never throws: a failed email must not fail the sign-up or booking that triggered it.
// The same file lives in taparide_website/api/_lib and taparide_flutter/deploy/api/_lib.
//   MAIL_FROM      sender, default "Tap A Ride <no-reply@taparide.com>" (the domain must be verified in Resend)
//   MAIL_REPLY_TO  where replies go, default info@taparide.com
import { reportError } from "./sentry.js";

export const mailReady = () => !!process.env.RESEND_API_KEY;

/** @returns {Promise<{sent: true, id: string} | {sent: false, reason: string}>} */
export async function sendMail({ to, subject, html, text, replyTo }) {
  if (!mailReady()) return { sent: false, reason: "not-configured" };
  if (!to || !subject || (!html && !text)) return { sent: false, reason: "incomplete" };
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
        reply_to: replyTo || process.env.MAIL_REPLY_TO || "info@taparide.com",
      }),
      signal: AbortSignal.timeout(5000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      // No addresses or names in the report: only what failed and why.
      await reportError(new Error(`Email not sent (${res.status}): ${body?.name || body?.message || "unknown"}`), { route: "mail", subject });
      return { sent: false, reason: `provider-${res.status}` };
    }
    return { sent: true, id: body.id };
  } catch (e) {
    await reportError(e, { route: "mail", subject });
    return { sent: false, reason: e?.name === "TimeoutError" ? "timeout" : "network" };
  }
}

/** Escapes text for HTML email bodies. */
export const esc = (v) =>
  String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
