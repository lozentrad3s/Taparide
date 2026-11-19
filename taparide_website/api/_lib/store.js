// Waitlist storage. With SUPABASE_URL and SUPABASE_ANON_KEY set, every call goes to the
// database functions in supabase/migrations/20261118000000_waitlist.sql. Without them
// (local preview), a small JSON file in the temp folder plays the same rules, so the
// website can be tried end to end before the database is updated.
import { readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes, randomInt } from "node:crypto";

export class StoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const isPreview = () => !(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY);

export async function call(fn, args) {
  if (isPreview()) return preview[fn](args);
  const url = `${process.env.SUPABASE_URL}/rest/v1/rpc/${fn}`;
  const key = process.env.SUPABASE_ANON_KEY;
  const res = await fetch(url, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const body = await res.json().catch(() => null);
  if (res.ok) return body;
  const code = body?.code;
  const status = code === "22023" ? 400 : code === "P0002" ? 404 : code === "23505" ? 409 : 502;
  const err = new StoreError(status, status === 502 ? "The waitlist is busy right now. Try again in a minute." : body?.message || "Something went wrong.");
  // PostgREST: the database function doesn't exist (yet). Lets callers fall back to an older one.
  err.missing = code === "PGRST202";
  throw err;
}

// ---------------------------------------------------------------- preview store (mirrors the SQL)

const FREE_RIDE = 1000;
const FREE_RIDE_CAP = 5000;
const ROLES = ["rider", "driver", "operator", "ev_owner", "event_organiser", "other"];
const EVENTS = {
  "abuja-tech-week-2026": {
    days: ["2026-11-24", "2026-11-25", "2026-11-26"],
    slots: ["07:00"],
    areas: [
      "University of Abuja, Gwagwalada",
      "Nnamdi Azikiwe Airport",
      "Old Parade Ground (corps members)",
      "Nile University",
      "Police Signboard, Lugbe",
      "Checkpoint, Maraba–Nyanya",
    ],
    seats_per_bus: 0,
  },
};

const file = join(tmpdir(), "taparide-website-preview.json");
const load = () => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return { waitlist: [], seats: [] };
  }
};
const save = (db) => writeFileSync(file, JSON.stringify(db));
const bad = (m) => new StoreError(400, m);
const missing = (m) => new StoreError(404, m);

function code(db) {
  const a = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let c;
  do c = Array.from({ length: 6 }, () => a[randomInt(a.length)]).join("");
  while (db.waitlist.some((w) => w.code === c));
  return c;
}

function ticketCode(db, day) {
  const a = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let c;
  do c = `TW${day.slice(8, 10)}-` + Array.from({ length: 6 }, () => a[randomInt(a.length)]).join("");
  while (db.seats.some((s) => s.ticket === c));
  return c;
}

function passCode(db) {
  const a = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let c;
  do c = "TW-" + Array.from({ length: 6 }, () => a[randomInt(a.length)]).join("");
  while (db.seats.some((s) => s.ticket === c));
  return c;
}

const phoneKey = (p) => String(p || "").replace(/\D/g, "").slice(-10) || null;

/** One person's pass for one event (all their days share one pass ID), or null. */
function passOf(db, w, event) {
  const mine = db.seats.filter((s) => s.waitlist_id === w.id && s.event === event).sort((a, b) => a.day.localeCompare(b.day));
  if (!mine.length) return null;
  return { code: mine[0].ticket, event, name: w.name, days: mine.map((s) => s.day), area: mine[0].area, slot: mine[0].slot };
}

/** The person's own view: access key, name and their seats with pass IDs. */
function privateView(db, w) {
  return {
    ...summary(db, w),
    access: w.access,
    name: w.name,
    email: w.email,
    passes: [...new Set(db.seats.filter((s) => s.waitlist_id === w.id).map((s) => s.event))].map((e) => passOf(db, w, e)),
    seats: db.seats.filter((s) => s.waitlist_id === w.id).map(({ event, day, area, slot, ticket }) => ({ event, day, area, slot, ticket })),
  };
}

function summary(db, w) {
  return {
    code: w.code,
    referrals: w.referrals,
    position: db.waitlist.filter((o) => o.referrals > w.referrals || (o.referrals === w.referrals && o.id < w.id)).length + 1,
    total: db.waitlist.length,
    free_ride: FREE_RIDE,
    free_ride_left: db.waitlist.filter((o) => o.id <= w.id).length <= FREE_RIDE_CAP,
    seats: [],
  };
}

