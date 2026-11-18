// Sends server errors to Sentry when SENTRY_DSN is set (no SDK: one HTTPS call per error).
// Without a DSN it does nothing, so local previews and tests are unaffected.
// The same file lives in taparide_website/api/_lib and taparide_flutter/deploy/api/_lib.
import { randomUUID } from "node:crypto";

function parseDsn(dsn) {
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, "");
    if (!u.username || !project) return null;
    return { key: u.username, host: u.host, protocol: u.protocol, project };
  } catch {
    return null;
  }
}

/** Fire-and-forget; never throws. `context` lands in Sentry's "extra" data (no personal data, please). */
export async function reportError(error, context = {}) {
  const dsn = parseDsn(process.env.SENTRY_DSN || "");
  if (!dsn) return;
  const eventId = randomUUID().replace(/-/g, "");
  const err = error instanceof Error ? error : new Error(String(error));
  const event = {
    event_id: eventId,
    timestamp: Date.now() / 1000,
    platform: "node",
    level: "error",
    environment: process.env.VERCEL_ENV || "development",
    release: process.env.VERCEL_GIT_COMMIT_SHA || undefined,
    server_name: "vercel",
    exception: { values: [{ type: err.name, value: err.message, stacktrace: err.stack ? { frames: err.stack.split("\n").slice(1, 15).reverse().map((l) => ({ function: l.trim() })) } : undefined }] },
    extra: context,
  };
  const body = `${JSON.stringify({ event_id: eventId, dsn: process.env.SENTRY_DSN })}\n${JSON.stringify({ type: "event" })}\n${JSON.stringify(event)}`;
  try {
    await fetch(`${dsn.protocol}//${dsn.host}/api/${dsn.project}/envelope/`, {
      method: "POST",
      headers: { "Content-Type": "application/x-sentry-envelope", "X-Sentry-Auth": `Sentry sentry_version=7, sentry_key=${dsn.key}, sentry_client=taparide-api/1.0` },
      body,
      signal: AbortSignal.timeout(2000),
    });
  } catch {}
}
