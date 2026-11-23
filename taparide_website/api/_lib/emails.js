// Website emails: the Tech Week bus pass and the waitlist welcome. Table layout with inline styles
// so they render in Gmail, Outlook and phone mail apps. Every value from a visitor is escaped.
import { esc } from "./mail.js";

const SITE = "https://taparide.com";
const WHATSAPP = "+234 911 050 2561";
const WA_LINK = "https://wa.me/2349110502561";
const FOREST = "#0B5A3A";
const DEEP = "#06331F";
const MUTED = "#5B6B62";

const dayName = (d) =>
  new Date(`${d}T12:00:00+01:00`).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone: "Africa/Lagos" });
export const daysText = (days) => [...(days || [])].sort().map(dayName).join(", ");

function frame(preheader, inner) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tap A Ride</title></head>
<body style="margin:0;padding:0;background:#F2F6F3;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F6F3;"><tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;color:#111814;">
<tr><td style="background:${DEEP};padding:20px 24px;"><img src="${SITE}/img/brand/taparide_wordmark_white.png" width="132" height="20" alt="Tap A Ride" style="display:block;border:0;"></td></tr>
${inner}
<tr><td style="padding:18px 24px 24px;border-top:1px solid #DDE6E0;font-size:12px;line-height:18px;color:${MUTED};">
Questions? WhatsApp <a href="${WA_LINK}" style="color:${FOREST};">${WHATSAPP}</a> or reply to this email.<br>
Tap A Ride · Abuja · <a href="${SITE}/privacy" style="color:${MUTED};">Privacy notice</a>
</td></tr>
</table></td></tr></table></body></html>`;
}

const row = (label, value) =>
  `<tr><td style="padding:6px 0;font-size:11px;letter-spacing:1px;text-transform:uppercase;color:${MUTED};">${label}</td></tr>
<tr><td style="padding:0 0 10px;font-size:17px;font-weight:bold;">${value}</td></tr>`;

/** The personal Tech Week bus pass. */
export function passEmail({ name, code, days, area }) {
  const when = daysText(days);
  const subject = `Your free Tech Week bus pass: ${code}`;
  const html = frame(
    `Pass ${code} for ${when}. Be at ${area} by 7:00 AM.`,
    `<tr><td style="padding:24px 24px 4px;">
<p style="margin:0 0 4px;font-size:13px;font-weight:bold;color:${FOREST};text-transform:uppercase;letter-spacing:1px;">Abuja Tech Week 2026 · Free bus pass</p>
<h1 style="margin:0 0 8px;font-size:24px;line-height:30px;">You're on the bus, ${esc(name.split(" ")[0])}.</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;color:#34423A;">One pass covers every day below. Show it with a photo ID when you board.</p>
</td></tr>
<tr><td style="padding:0 24px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:2px solid ${FOREST};border-radius:12px;">
<tr><td style="padding:16px 18px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
${row("Name", esc(name))}
${row("Pass ID", `<span style="font-size:22px;letter-spacing:2px;color:${FOREST};">${esc(code)}</span>`)}
${row("Valid on", esc(when))}
${row("Pick-up point", esc(area))}
${row("Departure", "7:00 AM sharp")}
${row("Drop-off", "Velodrome, National Stadium, Abuja")}
</table></td></tr></table>
</td></tr>
<tr><td style="padding:16px 24px 8px;font-size:14px;line-height:21px;color:#34423A;">
<p style="margin:0 0 10px;"><strong>Be there by 7:00 AM.</strong> The bus leaves on time.</p>
<p style="margin:0 0 10px;">Valid only for the person named above, with a photo ID. Not transferable: a copied or shared pass is refused at boarding.</p>
</td></tr>
<tr><td style="padding:4px 24px 22px;">
<a href="${SITE}/#tech-week" style="display:inline-block;background:${FOREST};color:#ffffff;text-decoration:none;font-weight:bold;font-size:15px;padding:13px 22px;border-radius:999px;">Show my pass with QR code</a>
</td></tr>`,
  );
  const text = `Your free Abuja Tech Week bus pass

Name: ${name}
Pass ID: ${code}
Valid on: ${when}
Pick-up point: ${area}
Departure: 7:00 AM sharp
Drop-off: Velodrome, National Stadium, Abuja

Be there by 7:00 AM; the bus leaves on time.
Valid only for the person named above, with a photo ID. Not transferable: a copied or shared pass is refused at boarding.

Show your pass with its QR code: ${SITE}/#tech-week
Questions? WhatsApp ${WHATSAPP}`;
  return { subject, html, text };
}

/** Welcome after joining the waitlist (new sign-ups only). */
export function welcomeEmail({ name, code, position, freeRideLeft }) {
  const link = `${SITE}/r/${code}`;
  const hello = name ? `Welcome, ${esc(String(name).split(" ")[0])}.` : "Welcome to Tap A Ride.";
  const credit = freeRideLeft === false
    ? "The sign-up rewards have all been claimed, but your place in line is saved."
    : "Your sign-up ride reward is granted. Open your Tap A Ride account with this same email to see it. We announce what it is worth, and how to use it, when we fully launch.";
  const subject = "You're on the Tap A Ride list";
  const html = frame(
    `You're #${position} in line. Share your link to move up.`,
    `<tr><td style="padding:24px 24px 8px;">
<h1 style="margin:0 0 8px;font-size:24px;line-height:30px;">${hello}</h1>
<p style="margin:0 0 14px;font-size:15px;line-height:22px;color:#34423A;">You're <strong>#${Number(position).toLocaleString("en-NG")}</strong> in line for Tap A Ride in Abuja.</p>
<p style="margin:0 0 14px;font-size:15px;line-height:22px;color:#34423A;">${credit}</p>
<p style="margin:0 0 6px;font-size:15px;line-height:22px;color:#34423A;">Every friend who joins with your link moves you up:</p>
<p style="margin:0 0 18px;font-size:16px;font-weight:bold;"><a href="${link}" style="color:${FOREST};">${link}</a></p>
<a href="${SITE}/app/#/register" style="display:inline-block;background:${FOREST};color:#ffffff;text-decoration:none;font-weight:bold;font-size:15px;padding:13px 22px;border-radius:999px;">Open my account</a>
</td></tr>
<tr><td style="padding:14px 24px 20px;font-size:14px;line-height:21px;color:#34423A;">Going to Abuja Tech Week (24–26 November)? Get a free bus pass at <a href="${SITE}/#tech-week" style="color:${FOREST};">taparide.com</a>.</td></tr>`,
  );
  const text = `${name ? `Welcome, ${String(name).split(" ")[0]}.` : "Welcome to Tap A Ride."}

You're #${position} in line for Tap A Ride in Abuja.
${credit}

Every friend who joins with your link moves you up: ${link}
Open your account: ${SITE}/app/#/register

Going to Abuja Tech Week (24–26 November)? Get a free bus pass at ${SITE}/#tech-week
Questions? WhatsApp ${WHATSAPP}`;
  return { subject, html, text };
}