const preview = {
  join_waitlist({ p_email, p_name, p_phone, p_area, p_ref, p_role, p_source, p_terms }) {
    const db = load();
    const email = String(p_email || "").trim().toLowerCase();
    if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(email)) throw bad("Enter a valid email address.");
    const phone = String(p_phone || "").replace(/[^0-9+]/g, "") || null;
    if (phone && (phone.length < 10 || phone.length > 15)) throw bad("Enter a valid phone number, e.g. 0803 123 4567.");
    const name = String(p_name || "").trim().slice(0, 80) || null;
    const area = String(p_area || "").trim().slice(0, 40) || null;
    let w = db.waitlist.find((o) => o.email === email);
    if (w) {
      w.name ??= name;
      w.phone ??= phone;
      w.area ??= area;
      w.access ??= randomBytes(18).toString("hex");
      save(db);
      return { ...privateView(db, w), existing: true };
    }
    let ref = String(p_ref || "").trim().toUpperCase() || null;
    if (ref && !db.waitlist.some((o) => o.code === ref)) ref = null;
    w = {
      id: (db.waitlist.at(-1)?.id || 0) + 1,
      email, name, phone, area,
      role: ROLES.includes(p_role) ? p_role : "other",
      code: code(db),
      access: randomBytes(18).toString("hex"),
      referred_by: ref,
      referrals: 0,
      source: p_source || null,
      terms_version: p_terms || null,
      terms_accepted_at: p_terms ? new Date().toISOString() : null,
      created_at: new Date().toISOString(),
    };
    db.waitlist.push(w);
    if (ref) db.waitlist.find((o) => o.code === ref).referrals++;
    save(db);
    return { ...privateView(db, w), existing: false };
  },

  waitlist_status({ p_code }) {
    const db = load();
    const w = db.waitlist.find((o) => o.code === String(p_code || "").trim().toUpperCase());
    if (!w) throw missing("We could not find that code.");
    return summary(db, w);
  },

  reserve_event_seat({ p_access, p_event, p_day, p_area, p_slot, p_name, p_phone }) {
    const db = load();
    const ev = EVENTS[p_event];
    if (!ev) throw missing("This event is not taking seat requests.");
    const key = String(p_access || "");
    const w = key.length >= 20 ? db.waitlist.find((o) => o.access === key) : null;
    if (!w) throw missing("Join the waitlist first, then pick your seat.");
    if (!ev.days.includes(p_day)) throw bad("Pick one of the event days.");
    if (!ev.areas.includes(p_area)) throw bad("Pick a pick-up point from the list.");
    if (!ev.slots.includes(p_slot)) throw bad("Pick one of the departure times.");
    const phone = String(p_phone || "").replace(/[^0-9+]/g, "") || null;
    if (phone && (phone.length < 10 || phone.length > 15)) throw bad("Enter a valid phone number, e.g. 0803 123 4567.");
    const name = String(p_name || "").trim().slice(0, 80);
    if (name) w.name = name;
    if (phone) w.phone = phone;
    if (!w.name) throw bad("Enter your full name for the boarding list.");
    let mine = db.seats.find((s) => s.waitlist_id === w.id && s.event === p_event && s.day === p_day);
    if (mine) Object.assign(mine, { area: p_area, slot: p_slot });
    else db.seats.push((mine = { waitlist_id: w.id, event: p_event, day: p_day, area: p_area, slot: p_slot, ticket: ticketCode(db, p_day) }));
    save(db);
    const riders = db.seats.filter((s) => s.event === p_event && s.day === p_day && s.area === p_area && s.slot === p_slot).length;
    return { ticket: { code: mine.ticket, name: w.name, event: p_event, day: p_day, area: p_area, slot: p_slot }, riders, summary: privateView(db, w) };
  },

  reserve_event_pass({ p_access, p_event, p_area, p_name, p_phone, p_days, p_slot }) {
    const db = load();
    const ev = EVENTS[p_event];
    if (!ev) throw missing("This event is not taking seat requests.");
    const key = String(p_access || "");
    const w = key.length >= 20 ? db.waitlist.find((o) => o.access === key) : null;
    if (!w) throw missing("Join the waitlist first, then pick your seat.");
    const name = String(p_name || "").trim().replace(/\s+/g, " ").slice(0, 80);
    if (name.split(" ").length < 2) throw bad("Enter your first and last name for the boarding list.");
    const phone = String(p_phone || "").replace(/[^0-9+]/g, "");
    if ((phoneKey(phone) || "").length < 10 || phone.length > 15) throw bad("Enter your WhatsApp number, e.g. 0803 123 4567.");
    if (!ev.areas.includes(p_area)) throw bad("Pick a pick-up point from the list.");
    const slot = p_slot || ev.slots[0];
    if (!ev.slots.includes(slot)) throw bad("Pick one of the departure times.");
    const days = p_days?.length ? p_days : ev.days;
    if (days.some((d) => !ev.days.includes(d))) throw bad("Pick days of the event only.");
    const other = db.waitlist.find((o) => o.id !== w.id && phoneKey(o.phone) === phoneKey(phone) && db.seats.some((s) => s.waitlist_id === o.id && s.event === p_event));
    if (other) throw new StoreError(409, `This WhatsApp number already has a free bus pass (booked with ${other.email.replace(/^(.).*(@.*)$/, "$1***$2")}). One pass covers every day; check that email for it, or message us on WhatsApp.`);
    w.name = name;
    w.phone = phone;
    const code = db.seats.find((s) => s.waitlist_id === w.id && s.event === p_event)?.ticket || passCode(db);
    db.seats = db.seats.filter((s) => !(s.waitlist_id === w.id && s.event === p_event));
    for (const day of days) db.seats.push({ waitlist_id: w.id, event: p_event, day, area: p_area, slot, ticket: code });
    save(db);
    const riders = db.seats.filter((s) => s.event === p_event && s.day === days[0] && s.area === p_area && s.slot === slot).length;
    return { pass: passOf(db, w, p_event), riders, summary: privateView(db, w) };
  },

  event_seat_demand({ p_event }) {
    const db = load();
    const ev = EVENTS[p_event];
    if (!ev) return null;
    const groups = new Map();
    for (const s of db.seats.filter((s) => s.event === p_event)) {
      const k = `${s.day}|${s.area}|${s.slot}`;
      groups.set(k, (groups.get(k) || 0) + 1);
    }
    const requests = [...groups].map(([k, riders]) => {
      const [day, area, slot] = k.split("|");
      return { day, area, slot, riders };
    }).sort((a, b) => b.riders - a.riders);
    return { event: p_event, config: ev, seats_per_bus: ev.seats_per_bus, requests, total: requests.reduce((n, r) => n + r.riders, 0) };
  },
};
