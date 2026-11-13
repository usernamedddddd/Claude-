import {
  CATEGORIES, CHAINS, CHAIN_KEYS, DEFAULTS, TIPS, decodePrice, overpassQuery, parseOverpass,
  parseReddit, placeFromNominatim, rankDeals,
} from "./logic.js";

const NOMINATIM = "https://nominatim.openstreetmap.org";
const OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"];
const REDDIT = "https://www.reddit.com/search.json";
const QUERIES = [
  "dollar general penny",
  "home depot penny",
  "penny shopping",
  "hidden clearance",
  "target clearance 70%",
  "walmart clearance",
];
const STORE_CACHE_DAYS = 7;
const DEAL_CACHE_MIN = 15;

// ---- storage (per-device; the app works without it) -----------------------------
const store = {
  get(k, fallback) { try { const v = localStorage.getItem("dealbot:" + k); return v ? JSON.parse(v) : fallback; } catch { return fallback; } },
  set(k, v) { try { localStorage.setItem("dealbot:" + k, JSON.stringify(v)); } catch { /* private mode */ } },
};

const settings = Object.assign({ loc: null, radiusMiles: DEFAULTS.radiusMiles, chains: DEFAULTS.chains, hideFar: true },
  store.get("settings", {}));
const saveSettings = () => store.set("settings", settings);
let stores = null;            // nearby stores, or null if unknown
let rawDeals = [];            // posts as fetched
let kindFilter = "all";
let catFilter = store.get("category", "all");   // remembered between visits
const CAT = Object.fromEntries(CATEGORIES.map((c) => [c.key, c]));
if (catFilter !== "all" && catFilter !== "other" && !CAT[catFilter]) catFilter = "all";
let loading = false;

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const isApple = /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent);

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove("show"), 2200);
}

function directionsUrl(s) {
  return isApple ? `https://maps.apple.com/?daddr=${s.lat},${s.lon}&q=${encodeURIComponent(s.name)}`
    : `https://www.google.com/maps/dir/?api=1&destination=${s.lat},${s.lon}`;
}

function ago(ms) {
  if (!ms) return "";
  const m = Math.max(0, (Date.now() - ms) / 60000);
  if (m < 60) return `${Math.round(m)}m ago`;
  if (m < 1440) return `${Math.round(m / 60)}h ago`;
  return `${Math.round(m / 1440)}d ago`;
}

