// Tap A Ride website: header, story rail, waitlist, invite ticket and Tech Week seats.
(() => {
  "use strict";
  document.documentElement.classList.add("js");

  const EVENT = "abuja-tech-week-2026";
  const EVENT_START = new Date("2026-11-24T07:00:00+01:00");
  const SEATS_PER_BUS = 14;
  const local = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  const APP = local ? "http://localhost:8080" : "https://taparide.vercel.app";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const naira = (n) => "₦" + Number(n).toLocaleString("en-NG");

  // Storage can throw (private mode, blocked site data); the page works without it.
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch {} },
    del(k) { try { localStorage.removeItem(k); } catch {} },
  };

  // ---------------------------------------------------------------- links into the web app
  for (const a of $$("[data-app]")) a.href = APP + a.dataset.app;

  // ---------------------------------------------------------------- header + menu
  const top = $("[data-top]");
  const hero = $(".hero");
  const solid = () => top.classList.toggle("solid", !hero || hero.getBoundingClientRect().bottom < 90);
  solid();
  addEventListener("scroll", solid, { passive: true });

  const menuBtn = $("[data-menu-btn]");
  const menu = $("[data-menu]");
  const setMenu = (open) => {
    menu.hidden = !open;
    menuBtn.setAttribute("aria-expanded", String(open));
    menuBtn.querySelector("use").setAttribute("href", open ? "#i-close" : "#i-menu");
    top.classList.toggle("solid", open || !hero || hero.getBoundingClientRect().bottom < 90);
  };
  menuBtn?.addEventListener("click", () => setMenu(menu.hidden));
  menu?.addEventListener("click", (e) => { if (e.target.closest("a")) setMenu(false); });
  addEventListener("keydown", (e) => { if (e.key === "Escape" && menu && !menu.hidden) { setMenu(false); menuBtn.focus(); } });

  // ---------------------------------------------------------------- story rail tracks the section in view
  const rail = $("[data-rail]");
  if (rail && "IntersectionObserver" in window) {
    const links = new Map($$("[data-rail-link]", rail).map((a) => [a.dataset.railLink, a]));
    const seen = new Map();
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) seen.set(e.target.id, e.intersectionRatio);
      let best = null, ratio = 0;
      for (const [id, r] of seen) if (r > ratio) { best = id; ratio = r; }
      for (const [id, a] of links) a.setAttribute("aria-current", String(id === best && ratio > 0));
      const cur = best && links.get(best);
      if (cur && ratio > 0) {
        const box = rail.firstElementChild;
        const left = cur.offsetLeft - box.clientWidth / 2 + cur.clientWidth / 2;
        box.scrollTo({ left, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
      }
    }, { threshold: [0, 0.15, 0.3, 0.5, 0.7], rootMargin: "-120px 0px -35% 0px" });
    $$("[data-story]").forEach((s) => io.observe(s));
  }

  // ---------------------------------------------------------------- countdown
  const cd = $("[data-countdown]");
  if (cd) {
    const days = Math.ceil((EVENT_START - Date.now()) / 86_400_000);
    cd.textContent = days > 1 ? `${days} days` : days === 1 ? "Tomorrow" : Date.now() < new Date("2026-11-27") ? "On now" : "Finished";
  }

  // ---------------------------------------------------------------- api
  async function api(method, body, query = "") {
    const res = await fetch("/api/waitlist" + query, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || "We couldn't reach Tap A Ride. Check your connection and try again.");
    if (data.preview) $("[data-preview-flag]")?.removeAttribute("hidden");
    return data;
  }

  const emailOk = (v) => /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(v.trim());
  function say(form, text, kind) {
    const m = $("[data-msg]", form);
    if (!m) return;
    m.className = "form-msg" + (kind ? " " + kind : "");
    m.innerHTML = "";
    if (text instanceof Node) m.append(text); else m.textContent = text || "";
  }
  function busy(form, on) {
    const b = $("button[type=submit]", form);
    if (!b) return;
    b.disabled = on;
    b.setAttribute("aria-busy", String(on));
  }

  // ---------------------------------------------------------------- invite code from the link (?ref=XXXXXX)
  const params = new URLSearchParams(location.search);
  const ref = (params.get("ref") || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
  if (ref) store.set("tar.ref", ref);

  // ---------------------------------------------------------------- the ticket
  let me = null; // {code, position, total, referrals, free_ride, free_ride_left, seats}
  const card = $("[data-join-card]");
  const fullForm = $("[data-join=full]");
  const ticket = $("[data-ticket]");

  function inviteLink(code) { return `${location.origin}/r/${code}`; }

  function renderTicket(data, { print = false } = {}) {
    me = { ...me, ...data };
    store.set("tar.code", me.code);
    const name = store.get("tar.name");
    $("[data-t-name]", ticket).textContent = name || "you";
    $("[data-t-pos]", ticket).textContent = `#${Number(me.position).toLocaleString("en-NG")}`;
    $("[data-t-refs]", ticket).textContent = String(me.referrals ?? 0);
    $("[data-t-code]", ticket).textContent = me.code;
    $(".ticket-value", ticket).textContent = naira(me.free_ride || 1000);
    $("[data-t-note]", ticket).textContent = me.free_ride_left === false
      ? "The free rides have all been claimed, but your place in line is saved."
      : "Open your Tap A Ride account with this email and the ride lands in your wallet.";
    const seat = (me.seats || []).find((s) => s.event === EVENT);
    const seatEl = $("[data-t-seat]", ticket);
    seatEl.hidden = !seat;
    if (seat) seatEl.textContent = `Tech Week seat requested: ${seat.area} → Velodrome, ${dayLabel(seat.day)}, ${timeLabel(seat.slot)}`;

    const link = inviteLink(me.code);
    $("[data-t-link]", ticket).value = link;
    const msg = `I just got a free ride on Tap A Ride: fixed fares and verified rides in Abuja. Join with my link and get yours: ${link}`;
    $("[data-wa]", ticket).href = "https://wa.me/?text=" + encodeURIComponent(msg);
    $("[data-x]", ticket).href = "https://x.com/intent/post?text=" + encodeURIComponent(msg);
    const shareBtn = $("[data-share]", ticket);
    if (navigator.share) shareBtn.hidden = false;

    fullForm.hidden = true;
    ticket.hidden = false;
    if (print && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
      ticket.classList.remove("printing");
      void ticket.offsetWidth;
      ticket.classList.add("printing");
    }
    // The seat form no longer needs an email once we know who you are.
    $("[data-seat-email]")?.setAttribute("hidden", "");
  }

  $("[data-copy]", ticket)?.addEventListener("click", async (e) => {
    const input = $("[data-t-link]", ticket);
    const label = e.currentTarget.querySelector("span");
    try { await navigator.clipboard.writeText(input.value); } catch { input.select(); document.execCommand?.("copy"); }
    label.textContent = "Copied";
    setTimeout(() => (label.textContent = "Copy"), 1800);
  });
  $("[data-share]", ticket)?.addEventListener("click", () => {
    navigator.share?.({ title: "Tap A Ride", text: "Get a free ride on Tap A Ride in Abuja", url: inviteLink(me.code) }).catch(() => {});
  });
  $("[data-forget]", ticket)?.addEventListener("click", () => {
    store.del("tar.code");
    store.del("tar.name");
    me = null;
    ticket.hidden = true;
    fullForm.hidden = false;
    $("[data-seat-email]")?.removeAttribute("hidden");
    $("#j-email").focus();
  });

  // Returning visitor: show their ticket with a fresh place in line.
  const saved = store.get("tar.code");
  if (saved) {
    api("GET", null, "?code=" + encodeURIComponent(saved)).then((d) => renderTicket(d)).catch(() => store.del("tar.code"));
  }

  async function join(fields, source) {
    const data = await api("POST", { action: "join", ref: store.get("tar.ref") || undefined, source, ...fields });
    if (fields.name) store.set("tar.name", fields.name.trim().split(/\s+/)[0]);
    renderTicket(data, { print: true });
    return data;
  }

  // ---------------------------------------------------------------- hero quick join
  const quick = $("[data-join=hero]");
  quick?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = quick.email.value;
    if (!emailOk(email)) { quick.email.setAttribute("aria-invalid", "true"); quick.email.focus(); return say(quick, "Enter a valid email address.", "err"); }
    quick.email.removeAttribute("aria-invalid");
    busy(quick, true);
    say(quick, "");
    try {
      const d = await join({ email, company: quick.company.value }, "website-hero");
      const a = Object.assign(document.createElement("a"), { href: "#join", textContent: "See your ticket and invite link" });
      const p = document.createElement("span");
      p.append(d.existing ? `You're already in, at #${d.position}. ` : `You're in at #${d.position} of ${d.total}. Your free ride is saved. `, a);
      say(quick, p, "ok");
    } catch (err) {
      say(quick, err.message, "err");
    } finally {
      busy(quick, false);
    }
  });

  // ---------------------------------------------------------------- full join form
  fullForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = fullForm;
    if (!emailOk(f.email.value)) { f.email.setAttribute("aria-invalid", "true"); f.email.focus(); return say(f, "Enter a valid email address.", "err"); }
    f.email.removeAttribute("aria-invalid");
    busy(f, true);
    say(f, "");
    try {
      await join({ email: f.email.value, name: f.name.value, phone: f.phone.value, area: f.area.value, role: f.role.value, company: f.company.value }, "website");
      ticket.focus({ preventScroll: true });
    } catch (err) {
      say(f, err.message, "err");
    } finally {
      busy(f, false);
    }
  });

  // "Event organisers" link preselects the role.
  for (const a of $$("[data-role-link]")) {
    a.addEventListener("click", () => { if (fullForm?.role) fullForm.role.value = a.dataset.roleLink; });
  }

  // ---------------------------------------------------------------- Tech Week seats
  const dayLabel = (d) => new Date(d + "T12:00:00+01:00").toLocaleDateString("en-NG", { weekday: "short", day: "numeric", month: "short", timeZone: "Africa/Lagos" });
  const timeLabel = (t) => { const [h, m] = t.split(":").map(Number); return `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`; };

  const seatForm = $("[data-seat]");
  const demandList = $("[data-demand]");
  let mineKey = null;

  function renderDemand(d) {
    const per = d.seats_per_bus || SEATS_PER_BUS;
    const rows = (d.requests || []).slice(0, 6);
    demandList.innerHTML = "";
    if (!rows.length) {
      const li = document.createElement("li");
      li.className = "demand-empty";
      li.textContent = "No seats requested yet. Be the first from your area and share the link with your colleagues.";
      demandList.append(li);
      return;
    }
    for (const r of rows) {
      const li = document.createElement("li");
      if (`${r.day}|${r.area}|${r.slot}` === mineKey) li.classList.add("mine");
      const full = r.riders >= per;
      li.innerHTML = `<span class="demand-route"></span><span class="demand-count"></span><span class="demand-when"></span><span class="demand-bar"><i></i></span>`;
      $(".demand-route", li).textContent = `${r.area} → Velodrome`;
      $(".demand-when", li).textContent = `${dayLabel(r.day)} · ${timeLabel(r.slot)}${full ? " · enough riders" : ""}`;
      const c = $(".demand-count", li);
      c.textContent = String(r.riders);
      const small = document.createElement("small");
      small.textContent = `of ${per} seats`;
      c.append(small);
      $(".demand-bar i", li).style.transform = `scaleX(${Math.min(1, r.riders / per)})`;
      demandList.append(li);
    }
    $("[data-demand-sub]").textContent = `${d.total} seat${d.total === 1 ? "" : "s"} requested so far. A bus runs when ${per} people from one area pick the same day and time.`;
  }

  const loadDemand = () => api("GET", null, "?event=" + EVENT).then(renderDemand).catch(() => {
    demandList.innerHTML = "";
    const li = document.createElement("li");
    li.className = "demand-empty";
    li.textContent = "Seat counts aren't available right now. You can still reserve.";
    demandList.append(li);
  });
  if (demandList) {
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { io.disconnect(); loadDemand(); } }, { rootMargin: "400px" });
      io.observe(demandList);
    } else loadDemand();
  }

  seatForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = seatForm;
    const day = f.day.value, slot = f.slot.value, area = f.area.value;
    if (!area) { f.area.focus(); return say(f, "Choose the area you're leaving from.", "err"); }
    if (!slot) return say(f, "Pick a departure time.", "err");
    if (!me?.code && !emailOk(f.email.value)) { f.email.setAttribute("aria-invalid", "true"); f.email.focus(); return say(f, "Enter your email so we can confirm your bus.", "err"); }
    f.email.removeAttribute("aria-invalid");
    busy(f, true);
    say(f, "");
    try {
      if (!me?.code) await join({ email: f.email.value, phone: f.phone.value, area, company: f.company.value }, "tech-week");
      const r = await api("POST", { action: "seat", code: me.code, event: EVENT, day, area, slot });
      mineKey = `${r.day}|${r.area}|${r.slot}`;
      renderTicket(r.summary);
      const left = Math.max(0, r.seats_per_bus - r.riders);
      say(f, `Seat requested: ${area} → Velodrome, ${dayLabel(day)}, ${timeLabel(slot)}. ` +
        (left ? `${r.riders} of ${r.seats_per_bus} riders so far: ${left} more and the bus runs. Share your link to fill it.` : "This bus has enough riders. We'll confirm it with you soon."), "ok");
      loadDemand();
    } catch (err) {
      say(f, err.message, "err");
    } finally {
      busy(f, false);
    }
  });
})();
