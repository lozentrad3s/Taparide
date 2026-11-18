// Tap A Ride website: header, hero slideshow, waitlist, invite ticket and Abuja Tech Week seats.
(() => {
  "use strict";
  document.documentElement.classList.add("js");

  const EVENT = "abuja-tech-week-2026";
  const TERMS = "v1"; // the version of /terms people agree to
  const EVENT_START = new Date("2026-11-24T07:00:00+01:00");
  // The app and the partner dashboards live on this same site.
  const APP = "/app";
  const DASH = "/dashboard";
  const WHATSAPP = "2349110502561";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const naira = (n) => "₦" + Number(n).toLocaleString("en-NG");
  const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Storage can throw (private mode, blocked site data); the page works without it.
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch {} },
    del(k) { try { localStorage.removeItem(k); } catch {} },
  };

  // ---------------------------------------------------------------- links into the app and dashboards
  for (const a of $$("[data-app]")) a.href = APP + a.dataset.app;
  for (const a of $$("[data-dash]")) a.href = DASH + a.dataset.dash;

  // ---------------------------------------------------------------- header + menu
  const top = $("[data-top]");
  const wa = $("[data-wa-float]");
  const waHint = $("[data-wa-hint]");
  let waHinted = store.get("tar.wa-hint") === "closed";
  const closeHint = () => {
    if (waHint) waHint.hidden = true;
    store.set("tar.wa-hint", "closed");
  };
  $("[data-wa-hint-close]")?.addEventListener("click", closeHint);
  const solid = () => {
    top?.classList.toggle("solid", scrollY > 8);
    const show = scrollY > Math.min(innerHeight * 0.75, 640);
    wa?.classList.toggle("is-visible", show);
    // Say hello once, a moment after the button first appears; it closes itself after 10 s.
    if (show && !waHinted && waHint) {
      waHinted = true;
      setTimeout(() => { waHint.hidden = false; setTimeout(() => { waHint.hidden = true; }, 10000); }, 1200);
    }
  };
  solid();
  addEventListener("scroll", solid, { passive: true });

  const menuBtn = $("[data-menu-btn]");
  const menu = $("[data-menu]");
  const setMenu = (open) => {
    menu.hidden = !open;
    menuBtn.setAttribute("aria-expanded", String(open));
    menuBtn.querySelector("use").setAttribute("href", open ? "#i-close" : "#i-menu");
  };
  menuBtn?.addEventListener("click", () => setMenu(menu.hidden));
  menu?.addEventListener("click", (e) => { if (e.target.closest("a")) setMenu(false); });
  addEventListener("keydown", (e) => { if (e.key === "Escape" && menu && !menu.hidden) { setMenu(false); menuBtn.focus(); } });

  // ---------------------------------------------------------------- hero slideshow
  const hero = $("[data-hero]");
  if (hero) {
    const slides = $$("[data-slide]", hero);
    const stories = $$("[data-story-slide]", hero);
    const tabs = $$("[data-tab]", hero);
    const MS = 6000;
    hero.style.setProperty("--slide-ms", MS + "ms");
    let i = 0, timer = null, paused = reduced();
    const show = (n) => {
      i = (n + slides.length) % slides.length;
      slides.forEach((s, k) => s.classList.toggle("is-on", k === i));
      stories.forEach((st, k) => {
        st.classList.toggle("is-on", k === i);
        st.setAttribute("aria-hidden", String(k !== i));
        for (const a of $$("a", st)) a.tabIndex = k === i ? 0 : -1;
      });
      tabs.forEach((t, k) => {
        t.classList.toggle("is-on", k === i);
        t.setAttribute("aria-pressed", String(k === i));
        t.classList.toggle("is-done", k < i);
        const bar = t.querySelector(".bar i");
        if (bar) { bar.style.animation = "none"; void bar.offsetWidth; bar.style.animation = ""; }
      });
    };
    const schedule = () => { clearTimeout(timer); if (!paused) timer = setTimeout(() => { show(i + 1); schedule(); }, MS); };
    const setPaused = (p) => {
      paused = p;
      hero.classList.toggle("paused", p);
      schedule();
    };
    tabs.forEach((t, k) => t.addEventListener("click", () => { show(k); schedule(); }));
    hero.addEventListener("focusin", () => { clearTimeout(timer); hero.classList.add("paused"); });
    hero.addEventListener("focusout", () => { if (!paused) { hero.classList.remove("paused"); schedule(); } });
    document.addEventListener("visibilitychange", () => (document.hidden ? clearTimeout(timer) : schedule()));
    setPaused(paused);
    show(0);
  }

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
        box.scrollTo({ left: cur.offsetLeft - box.clientWidth / 2 + cur.clientWidth / 2, behavior: reduced() ? "auto" : "smooth" });
      }
    }, { threshold: [0, 0.15, 0.3, 0.5, 0.7], rootMargin: "-120px 0px -35% 0px" });
    $$("[data-story]").forEach((s) => io.observe(s));
  }

  // ---------------------------------------------------------------- countdown
  for (const cd of $$("[data-countdown]")) {
    const days = Math.ceil((EVENT_START - Date.now()) / 86_400_000);
    cd.textContent = days > 1 ? `in ${days} days` : days === 1 ? "tomorrow" : Date.now() < new Date("2026-11-27") ? "on now" : "finished";
  }

  // ---------------------------------------------------------------- anti-bot (see api/waitlist.js)
  const loadedAt = performance.now();
  let turnstileToken = null;
  let turnstileWidget = null;
  fetch("/api/waitlist?config=1").then((r) => r.json()).then(({ turnstile }) => {
    if (!turnstile) return;
    window.onTurnstileReady = () => {
      const box = document.createElement("div");
      box.className = "ts-box";
      document.body.append(box);
      turnstileWidget = window.turnstile.render(box, { sitekey: turnstile, size: "flexible", appearance: "interaction-only", callback: (t) => (turnstileToken = t) });
    };
    const s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileReady&render=explicit";
    s.async = true;
    document.head.append(s);
  }).catch(() => {});

  // ---------------------------------------------------------------- api
  async function api(method, body, query = "") {
    if (body) {
      body = { ...body, elapsed: Math.round(performance.now() - loadedAt), turnstile: turnstileToken || undefined };
      turnstileToken = null;
      if (turnstileWidget !== null) window.turnstile?.reset(turnstileWidget);
    }
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

  const emailOk = (v) => /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(String(v).trim());
  const phoneOk = (v) => String(v).replace(/[^0-9]/g, "").length >= 10;
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
  // Claiming the free ride needs the terms accepted.
  function agreed(form) {
    const box = form.terms;
    if (!box || box.checked) { box?.closest(".agree")?.classList.remove("is-missing"); return true; }
    box.closest(".agree")?.classList.add("is-missing");
    box.focus();
    say(form, "Please agree to the Terms and Privacy notice to claim your free ride.", "err");
    return false;
  }

  function invalid(input, form, message) {
    input.setAttribute("aria-invalid", "true");
    input.focus();
    say(form, message, "err");
    return false;
  }

  // ---------------------------------------------------------------- invite code from the link (?ref=XXXXXX)
  const params = new URLSearchParams(location.search);
  const ref = (params.get("ref") || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
  if (ref) store.set("tar.ref", ref);

  // ---------------------------------------------------------------- the ticket
  let me = null; // {code, position, total, referrals, free_ride, free_ride_left, seats}
  const fullForm = $("[data-join=full]");
  const ticket = $("[data-ticket]");
  const inviteLink = (code) => `${location.origin}/r/${code}`;
  const dayLabel = (d) => new Date(d + "T12:00:00+01:00").toLocaleDateString("en-NG", { weekday: "short", day: "numeric", month: "short", timeZone: "Africa/Lagos" });
  const shortPoint = (p) => p.replace(/\s*\(.*\)$/, "");

  // "Open my account" goes to sign-up in the app with the email filled in (and the invite code kept).
  function accountLink() {
    const q = new URLSearchParams();
    const email = store.get("tar.email");
    if (email) q.set("email", email);
    if (me?.code) q.set("ref", me.code);
    return `${APP}/#/register${q.toString() ? "?" + q : ""}`;
  }

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
    const seats = (me.seats || []).filter((s) => s.event === EVENT);
    const seatEl = $("[data-t-seat]", ticket);
    seatEl.hidden = !seats.length;
    if (seats.length) {
      seatEl.textContent = "Tech Week passes: " + seats.map((s) => `${dayLabel(s.day)}, ${shortPoint(s.area)}${s.ticket ? ` (${s.ticket})` : ""}`).join(" · ") + ". Be there by 7:00 AM.";
    }

    const link = inviteLink(me.code);
    $("[data-t-link]", ticket).value = link;
    const msg = `I just got a free ride on Tap A Ride, plus free buses to Abuja Tech Week (24–26 Nov). Join with my link: ${link}`;
    $("[data-wa]", ticket).href = "https://wa.me/?text=" + encodeURIComponent(msg);
    $("[data-x]", ticket).href = "https://x.com/intent/post?text=" + encodeURIComponent(msg);
    if (navigator.share) $("[data-share]", ticket).hidden = false;
    $(".stub-actions .btn-go", ticket).href = accountLink();

    fullForm.hidden = true;
    ticket.hidden = false;
    if (print && !reduced()) {
      ticket.classList.remove("printing");
      void ticket.offsetWidth;
      ticket.classList.add("printing");
    }
    if (store.get("tar.access")) $("[data-seat-email]")?.setAttribute("hidden", "");
    savePasses(me.seats || []);
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
    for (const k of ["tar.code", "tar.name", "tar.email", "tar.access", "tar.passes"]) store.del(k);
    renderPasses();
    me = null;
    ticket.hidden = true;
    fullForm.hidden = false;
    $("[data-seat-email]")?.removeAttribute("hidden");
    $("#j-email").focus();
  });

  // Returning visitor: show their ticket with a fresh place in line.
  const saved = store.get("tar.code");
  if (saved) api("GET", null, "?code=" + encodeURIComponent(saved)).then((d) => renderTicket(d)).catch(() => store.del("tar.code"));

  // ---------------------------------------------------------------- personal bus passes
  function getPasses() {
    try { return JSON.parse(store.get("tar.passes") || "[]"); } catch { return []; }
  }
  /** Keeps one pass per day (the newest), from the server's view of this person's seats. */
  function savePasses(seats) {
    const fresh = seats.filter((s) => s.event === EVENT && s.ticket).map((s) => ({ code: s.ticket, name: me?.name || store.get("tar.fullname") || "", day: s.day, area: s.area, slot: s.slot }));
    if (!fresh.length) return;
    const byDay = new Map(getPasses().map((p) => [p.day, p]));
    for (const p of fresh) byDay.set(p.day, { ...byDay.get(p.day), ...p, name: p.name || byDay.get(p.day)?.name || "" });
    store.set("tar.passes", JSON.stringify([...byDay.values()].sort((a, b) => a.day.localeCompare(b.day))));
    renderPasses();
  }
  let qrReady;
  const loadQr = () => (qrReady ||= new Promise((ok, fail) => {
    if (window.qrcode) return ok();
    const s = Object.assign(document.createElement("script"), { src: "/js/vendor/qrcode.js", onload: ok, onerror: fail });
    document.head.append(s);
  }));
  async function renderPasses() {
    const box = $("[data-passes]");
    if (!box) return;
    const passes = getPasses();
    box.hidden = !passes.length;
    const list = $("[data-pass-list]", box);
    list.innerHTML = "";
    for (const p of passes) {
      const el = document.createElement("article");
      el.className = "pass";
      el.innerHTML = `<div class="pass-top"><img src="/img/brand/taparide_wordmark_white.png" width="120" height="18" alt="Tap A Ride"><span class="pass-tag">Free bus pass</span></div>
        <div class="pass-body"><div><p class="pass-event">Abuja Tech Week 2026</p><dl>
          <div><dt>Name</dt><dd class="pass-name"></dd></div>
          <div><dt>Date</dt><dd class="pass-day"></dd></div>
          <div><dt>Pick-up point</dt><dd class="pass-area"></dd></div>
          <div><dt>Pass ID</dt><dd class="pass-id"></dd></div>
        </dl></div><div class="pass-qr" aria-hidden="true"></div></div>
        <p class="pass-rules">Valid only for the person named above, with a photo ID. Not transferable: a copied or shared pass is refused at boarding. Be there by 7:00 AM; the bus leaves on time.</p>`;
      $(".pass-name", el).textContent = p.name || "Your name";
      $(".pass-day", el).textContent = `${dayLabel(p.day)} · 7:00 AM sharp`;
      $(".pass-area", el).textContent = p.area;
      $(".pass-id", el).textContent = p.code;
      el.setAttribute("aria-label", `Free bus pass ${p.code} for ${p.name}, ${dayLabel(p.day)} from ${p.area}`);
      list.append(el);
      loadQr().then(() => {
        const q = window.qrcode(0, "M");
        q.addData(`TAPARIDE PASS ${p.code} | ${p.name} | ${p.day} | ${p.area}`);
        q.make();
        $(".pass-qr", el).innerHTML = q.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
      }).catch(() => {});
    }
  }
  $("[data-print-pass]")?.addEventListener("click", () => window.print());
  renderPasses();

  async function join(fields, source) {
    const data = await api("POST", { action: "join", ref: store.get("tar.ref") || undefined, source, terms: TERMS, ...fields });
    if (data.access) store.set("tar.access", data.access);
    if (fields.name) store.set("tar.name", fields.name.trim().split(/\s+/)[0]);
    if (fields.email) store.set("tar.email", fields.email.trim().toLowerCase());
    renderTicket(data, { print: true });
    return data;
  }

  // ---------------------------------------------------------------- hero quick join
  const quick = $("[data-join=hero]");
  quick?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = quick.email.value;
    if (!emailOk(email)) return invalid(quick.email, quick, "Enter a valid email address.");
    quick.email.removeAttribute("aria-invalid");
    if (!agreed(quick)) return;
    busy(quick, true);
    say(quick, "");
    try {
      const d = await join({ email, company: quick.company.value }, "website-hero");
      const a = Object.assign(document.createElement("a"), { href: "#join", textContent: "See your ticket and invite link" });
      const p = document.createElement("span");
      p.append(d.existing ? `You're already in, at #${d.position}. ` : `You're in at #${d.position}. Your free ride is saved. `, a);
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
    if (!emailOk(f.email.value)) return invalid(f.email, f, "Enter a valid email address.");
    f.email.removeAttribute("aria-invalid");
    if (!agreed(f)) return;
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

  // ---------------------------------------------------------------- campaign gallery arrows
  const track = $("[data-gallery]");
  if (track) {
    const btns = $$("[data-gal]");
    const step = () => (track.querySelector("img")?.getBoundingClientRect().width || 300) + 20;
    const sync = () => {
      btns[0].disabled = track.scrollLeft < 8;
      btns[1].disabled = track.scrollLeft + track.clientWidth > track.scrollWidth - 8;
    };
    for (const b of btns) b.addEventListener("click", () => track.scrollBy({ left: Number(b.dataset.gal) * step(), behavior: reduced() ? "auto" : "smooth" }));
    track.addEventListener("scroll", sync, { passive: true });
    addEventListener("resize", sync);
    sync();
  }

  // ---------------------------------------------------------------- Abuja Tech Week seats
  const seatForm = $("[data-seat]");
  const pointButtons = $$("[data-point]");
  let demand = [];

  function selectedDay() { return seatForm?.day.value || "2026-11-24"; }
  function renderCounts() {
    const day = selectedDay();
    const dayEl = $("[data-points-day]");
    if (dayEl) dayEl.textContent = `Seats registered for ${dayLabel(day)}`;
    for (const el of $$("[data-count]")) {
      const n = demand.filter((r) => r.day === day && r.area === el.dataset.count).reduce((t, r) => t + r.riders, 0);
      el.textContent = String(n);
      const small = document.createElement("small");
      small.textContent = n === 1 ? "seat" : "seats";
      el.append(small);
    }
  }
  const loadDemand = () => api("GET", null, "?event=" + EVENT).then((d) => { demand = d.requests || []; renderCounts(); }).catch(() => {
    for (const el of $$("[data-count]")) el.textContent = "";
  });
  if (seatForm) {
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { io.disconnect(); loadDemand(); } }, { rootMargin: "400px" });
      io.observe(seatForm);
    } else loadDemand();
  }

  function pickPoint(name) {
    if (!seatForm) return;
    seatForm.area.value = name;
    for (const b of pointButtons) b.classList.toggle("is-picked", b.dataset.point === name);
  }
  for (const b of pointButtons) b.addEventListener("click", () => {
    pickPoint(b.dataset.point);
    (seatForm.name.value ? seatForm.phone : seatForm.name).focus({ preventScroll: true });
    if (innerWidth < 960) seatForm.scrollIntoView({ behavior: reduced() ? "auto" : "smooth", block: "start" });
  });
  seatForm?.area.addEventListener("change", () => pickPoint(seatForm.area.value));
  for (const r of $$("input[name=day]", seatForm || document)) r.addEventListener("change", renderCounts);

  seatForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = seatForm;
    for (const el of $$("[aria-invalid]", f)) el.removeAttribute("aria-invalid");
    const day = selectedDay(), area = f.area.value;
    if (!area) return invalid(f.area, f, "Choose your pick-up point.");
    if (f.name.value.trim().split(/\s+/).length < 2) return invalid(f.name, f, "Enter your first and last name for the boarding list.");
    if (!phoneOk(f.phone.value)) return invalid(f.phone, f, "Enter your WhatsApp number so we can send bus updates.");
    if (!store.get("tar.access") && !emailOk(f.email.value)) return invalid(f.email, f, "Enter your email to get your pass.");
    if (!agreed(f)) return;
    busy(f, true);
    say(f, "");
    try {
      if (!store.get("tar.access")) await join({ email: f.email.value, name: f.name.value, phone: f.phone.value, company: f.company.value }, "tech-week");
      const r = await api("POST", { action: "seat", access: store.get("tar.access"), event: EVENT, day, area, slot: "07:00", name: f.name.value, phone: f.phone.value });
      store.set("tar.name", f.name.value.trim().split(/\s+/)[0]);
      store.set("tar.fullname", r.ticket.name);
      renderTicket(r.summary);
      savePasses([{ ...r.ticket, ticket: r.ticket.code, event: EVENT }]);
      say(f, `Your free bus pass is ready: ${r.ticket.code}, ${dayLabel(day)}, ${shortPoint(area)}, 7:00 AM sharp. It's below; save or screenshot it.`, "ok");
      $("[data-passes]")?.scrollIntoView({ behavior: reduced() ? "auto" : "smooth", block: "start" });
      const msg = `I'm riding the free Tap A Ride bus to Abuja Tech Week (24–26 Nov, 7:00 AM). Get your free seat: ${inviteLink(me.code)}`;
      $("[data-seat-wa]", f).href = "https://wa.me/?text=" + encodeURIComponent(msg);
      $("[data-seat-done]", f).hidden = false;
      loadDemand();
    } catch (err) {
      say(f, err.message, "err");
    } finally {
      busy(f, false);
    }
  });
  $("[data-seat-again]")?.addEventListener("click", () => {
    const days = $$("input[name=day]", seatForm);
    const next = days.find((d) => !(me?.seats || []).some((s) => s.event === EVENT && s.day === d.value));
    if (next) { next.checked = true; renderCounts(); }
    $("[data-seat-done]", seatForm).hidden = true;
    say(seatForm, "");
    seatForm.area.focus();
  });
})();
