// Run with: node --test dealbot/web/tests/*.test.mjs
import assert from "node:assert/strict";
import test from "node:test";
import {
  chainForOsm, decodePrice, detectChains, enrich, findPrices, mentionsLocation, overpassQuery,
  parseOverpass, parseReddit, placeFromNominatim, rankDeals, DEFAULTS,
} from "../logic.js";

const ALL = ["dollar_general", "home_depot", "walmart", "target", "costco", "lowes"];
const NOW = Date.UTC(2026, 10, 13, 12);
const LOC = { lat: 36.16, lon: -86.78, label: "Nashville, TN", city: "Nashville", state: "Tennessee" };
const STORES = [
  { chain: "dollar_general", name: "Dollar General", lat: 36.17, lon: -86.78, address: "12 Main St", distanceMiles: 0.7 },
  { chain: "home_depot", name: "The Home Depot", lat: 36.3, lon: -86.78, address: "", distanceMiles: 9 },
];
const deal = (id, title, text = "", ageDays = 0) => ({ id: String(id), title, url: "u", source: "t", text, published: NOW - ageDays * 86400000 });

test("detects chains", () => {
  assert.deepEqual(detectChains("DG penny list for 11/11", ALL), ["dollar_general"]);
  assert.deepEqual(detectChains("dg lowercase", ALL), []);
  assert.deepEqual(detectChains("Home Depot and Lowes", ALL), ["home_depot", "lowes"]);
  assert.equal(chainForOsm({ brand: "The Home Depot" }, ALL), "home_depot");
  assert.equal(chainForOsm({ name: "Targeted Fitness" }, ALL), null);
});

test("finds prices", () => {
  assert.deepEqual(findPrices("was $12.97 now $3.03, also 1¢ and $1,200"), [12.97, 3.03, 1200, 0.01]);
  assert.deepEqual(findPrices("no money 12.03"), []);
});

test("decodes price tags like the Python version", () => {
  assert.equal(decodePrice("dollar_general", 0.01)[0].kind, "penny");
  assert.equal(decodePrice("home_depot", 12.03)[0].kind, "final_markdown");
  assert.equal(decodePrice("home_depot", 24.06)[0].kind, "markdown");
  assert.deepEqual(decodePrice("home_depot", 24.98), []);
  assert.equal(decodePrice("target", 7.04)[0].pct, 70);
  assert.equal(decodePrice("target", 7.99)[0].kind, "regular");
  assert.equal(decodePrice("costco", 9.97)[0].kind, "final_markdown");
  assert.equal(decodePrice("walmart", 4.5)[0].kind, "clearance");
  assert.deepEqual(decodePrice("walmart", 4.97), []);
});

test("location mentions", () => {
  assert.ok(mentionsLocation("found in nashville", LOC));
  assert.ok(mentionsLocation("Murfreesboro, TN", LOC));
  assert.ok(!mentionsLocation("TN letters", LOC));
});

test("enrich", () => {
  const d = enrich(deal(1, "DG penny list", "Tide 037000123456 rings up 1¢"), ALL);
  assert.equal(d.kind, "penny");
  assert.deepEqual(d.upcs, ["037000123456"]);
  assert.equal(enrich(deal(2, "Drill at Home Depot for $49.03"), ALL).kind, "clearance");
  assert.equal(enrich(deal(3, "Walmart 20% off coffee"), ALL).kind, "sale");
});

test("ranking filters and orders", () => {
  const cfg = { ...DEFAULTS, minScore: 0 };
  const ranked = rankDeals([
    deal(1, "Walmart 20% off coffee"),
    deal(2, "Dollar General penny list", "Tide 1¢ in Nashville"),
    deal(3, "Home Depot drill $49.03"),
    deal(4, "Dollar General penny list (old)", "", 10),
    deal(5, "Best penny stocks to buy"),
  ], cfg, LOC, STORES, NOW);
  assert.deepEqual(ranked.map((d) => d.id), ["2", "3"]);
  assert.equal(ranked[0].nearestStore.address, "12 Main St");
  assert.equal(rankDeals([deal(1, "Walmart clearance 75% off")], cfg, null, null, NOW).length, 1);
});

test("parses API responses", () => {
  const q = overpassQuery(36.16, -86.78, 5, ["dollar_general", "lowes"]);
  assert.ok(q.includes("around:8047,36.16,-86.78") && q.includes("Lowe'?s"));
  const stores = parseOverpass({ elements: [
    { lat: 36.17, lon: -86.78, tags: { brand: "Dollar General", "addr:housenumber": "12", "addr:street": "Main St" } },
    { center: { lat: 36.2, lon: -86.78 }, tags: { name: "Lowe's" } },
    { lat: 36.17, lon: -86.78, tags: { name: "Bob's Hardware" } },
  ] }, LOC, ["dollar_general", "lowes"]);
  assert.deepEqual(stores.map((s) => s.chain), ["dollar_general", "lowes"]);
  const [r] = parseReddit({ data: { children: [
    { data: { id: "a", title: "HD &amp; penny", permalink: "/r/x/a", subreddit: "x", created_utc: 1 } },
    { data: { id: "b", title: "t", over_18: true } },
  ] } });
  assert.equal(r.title, "HD & penny");
  assert.equal(placeFromNominatim({ lat: "1", lon: "2", address: { town: "Franklin", state: "Tennessee" } }).label, "Franklin, TN");
});