async function fetchJson(url, opts = {}, timeoutMs = 20000) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const r = await fetch(url, { ...opts, signal: ctl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally { clearTimeout(t); }
}

// ---- location -------------------------------------------------------------------
async function reverseGeocode(lat, lon) {
  try {
    const r = await fetchJson(`${NOMINATIM}/reverse?format=jsonv2&zoom=10&addressdetails=1&lat=${lat}&lon=${lon}`);
    return placeFromNominatim({ ...r, lat, lon });
  } catch { return { lat, lon, city: "", state: "", label: "My location" }; }
}

async function geocode(q) {
  const zip = /^\d{5}$/.test(q.trim());
  const params = new URLSearchParams({ format: "jsonv2", limit: "1", addressdetails: "1", countrycodes: "us" });
  params.set(zip ? "postalcode" : "q", q.trim());
  const res = await fetchJson(`${NOMINATIM}/search?${params}`);
  if (!res.length) throw new Error("Couldn't find that place. Try a ZIP code or 'City, ST'.");
  return placeFromNominatim(res[0]);
}

function useGps() {
  const msg = $("#locMsg");
  if (!navigator.geolocation) { msg.textContent = "This browser can't share location. Enter a ZIP instead."; return; }
  msg.innerHTML = '<span class="spin">↻</span> Finding you…';
  navigator.geolocation.getCurrentPosition(async (pos) => {
    const lat = +pos.coords.latitude.toFixed(4), lon = +pos.coords.longitude.toFixed(4);
    await setLocation(await reverseGeocode(lat, lon));
  }, (err) => {
    msg.textContent = err.code === 1
      ? "Location permission was denied. Enter a ZIP code instead, or allow location for this site in your browser settings."
      : "Couldn't get your location. Enter a ZIP code instead.";
  }, { enableHighAccuracy: false, timeout: 15000, maximumAge: 600000 });
}

async function setPlace() {
  const q = $("#placeInput").value;
  if (!q.trim()) return;
  $("#locMsg").innerHTML = '<span class="spin">↻</span> Looking up…';
  try { await setLocation(await geocode(q)); } catch (e) {
    $("#locMsg").textContent = e instanceof TypeError || e.name === "AbortError"
      ? "Can't reach the map service. Check your connection and try again." : e.message;
  }
}

async function setLocation(loc) {
  settings.loc = loc;
  saveSettings();
  $("#locMsg").textContent = `Set to ${loc.label}.`;
  renderLocBtn();
  $("#settings").close();
  stores = null;
  await refresh(true);
}

function renderLocBtn() {
  $("#locBtn").textContent = settings.loc ? `📍 ${settings.loc.label || "My location"} · ${settings.radiusMiles} mi` : "📍 Set location";
}

// ---- data loading ---------------------------------------------------------------
function storeKey() {
  const l = settings.loc;
  return `${l.lat.toFixed(3)},${l.lon.toFixed(3)},${settings.radiusMiles},${[...settings.chains].sort().join(",")}`;
}

async function loadStores(force) {
  if (!settings.loc) return null;
  const key = storeKey();
  const cached = store.get("stores", null);
  if (!force && cached?.key === key && Date.now() - cached.at < STORE_CACHE_DAYS * 86400000) return cached.stores;
  const body = new URLSearchParams({ data: overpassQuery(settings.loc.lat, settings.loc.lon, settings.radiusMiles, settings.chains) });
  for (const url of OVERPASS) {
    try {
      const payload = await fetchJson(url, { method: "POST", body }, 30000);
      const found = parseOverpass(payload, settings.loc, settings.chains);
      store.set("stores", { key, at: Date.now(), stores: found });
      return found;
    } catch { /* try the next mirror */ }
  }
  return cached?.key === key ? cached.stores : null;
}

// Deals come from two places:
//  1. deals.json, published next to this app every hour by GitHub Actions. It collects
//     Google News, Bing News, Slickdeals, deal blogs and Reddit, which a browser can't
//     read directly (those sites block cross-site requests).
//  2. A live Reddit search from the phone, for anything posted since the last hourly run.
async function loadFeed() {
  const data = await fetchJson(`deals.json?t=${Math.floor(Date.now() / 300000)}`, { cache: "no-store" });
  return { deals: data.deals || [], sources: data.sources || [], at: data.generated_at };
}

async function loadDeals() {
  const [feed, ...reddit] = await Promise.allSettled([loadFeed(), ...QUERIES.map((q) =>
    fetchJson(`${REDDIT}?${new URLSearchParams({ q, sort: "new", t: "week", limit: "50", raw_json: "1" })}`))]);
  const byId = new Map();
  const add = (d) => { if (!byId.has(d.id)) byId.set(d.id, d); };
  const redditOk = reddit.filter((r) => r.status === "fulfilled");
  redditOk.forEach((r) => parseReddit(r.value).forEach(add));
  const feedOk = feed.status === "fulfilled";
  if (feedOk) feed.value.deals.forEach(add);
  const feedSources = feedOk ? feed.value.sources : [];
  const names = new Set(feedSources.filter((s) => s.ok).map((s) => s.name.split(":")[0]));
  if (redditOk.length) names.add("Reddit");
  return {
    deals: [...byId.values()],
    ok: (feedOk && feed.value.deals.length ? 1 : 0) + redditOk.length,
    sourceCount: feedSources.filter((s) => s.ok).length + (redditOk.length ? 1 : 0),
    sourceNames: [...names],
    feedAt: feedOk ? feed.value.at : null,
  };
}

async function refresh(force = false) {
  if (loading) return;
  loading = true;
  $("#refreshBtn").classList.add("spin");
  const status = $("#dealStatus");
  try {
    const cached = store.get("deals", null);
    if (!force && cached && Date.now() - cached.at < DEAL_CACHE_MIN * 60000) {
      rawDeals = cached.deals;
      stores = await loadStores(false);
      status.className = "status";
      status.textContent = `${cached.summary || "Updated"} · ${ago(cached.at)} · tap ↻ to refresh`;
    } else {
      status.className = "status";
      status.innerHTML = '<span class="spin">↻</span> Finding deals near you…';
      const [s, d] = await Promise.all([loadStores(force), loadDeals()]);
      stores = s;
      if (d.ok === 0) {
        rawDeals = cached?.deals || [];
        status.className = "status warn";
        status.innerHTML = `Couldn't load deals. Check your connection and tap ↻.
          ${rawDeals.length ? "Showing your last results." : ""}
          <a href="https://www.reddit.com/search/?q=penny%20list&sort=new" target="_blank" rel="noopener">Search Reddit yourself →</a>`;
      } else {
        rawDeals = d.deals;
        const summary = `Checked ${d.sourceCount} source${d.sourceCount === 1 ? "" : "s"} (${d.sourceNames.slice(0, 5).join(", ")}${d.sourceNames.length > 5 ? ", …" : ""})`;
        store.set("deals", { at: Date.now(), deals: rawDeals, summary });
        status.textContent = `${summary} · just now`;
      }
    }
  } finally {
    loading = false;
    $("#refreshBtn").classList.remove("spin");
    renderDeals();
    renderStores();
  }
}

// ---- rendering ------------------------------------------------------------------
function renderDeals() {
  const list = $("#dealList");
  const words = $("#search").value.split(/[,\s]+/).filter(Boolean);
  const cfg = { ...DEFAULTS, radiusMiles: settings.radiusMiles, chains: settings.chains, keywords: words,
    requireNearbyStore: settings.hideFar, minScore: 20 };
  const byKind = rankDeals(rawDeals.map((d) => ({ ...d })), cfg, settings.loc, stores)
    .filter((d) => kindFilter === "all" || d.kind === kindFilter);
  renderCategoryChips(byKind);
  const deals = byKind.filter((d) => catFilter === "all"
    || (catFilter === "other" ? !d.categories.length : d.categories.includes(catFilter)));

  const seen = store.get("seen", {});
  const now = Date.now();
  for (const [id, t] of Object.entries(seen)) if (now - t > 30 * 86400000) delete seen[id];

  if (!settings.loc) {
    list.innerHTML = `<div class="card empty">Set your location to see deals at stores near you.<div class="actions">
      <button class="btn primary" data-open-settings>📍 Set location</button></div></div>`;
  } else if (!deals.length) {
    const what = catFilter !== "all" ? `in ${catFilter === "other" ? "Other" : CAT[catFilter].label} ` : "";
    list.innerHTML = loading ? "" : `<div class="empty">No deals ${what}match right now.<br>Try “All”, clear the filter, or widen your radius.</div>`;
  } else {
    list.innerHTML = deals.slice(0, 60).map((d) => {
      const isNew = !seen[d.id];
      const chains = d.chains.map((c) => CHAINS[c].name).join(", ") || "Store not stated";
      const s = d.nearestStore;
      return `<article class="card">
        <div class="row">
          <span class="badge ${d.kind}">${d.kind === "penny" ? "🪙 PENNY" : d.kind.toUpperCase()}</span>
          ${isNew ? '<span class="badge new">NEW</span>' : ""}
          ${d.percentOff ? `<span class="meta">${d.percentOff}% off</span>` : ""}
          <span class="score" title="Deal score">★ ${Math.round(d.score)}</span>
        </div>
        <h3>${esc(d.title)}</h3>
        <div class="meta">${esc(chains)}${s ? ` · ${s.distanceMiles.toFixed(1)} mi` : ""}${d.localMention ? " · mentions your area" : ""}</div>
        ${d.priceNotes.slice(0, 2).map((n) => `<div class="note">💡 ${esc(n)}</div>`).join("")}
        ${d.upcs.length ? `<div class="row" style="margin-top:6px">${d.upcs.slice(0, 6).map((u) => `<button class="upc" data-upc="${u}">${u}</button>`).join("")}</div>` : ""}
        ${d.categories.length ? `<div class="tags">${d.categories.map((c) => `<span class="tag">${CAT[c].icon} ${CAT[c].label}</span>`).join("")}</div>` : ""}
        <div class="meta" style="margin-top:6px">${esc(d.source)} · ${ago(d.published)}</div>
        <div class="actions">
          <a class="btn primary" href="${esc(d.url)}" target="_blank" rel="noopener">Open post</a>
          ${s ? `<a class="btn" href="${directionsUrl(s)}" target="_blank" rel="noopener">Directions</a>` : ""}
        </div>
      </article>`;
    }).join("");
  }
  for (const d of deals) if (!seen[d.id]) seen[d.id] = now;
  // Remember as seen after a short delay so "NEW" stays visible during this visit.
  clearTimeout(renderDeals.t);
  renderDeals.t = setTimeout(() => store.set("seen", seen), 3000);
}

// Category chips show how many current deals fall in each, so empty ones are easy to skip.
function renderCategoryChips(deals) {
  const counts = { all: deals.length, other: 0 };
  for (const d of deals) {
    if (!d.categories.length) counts.other++;
    for (const c of d.categories) counts[c] = (counts[c] || 0) + 1;
  }
  const all = [...CATEGORIES, { key: "other", label: "Other", icon: "📦" }];
  // Categories with deals first (in their usual order), empty ones at the end of the row.
  const chips = [{ key: "all", label: "All categories", icon: "" },
    ...all.filter((c) => counts[c.key] || c.key === catFilter), ...all.filter((c) => !counts[c.key] && c.key !== catFilter)];
  $("#catFilters").innerHTML = chips.map((c) => {
    const n = counts[c.key] || 0;
    const on = c.key === catFilter;
    return `<button class="pill" data-cat="${c.key}" aria-pressed="${on}" ${!n && !on ? "disabled" : ""}>`
      + `${c.icon ? c.icon + " " : ""}${c.label}${settings.loc ? ` <span class="n">${n}</span>` : ""}</button>`;
  }).join("");
}

function renderStores() {
  const st = $("#storeStatus"), list = $("#storeList");
  if (!settings.loc) { st.textContent = "Set your location to see nearby stores."; list.innerHTML = ""; return; }
  if (stores === null) { st.textContent = loading ? "Looking up stores…" : "Couldn't look up stores right now. Try ↻ later."; list.innerHTML = ""; return; }
  st.textContent = `${stores.length} store${stores.length === 1 ? "" : "s"} within ${settings.radiusMiles} miles of ${settings.loc.label}`;
  list.innerHTML = stores.length ? stores.map((s) => `<div class="card store">
      <div class="dist">${s.distanceMiles.toFixed(1)} mi</div>
      <div class="info"><div><strong>${esc(CHAINS[s.chain].name)}</strong></div>
        <div class="meta">${esc(s.address || s.name)}</div></div>
      <a class="btn" href="${directionsUrl(s)}" target="_blank" rel="noopener">Go</a>
    </div>`).join("")
    : `<div class="empty">No stores found. Widen your radius in settings.</div>`;
}

function renderDecode() {
  const chain = $("#decStore").value, raw = $("#decPrice").value.replace(/[$\s]/g, "");
  const out = $("#decOut");
  if (!raw) { out.innerHTML = ""; return; }
  const price = parseFloat(raw);
  if (!(price > 0)) { out.innerHTML = `<div class="note">Enter a price like 12.03</div>`; return; }
  const sigs = decodePrice(chain, price);
  out.innerHTML = sigs.length ? sigs.map((s) => `<div class="card" style="margin:0 0 8px">
      <span class="badge ${s.kind === "penny" ? "penny" : s.kind === "regular" ? "other" : "clearance"}">${s.kind.replace("_", " ").toUpperCase()}</span>
      ${s.pct ? `<strong> ~${s.pct}% off</strong>` : ""}<div style="margin-top:6px">${esc(s.note)}</div></div>`).join("")
    : `<div class="note">No known clearance code for $${price.toFixed(2)} at ${CHAINS[chain].name}. Scan it in the store's app to check.</div>`;
}

function renderTips() {
  $("#view-tips").innerHTML = Object.entries(TIPS).map(([k, tips]) => `<div class="card">
      <h3>${CHAINS[k].name}</h3><ul>${tips.map((t) => `<li>${esc(t)}</li>`).join("")}</ul></div>`).join("")
    + `<div class="card"><h3>Good to know</h3><ul>
      <li>Penny lists are made by shoppers. Scan a UPC (tap one to copy it) in the store's app before you make a trip.</li>
      <li>Stores are told to pull penny items, and staff can say no. Be kind.</li>
      <li>Add this app to your home screen to open it like a regular app.</li></ul></div>`;
}

function renderSettings() {
  $("#radius").value = settings.radiusMiles;
  $("#radiusVal").textContent = settings.radiusMiles;
  $("#hideFar").checked = settings.hideFar;
  $("#chainChecks").innerHTML = CHAIN_KEYS.map((k) => `<label><input type="checkbox" value="${k}"
    ${settings.chains.includes(k) ? "checked" : ""}> ${CHAINS[k].name}</label>`).join("");
  $("#locMsg").textContent = settings.loc ? `Current: ${settings.loc.label}` : "";
}

function openSettings() { renderSettings(); $("#settings").showModal(); }

// ---- wiring ---------------------------------------------------------------------
function init() {
  document.querySelectorAll("nav.tabs button").forEach((b) => b.addEventListener("click", () => {
    document.querySelectorAll("nav.tabs button").forEach((x) => x.setAttribute("aria-selected", x === b));
    document.querySelectorAll(".view").forEach((v) => { v.hidden = v.id !== `view-${b.dataset.view}`; });
    window.scrollTo(0, 0);
  }));
  document.querySelectorAll(".pill[data-kind]").forEach((p) => p.addEventListener("click", () => {
    kindFilter = p.dataset.kind;
    document.querySelectorAll(".pill[data-kind]").forEach((x) => x.setAttribute("aria-pressed", x === p));
    renderDeals();
  }));
  $("#catFilters").addEventListener("click", (e) => {
    const chip = e.target.closest("[data-cat]");
    if (!chip) return;
    catFilter = chip.dataset.cat === catFilter ? "all" : chip.dataset.cat;   // tap again to clear
    store.set("category", catFilter);
    renderDeals();
    chip.scrollIntoView?.({ inline: "nearest", block: "nearest" });
  });
  $("#search").addEventListener("input", () => { clearTimeout(init.t); init.t = setTimeout(renderDeals, 200); });
  $("#locBtn").addEventListener("click", openSettings);
  $("#refreshBtn").addEventListener("click", () => refresh(true));
  $("#gpsBtn").addEventListener("click", useGps);
  $("#placeBtn").addEventListener("click", setPlace);
  $("#placeInput").addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); setPlace(); } });
  $("#radius").addEventListener("input", (e) => { $("#radiusVal").textContent = e.target.value; });
  $("#settings").addEventListener("close", () => {
    const radius = +$("#radius").value;
    const chains = [...document.querySelectorAll("#chainChecks input:checked")].map((i) => i.value);
    const changed = radius !== settings.radiusMiles || chains.join() !== settings.chains.join();
    settings.radiusMiles = radius;
    settings.chains = chains.length ? chains : DEFAULTS.chains;
    settings.hideFar = $("#hideFar").checked;
    saveSettings();
    renderLocBtn();
    if (changed && settings.loc) { stores = null; loadStores(false).then((s) => { stores = s; renderDeals(); renderStores(); }); }
    else renderDeals();
  });
  document.addEventListener("click", (e) => {
    const upc = e.target.closest("[data-upc]");
    if (upc) navigator.clipboard?.writeText(upc.dataset.upc).then(() => toast(`Copied ${upc.dataset.upc}`), () => toast(upc.dataset.upc));
    if (e.target.closest("[data-open-settings]")) openSettings();
  });

  $("#decStore").innerHTML = CHAIN_KEYS.map((k) => `<option value="${k}">${CHAINS[k].name}</option>`).join("");
  $("#decStore").addEventListener("change", renderDecode);
  $("#decPrice").addEventListener("input", renderDecode);
  renderTips();
  renderLocBtn();

  if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("sw.js").catch(() => {});
  if (settings.loc) refresh(false);
  else { renderDeals(); renderStores(); openSettings(); }
}

init();
