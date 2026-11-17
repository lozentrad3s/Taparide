// Waitlist storage. With SUPABASE_URL and SUPABASE_ANON_KEY set, every call goes to the
// database functions in supabase/migrations/20261118000000_waitlist.sql. Without them
// (local preview), a small JSON file in the temp folder plays the same rules, so the
// website can be tried end to end before the database is updated.
import { readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomInt } from "node:crypto";

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
  const status = code === "22023" ? 400 : code === "P0002" ? 404 : 502;
  throw new StoreError(status, status === 502 ? "The waitlist is busy right now. Try again in a minute." : body?.message || "Something went wrong.");
}

// ---------------------------------------------------------------- preview store (mirrors the SQL)

const FREE_RIDE = 1000;
const FREE_RIDE_CAP = 5000;
const ROLES = ["rider", "driver", "operator", "ev_owner", "event_organiser", "other"];
const EVENTS = {
  "abuja-tech-week-2026": {
    days: ["2026-11-24", "2026-11-25", "2026-11-26"],
    slots: ["07:00", "08:00", "09:00"],
    areas: ["Kubwa", "Gwarinpa", "Lugbe", "Nyanya", "Karu", "Lokogoma", "Life Camp", "Jabi", "Wuse", "Maitama", "Garki", "Gwagwalada", "Bwari", "Kuje"],
    seats_per_bus: 14,
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

function summary(db, w) {
  return {
    code: w.code,
    referrals: w.referrals,
    position: db.waitlist.filter((o) => o.referrals > w.referrals || (o.referrals === w.referrals && o.id < w.id)).length + 1,
    total: db.waitlist.length,
    free_ride: FREE_RIDE,
    free_ride_left: db.waitlist.filter((o) => o.id <= w.id).length <= FREE_RIDE_CAP,
    seats: db.seats.filter((s) => s.waitlist_id === w.id).map(({ event, day, area, slot }) => ({ event, day, area, slot })),
  };
}

const preview = {
  join_waitlist({ p_email, p_name, p_phone, p_area, p_ref, p_role, p_source }) {
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
      save(db);
      return { ...summary(db, w), existing: true };
    }
    let ref = String(p_ref || "").trim().toUpperCase() || null;
    if (ref && !db.waitlist.some((o) => o.code === ref)) ref = null;
    w = {
      id: (db.waitlist.at(-1)?.id || 0) + 1,
      email, name, phone, area,
      role: ROLES.includes(p_role) ? p_role : "other",
      code: code(db),
      referred_by: ref,
      referrals: 0,
      source: p_source || null,
      created_at: new Date().toISOString(),
    };
    db.waitlist.push(w);
    if (ref) db.waitlist.find((o) => o.code === ref).referrals++;
    save(db);
    return { ...summary(db, w), existing: false };
  },

  waitlist_status({ p_code }) {
    const db = load();
    const w = db.waitlist.find((o) => o.code === String(p_code || "").trim().toUpperCase());
    if (!w) throw missing("We could not find that code.");
    return summary(db, w);
  },

  request_event_seat({ p_code, p_event, p_day, p_area, p_slot }) {
    const db = load();
    const ev = EVENTS[p_event];
    if (!ev) throw missing("This event is not taking seat requests.");
    const w = db.waitlist.find((o) => o.code === String(p_code || "").trim().toUpperCase());
    if (!w) throw missing("Join the waitlist first, then pick your seat.");
    if (!ev.days.includes(p_day)) throw bad("Pick one of the event days.");
    if (!ev.areas.includes(p_area)) throw bad("Pick an area from the list.");
    if (!ev.slots.includes(p_slot)) throw bad("Pick one of the departure times.");
    const mine = db.seats.find((s) => s.waitlist_id === w.id && s.event === p_event && s.day === p_day);
    if (mine) Object.assign(mine, { area: p_area, slot: p_slot });
    else db.seats.push({ waitlist_id: w.id, event: p_event, day: p_day, area: p_area, slot: p_slot });
    save(db);
    const riders = db.seats.filter((s) => s.event === p_event && s.day === p_day && s.area === p_area && s.slot === p_slot).length;
    return { day: p_day, area: p_area, slot: p_slot, riders, seats_per_bus: ev.seats_per_bus, summary: summary(db, w) };
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
