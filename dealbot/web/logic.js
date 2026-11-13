// Deal-finding logic for the phone app. A JavaScript port of the Python package
// (dealbot/chains.py, pricing.py, extract.py, finder.py): keep the two in step.

export const CHAINS = {
  dollar_general: { name: "Dollar General", aliases: [/dollar\s*general/i, /\bDG\b(?!\s*\d)/], osm: ["Dollar General"] },
  home_depot: { name: "Home Depot", aliases: [/home\s*depot/i, /\bTHD\b/], osm: ["The Home Depot", "Home Depot"] },
  walmart: { name: "Walmart", aliases: [/wal-?\s?mart/i], osm: ["Walmart", "Walmart Supercenter", "Walmart Neighborhood Market"] },
  target: { name: "Target", aliases: [/\btarget\b/i], osm: ["Target"] },
  costco: { name: "Costco", aliases: [/costco/i], osm: ["Costco", "Costco Wholesale"] },
  lowes: { name: "Lowe's", aliases: [/\blowe'?s\b/i], osm: ["Lowe's", "Lowe's Home Improvement"] },
  family_dollar: { name: "Family Dollar", aliases: [/family\s*dollar/i], osm: ["Family Dollar"] },
  dollar_tree: { name: "Dollar Tree", aliases: [/dollar\s*tree/i], osm: ["Dollar Tree"] },
  cvs: { name: "CVS", aliases: [/\bcvs\b/i], osm: ["CVS Pharmacy", "CVS"] },
  walgreens: { name: "Walgreens", aliases: [/walgreens/i], osm: ["Walgreens"] },
};
export const CHAIN_KEYS = Object.keys(CHAINS);

export function detectChains(text, enabled = CHAIN_KEYS) {
  return enabled.filter((k) => CHAINS[k] && CHAINS[k].aliases.some((re) => re.test(text)));
}

export function chainForOsm(tags, enabled = CHAIN_KEYS) {
  for (const field of ["brand", "name", "operator"]) {
    const v = (tags[field] || "").trim().toLowerCase();
    if (!v) continue;
    for (const k of enabled) {
      if (CHAINS[k]?.osm.some((n) => v === n.toLowerCase() || v.startsWith(n.toLowerCase() + " "))) return k;
    }
  }
  return null;
}

// ---- price-tag decoder (community rules, not official) -------------------------
export function decodePrice(chain, price) {
  if (!(price > 0)) return [];
  const total = Math.round(price * 100);
  if (total === 1) return [{ kind: "penny", note: "Rings up at $0.01: a penny item.", strength: 3 }];
  const c = total % 100, last = c % 10, out = [];
  if (chain === "home_depot") {
    if (last === 3) out.push({ kind: "final_markdown", strength: 2, note: "Ends in 3: final clearance markdown. Often the last price before it goes to a penny." });
    else if (last === 6) out.push({ kind: "markdown", strength: 1, note: "Ends in 6: first clearance markdown; expect another drop to a price ending in 3." });
  } else if (chain === "target") {
    const pct = { 8: 30, 6: 50, 4: 70 }[last];
    if (pct) out.push({ kind: pct === 70 ? "final_markdown" : "clearance", pct, strength: pct >= 50 ? 2 : 1,
      note: `Ends in ${last}: about ${pct}% off clearance.` + (pct === 70 ? " Usually the final markdown." : "") });
    else if (last === 9) out.push({ kind: "regular", strength: 0, note: "Ends in 9: regular price." });
  } else if (chain === "walmart") {
    if (last === 0 && c !== 0) out.push({ kind: "clearance", strength: 1, note: "Ends in 0: probably clearance (rollbacks don't)." });
    else if (c === 0 && price < 10) out.push({ kind: "clearance", strength: 1, note: "Whole-dollar price under $10: possible clearance." });
  } else if (chain === "costco") {
    if (c === 97) out.push({ kind: "final_markdown", strength: 2, note: "Ends in .97: clearance markdown. An asterisk on the tag means discontinued." });
    else if (c === 0 || c === 88) out.push({ kind: "markdown", strength: 2, note: `Ends in .${String(c).padStart(2, "0")}: manager markdown on this store's stock.` });
    else if (c === 49 || c === 79) out.push({ kind: "markdown", strength: 1, note: `Ends in .${c}: manufacturer deal price.` });
  } else if (chain === "lowes") {
    if (last === 0 && c !== 0) out.push({ kind: "clearance", strength: 1, note: "Ends in 0 on a yellow tag: probably clearance." });
  }
  return out;
}

export const TIPS = {
  dollar_general: [
    "The community penny list usually takes effect early Tuesday morning; stores pull the items that day.",
    "Penny items aren't tagged. Scan barcodes in the DG app or at a price checker to confirm $0.01.",
    "Stores may refuse to sell penny items. Ask politely and accept a no.",
  ],
  home_depot: [
    "Clearance prices ending in .06 drop to .03, then to $0.01, which means the item gets pulled.",
    "The Home Depot app's in-store price can be lower than the shelf tag. Scan first.",
  ],
  target: [
    "Clearance stickers usually step 30% → 50% → 70% off, shown by prices ending in 8, 6, 4.",
    "Each department marks down on its own weekday; ask a team member which day yours is.",
  ],
  walmart: [
    "Clearance prices often end in 0. The yellow tag's date shows when it was marked down.",
    "Scan items in the Walmart app; hidden clearance often rings up below the shelf price.",
  ],
  costco: [
    "Prices ending .97 are clearance. An asterisk (*) in the tag's corner means it won't be restocked.",
    "Prices ending .00 or .88 are manager markdowns at that one warehouse.",
  ],
};

// ---- text extraction ---------------------------------------------------------
const PRICE_RE = /(^|[^\w.])\$\s?(\d{1,4}(?:,\d{3})*(?:\.\d{1,2})?)(?!\d)/g;
const CENTS_RE = /(^|[^\w.$])(\d{1,2})\s?(?:¢|cents?\b)/gi;
const PENNY_RE = /\bpenn(?:y|ies)\s*(?:list|item|items|find|finds|deal|deals|shopping|haul|day)\b|\$0?\.01\b|(^|\D)1\s?¢|\bone[\s-]cent\b|\bpenny(?:'d|ed)\b|\bwent to (?:a )?penny\b/i;
const PCT_RE = /(\d{1,2}(?:\.\d)?)\s?%\s?off/gi;
const CLEARANCE_RE = /\bclearance\b|\bmark(?:ed)?\s*down\b|\bmarkdowns?\b|\bhidden clearance\b|\bliquidat\w+|\bclose[\s-]?out\b/i;
const UPC_RE = /(^|\D)(\d{12})(?!\d)/g;

export const US_STATES = {
  AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California", CO: "Colorado",
  CT: "Connecticut", DE: "Delaware", FL: "Florida", GA: "Georgia", HI: "Hawaii", ID: "Idaho",
  IL: "Illinois", IN: "Indiana", IA: "Iowa", KS: "Kansas", KY: "Kentucky", LA: "Louisiana",
  ME: "Maine", MD: "Maryland", MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi",
  MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire", NJ: "New Jersey",
  NM: "New Mexico", NY: "New York", NC: "North Carolina", ND: "North Dakota", OH: "Ohio", OK: "Oklahoma",
  OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina", SD: "South Dakota",
  TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont", VA: "Virginia", WA: "Washington",
  WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming", DC: "District of Columbia",
};
const STATE_ABBR = Object.fromEntries(Object.entries(US_STATES).map(([k, v]) => [v.toLowerCase(), k]));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export function cleanText(raw) {
  const s = String(raw || "").replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
    .replace(/&#39;|&#x27;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n));
  return s.replace(/\s+/g, " ").trim();
}

export function findPrices(text) {
  const out = [];
  for (const m of text.matchAll(PRICE_RE)) out.push(parseFloat(m[2].replace(/,/g, "")));
  for (const m of text.matchAll(CENTS_RE)) out.push(parseInt(m[2], 10) / 100);
  return [...new Set(out)];
}

export function mentionsLocation(text, loc) {
  if (!loc) return false;
  if (loc.city && new RegExp(`\\b${esc(loc.city)}\\b`, "i").test(text)) return true;
  if (loc.state) {
    if (new RegExp(`\\b${esc(loc.state)}\\b`, "i").test(text)) return true;
    const abbr = STATE_ABBR[loc.state.toLowerCase()];
    if (abbr && new RegExp(`,\\s*${abbr}\\b|\\b${abbr}\\s+\\d{5}\\b`).test(text)) return true;
  }
  return false;
}

export function enrich(deal, enabled = CHAIN_KEYS, loc = null) {
  const blob = `${deal.title} ${deal.text || ""}`;
  deal.chains = detectChains(blob, enabled);
  deal.prices = findPrices(blob);
  const pcts = [...blob.matchAll(PCT_RE)].map((m) => parseFloat(m[1])).filter((p) => p > 0 && p < 100);
  deal.percentOff = pcts.length ? Math.max(...pcts) : null;
  deal.upcs = [...new Set([...blob.matchAll(UPC_RE)].map((m) => m[2]))].sort();
  deal.localMention = mentionsLocation(blob, loc);
  let strongest = 0;
  deal.priceNotes = [];
  for (const chain of deal.chains) for (const price of deal.prices) for (const s of decodePrice(chain, price)) {
    if (s.kind === "regular") continue;
    deal.priceNotes.push(`$${price.toFixed(2)} at ${CHAINS[chain].name}: ${s.note}`);
    strongest = Math.max(strongest, s.strength);
  }
  if (PENNY_RE.test(blob) || deal.prices.includes(0.01)) deal.kind = "penny";
  else if (CLEARANCE_RE.test(blob) || (deal.percentOff || 0) >= 50 || strongest >= 2) deal.kind = "clearance";
  else if (deal.percentOff || deal.priceNotes.length) deal.kind = "sale";
  else deal.kind = "other";
  return deal;
}

// ---- scoring & ranking -------------------------------------------------------
const KIND_BASE = { penny: 60, clearance: 30, sale: 15, other: 0 };
export const DEFAULTS = {
  radiusMiles: 10, chains: CHAIN_KEYS.slice(0, 8), maxAgeDays: 7, minScore: 25,
  pennyOnly: false, keywords: [], excludeKeywords: ["penny stock", "penny stocks", "crypto"],
  requireNearbyStore: true,
};

export function scoreDeal(d, cfg, now) {
  let s = KIND_BASE[d.kind] || 0;
  s += Math.min(40, (d.percentOff || 0) * 0.4);
  if (d.priceNotes.length) s += 10;
  if (d.upcs.length) s += 5;
  if (d.localMention) s += 15;
  if (d.nearestStore && cfg.radiusMiles > 0) s += 15 * Math.max(0, 1 - d.nearestStore.distanceMiles / cfg.radiusMiles);
  if (!d.chains.length) s -= 10;
  if (d.published) {
    const ageDays = Math.max(0, (now - d.published) / 86400000);
    s *= Math.max(0.3, 1 - (0.7 * ageDays) / Math.max(1, cfg.maxAgeDays));
  }
  return Math.round(s * 10) / 10;
}

const matchesAny = (text, words) => words.some((w) => w && new RegExp(`\\b${esc(w)}\\b`, "i").test(text));

/** stores === null means the store lookup was skipped or failed: keep every chain. */
export function rankDeals(deals, cfg, loc, stores, now = Date.now()) {
  const nearest = {};
  for (const st of stores || []) if (!nearest[st.chain] || st.distanceMiles < nearest[st.chain].distanceMiles) nearest[st.chain] = st;
  const out = [];
  for (const d of deals) {
    enrich(d, cfg.chains, loc);
    const blob = `${d.title} ${d.text || ""}`;
    if (d.published && (now - d.published) / 86400000 > cfg.maxAgeDays) continue;
    if (matchesAny(blob, cfg.excludeKeywords || [])) continue;
    if (cfg.keywords?.length && !matchesAny(blob, cfg.keywords)) continue;
    if (cfg.pennyOnly && d.kind !== "penny") continue;
    d.nearestStore = null;
    if (d.chains.length && stores) {
      const near = d.chains.map((c) => nearest[c]).filter(Boolean);
      if (!near.length && cfg.requireNearbyStore) continue;
      d.nearestStore = near.sort((a, b) => a.distanceMiles - b.distanceMiles)[0] || null;
    }
    d.score = scoreDeal(d, cfg, now);
    if (d.score >= cfg.minScore) out.push(d);
  }
  return out.sort((a, b) => b.score - a.score);
}

// ---- geo & parsing of API responses --------------------------------------------
export function haversineMiles(lat1, lon1, lat2, lon2) {
  const r = 3958.8, rad = Math.PI / 180;
  const dp = (lat2 - lat1) * rad, dl = (lon2 - lon1) * rad;
  const a = Math.sin(dp / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dl / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

export function overpassQuery(lat, lon, radiusMiles, chains) {
  const names = [...new Set(chains.flatMap((k) => CHAINS[k]?.osm || []))].sort();
  const alt = names.map((n) => n.replace("'", "'?")).join("|");
  const r = Math.round(radiusMiles * 1609.344);
  return `[out:json][timeout:25];(nwr["shop"]["brand"~"^(${alt})$",i](around:${r},${lat},${lon});` +
    `nwr["shop"]["name"~"^(${alt})",i](around:${r},${lat},${lon}););out center tags;`;
}

export function parseOverpass(payload, origin, chains) {
  const stores = new Map();
  for (const el of payload.elements || []) {
    const tags = el.tags || {};
    const chain = chainForOsm(tags, chains);
    if (!chain) continue;
    const lat = el.lat ?? el.center?.lat, lon = el.lon ?? el.center?.lon;
    if (lat == null || lon == null) continue;
    const street = [tags["addr:housenumber"], tags["addr:street"]].filter(Boolean).join(" ");
    const address = [street, tags["addr:city"]].filter(Boolean).join(", ");
    stores.set(`${chain}:${lat.toFixed(4)}:${lon.toFixed(4)}`, {
      chain, name: tags.name || CHAINS[chain].name, lat, lon, address,
      distanceMiles: haversineMiles(origin.lat, origin.lon, lat, lon),
    });
  }
  return [...stores.values()].sort((a, b) => a.distanceMiles - b.distanceMiles);
}

export function parseReddit(payload) {
  return (payload?.data?.children || []).map((c) => c.data || {}).filter((d) => d.id && !d.over_18).map((d) => ({
    id: `reddit:${d.id}`,
    title: cleanText(d.title),
    url: `https://www.reddit.com${d.permalink || ""}`,
    source: `r/${d.subreddit || "?"}`,
    text: cleanText(d.selftext).slice(0, 4000),
    published: d.created_utc ? d.created_utc * 1000 : null,
  }));
}

export function placeFromNominatim(r) {
  const a = r.address || {};
  return {
    lat: parseFloat(r.lat), lon: parseFloat(r.lon),
    city: a.city || a.town || a.village || a.hamlet || "",
    state: a.state || "",
    label: [a.city || a.town || a.village || a.hamlet, a.state && (STATE_ABBR[a.state.toLowerCase()] || a.state)].filter(Boolean).join(", ") || r.display_name || "",
  };
}
