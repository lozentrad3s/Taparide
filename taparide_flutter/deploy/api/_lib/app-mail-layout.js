// Branded email layout for the app's server emails (partner decisions, daily summary).
// Kept apart from mail.js because the website ships its own copy of mail.js, which replaces
// this folder's one in the assembled deployment (same interface).

/** Escapes text for HTML email bodies. */
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/** Branded, inline-styled email shell (works in Gmail, Outlook and phone mail apps). */
export function brandEmail({ heading, bodyHtml, cta, footnote }) {
  const button = cta
    ? `<p style="margin:28px 0 8px"><a href="${esc(cta.url)}" style="display:inline-block;background:#0B5A3A;color:#ffffff;text-decoration:none;font-weight:600;padding:14px 24px;border-radius:12px;font-size:16px">${esc(cta.label)}</a></p>`
    : "";
  return `<!doctype html><html><body style="margin:0;padding:0;background:#F2F6F3">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F6F3;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;color:#111814">
<tr><td style="background:#06331F;padding:20px 28px;color:#ffffff;font-size:20px;font-weight:700;letter-spacing:.2px">Tap A Ride</td></tr>
<tr><td style="padding:28px 28px 8px">
<h1 style="margin:0 0 14px;font-size:22px;line-height:1.3;color:#111814">${esc(heading)}</h1>
<div style="font-size:15px;line-height:1.6;color:#34423A">${bodyHtml}</div>
${button}
</td></tr>
<tr><td style="padding:20px 28px 28px;font-size:12.5px;line-height:1.5;color:#5B6B62;border-top:1px solid #DDE6E0">
${footnote ? `${footnote}<br>` : ""}Questions? Reply to this email, write to <a href="mailto:info@taparide.com" style="color:#0B5A3A">info@taparide.com</a> or WhatsApp <a href="https://wa.me/2349110502561" style="color:#0B5A3A">+234 911 050 2561</a>.<br>Tap A Ride · Abuja · <a href="https://taparide.com" style="color:#0B5A3A">taparide.com</a>
</td></tr></table></td></tr></table></body></html>`;
}
