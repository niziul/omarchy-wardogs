#!/usr/bin/env node
var assert = require("assert");
var M = require("../Model.js");

var failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log("ok  " + name);
  } catch (err) {
    failed++;
    console.error("FAIL " + name);
    console.error("    " + err.message);
  }
}

var sampleIndex = {
  items: [
    { id: "m4", name: "M4", kind: "weapon", type: "Assault Rifle", caliber: "5.56x45mm" },
    { id: "ak74m", name: "AK74", kind: "weapon", type: "Assault Rifle", caliber: "5.45x39mm" },
    { id: "pkm", name: "PKM", kind: "weapon", type: "LMG", caliber: "7.62x54mm" },
    { id: "ammo_01", name: "5.56 FMJ", kind: "ammo", type: "Rifle", caliber: "5.56x45mm" },
    { id: "ak74mmag", name: "AK74 30 RND Magazine", kind: "ammo", type: "Magazine", caliber: "5.45x39mm" }
  ]
};

test("parseIndex returns [] on invalid json", function() {
  assert.deepStrictEqual(M.parseIndex("not-json"), []);
});

test("parseIndex skips entries without id/name and localizes fields", function() {
  var parsed = M.parseIndex(JSON.stringify({ items: [
    { id: "m4", name: "  M4  ", kind: "weapon", type: "Assault Rifle", caliber: "5.56x45mm" },
    { name: "no-id" },
    { id: "x" }
  ] }));
  assert.strictEqual(parsed.length, 1);
  assert.strictEqual(parsed[0].name, "M4");
  assert.strictEqual(parsed[0].id, "m4");
});

test("filterItems keeps matching kind and query, sorts by name", function() {
  var items = M.parseIndex(JSON.stringify(sampleIndex));
  var weapons = M.filterItems(items, "weapon", "");
  assert.strictEqual(weapons.length, 3);
  assert.strictEqual(weapons[0].name, "AK74");

  var fmj = M.filterItems(items, "", "5.56");
  assert.strictEqual(fmj.length, 2); // M4 + the ammo row (AK74 is 5.45, PKM is 7.62)

  var lmg = M.filterItems(items, "weapon", "PKM");
  assert.strictEqual(lmg.length, 1);
  assert.strictEqual(lmg[0].id, "pkm");
});

test("fuzzyScore matches in-order subsequences, rejects reordered ones", function() {
  assert.ok(M.fuzzyScore("amg", "ak74 30 rnd magazine") >= 0);
  assert.strictEqual(M.fuzzyScore("zg", "ak74 30 rnd magazine"), -1);
  assert.strictEqual(M.fuzzyScore("", "anything"), 0);
});

test("fuzzy scoring prefers word starts and contiguous runs", function() {
  // "ak" at the start of the haystack beats "ak" buried mid-string
  assert.ok(M.fuzzyScore("ak", "ak74 magazine") > M.fuzzyScore("ak", "xxak74 magazine"));
});

test("filterItems finds fuzzy (non-contiguous) matches, best first", function() {
  var items = M.parseIndex(JSON.stringify(sampleIndex));

  // "mag" only appears (in order) in the AK74 magazine row
  var mags = M.filterItems(items, "", "mag");
  assert.strictEqual(mags.length, 1);
  assert.strictEqual(mags[0].id, "ak74mmag");

  // "a74" spans "a…74" in both AK74 rows; scattered chars still match
  var aks = M.filterItems(items, "", "a74");
  assert.strictEqual(aks.length, 2);

  // a needle whose chars appear nowhere never matches
  assert.strictEqual(M.filterItems(items, "", "qq").length, 0);
});

test("itemCountByKind and kindsList order", function() {
  var items = M.parseIndex(JSON.stringify(sampleIndex));
  assert.strictEqual(M.itemCountByKind(items, "weapon"), 3);
  assert.deepStrictEqual(M.kindsList(items), ["weapon", "ammo"]);
});

test("kindLabel returns friendly title", function() {
  assert.strictEqual(M.kindLabel("weapon"), "Weapons");
  assert.strictEqual(M.kindLabel("unknown"), "Unknown");
});

test("itemUrl deep-links to the database and sanitizes ids", function() {
  assert.strictEqual(M.itemUrl("m4"), "https://wardogs.zone/database/m4");
  assert.strictEqual(M.itemUrl("a b/c"), "https://wardogs.zone/database/abc");
  assert.strictEqual(M.itemUrl(""), "https://wardogs.zone/database");
});

test("iconUrlFor builds /game/icons/{id}.png and sanitizes ids", function() {
  assert.strictEqual(M.iconUrlFor("a91"), "https://wardogs.zone/game/icons/a91.png");
  assert.strictEqual(M.iconUrlFor("wepn_030"), "https://wardogs.zone/game/icons/wepn_030.png");
  assert.strictEqual(M.iconUrlFor("a b/c"), "https://wardogs.zone/game/icons/abc.png");
  assert.strictEqual(M.iconUrlFor(""), "");
  assert.strictEqual(M.iconUrlFor(null), "");
});

test("iconFileName returns a safe local cache name", function() {
  assert.strictEqual(M.iconFileName("a91"), "a91.png");
  assert.strictEqual(M.iconFileName("x y"), "xy.png");
  assert.strictEqual(M.iconFileName(""), "");
});

test("parseHealth returns sane defaults on garbage and ok on valid", function() {
  var bad = M.parseHealth("nope");
  assert.strictEqual(bad.ok, false);
  assert.strictEqual(bad.version, "");

  var good = M.parseHealth(JSON.stringify({ ok: true, version: "0.17.0", build: "abc", env: "production" }));
  assert.strictEqual(good.ok, true);
  assert.strictEqual(good.version, "0.17.0");
});

test("shortVersion collapses to major.minor", function() {
  assert.strictEqual(M.shortVersion("0.17.0"), "0.17");
  assert.strictEqual(M.shortVersion("10.2.4"), "10.2");
  assert.strictEqual(M.shortVersion(""), "");
});

test("kindAndCaliber joins type and caliber", function() {
  assert.strictEqual(M.kindAndCaliber({ type: "Assault Rifle", caliber: "5.56x45mm" }), "Assault Rifle · 5.56x45mm");
  assert.strictEqual(M.kindAndCaliber({ type: "Weapon", caliber: "" }), "Weapon");
});

var sampleRss = [
  "<?xml version=\"1.0\"?>",
  "<rss><channel>",
  "<item><title>Hello &amp; World</title><link>https://wardogs.zone/news/hello</link>",
  "<guid>https://wardogs.zone/news/hello</guid>",
  "<pubDate>Tue, 25 Aug 2026 12:00:00 GMT</pubDate>",
  "<category>Game News</category>",
  "<description>A short &lt;preview&gt;.</description></item>",
  "<item><title></title><link>https://wardogs.zone/news/skip</link></item>",
  "<item><title>Second</title><link>https://wardogs.zone/news/second</link></item>",
  "</channel></rss>"
].join("");

test("parseRss extracts items and skips empty titles", function() {
  var rows = M.parseRss(sampleRss);
  assert.strictEqual(rows.length, 2);
  assert.strictEqual(rows[0].title, "Hello & World");
  assert.strictEqual(rows[0].link, "https://wardogs.zone/news/hello");
  assert.strictEqual(rows[0].category, "Game News");
  assert.strictEqual(rows[0].description, "A short <preview>.");
  assert.strictEqual(rows[1].title, "Second");
});

test("parseRss returns [] on garbage", function() {
  assert.deepStrictEqual(M.parseRss("not xml"), []);
  assert.deepStrictEqual(M.parseRss(""), []);
});

test("newestGuid is the first item's guid", function() {
  var rows = M.parseRss(sampleRss);
  assert.strictEqual(M.newestGuid(rows), "https://wardogs.zone/news/hello");
  assert.strictEqual(M.newestGuid([]), "");
});

test("relativeDate formats RFC-822 timestamps", function() {
  var now = Date.parse("Tue, 25 Aug 2026 12:00:00 GMT");
  assert.strictEqual(M.relativeDate("Tue, 25 Aug 2026 12:00:00 GMT", now), "just now");
  assert.strictEqual(M.relativeDate("Tue, 25 Aug 2026 11:00:00 GMT", now), "1h ago");
  assert.strictEqual(M.relativeDate("Mon, 24 Aug 2026 12:00:00 GMT", now), "1d ago");
  assert.strictEqual(M.relativeDate("not-a-date"), "not-a-date");
});

test("parseNewsCache round-trips a JSON array", function() {
  var rows = M.parseRss(sampleRss);
  var back = M.parseNewsCache(JSON.stringify(rows));
  assert.strictEqual(back.length, 2);
  assert.strictEqual(back[0].title, "Hello & World");
  assert.deepStrictEqual(M.parseNewsCache("nope"), []);
});

test("siteLinks returns the six wardogs.zone tool routes", function() {
  var links = M.siteLinks();
  assert.strictEqual(links.length, 6);
  assert.strictEqual(links[0].url, "https://wardogs.zone/loadouts");
  assert.ok(links[5].url.indexOf("community") !== -1);
  for (var i = 0; i < links.length; i++) {
    assert.ok(links[i].glyph && links[i].glyph.length > 0, "link " + i + " has a glyph");
    assert.ok(links[i].label && links[i].label.length > 0, "link " + i + " has a label");
  }
});

var subItems = [
  { id: "a", name: "A", kind: "weapon", type: "Assault Rifle" },
  { id: "b", name: "B", kind: "weapon", type: "Sniper Rifle" },
  { id: "c", name: "C", kind: "weapon", type: "Assault Rifle" },
  { id: "d", name: "D", kind: "weapon", type: "" },
  { id: "e", name: "E", kind: "ammo", type: "Assault Rifle" }
];

test("subcategories lists unique sorted types for a kind with counts", function() {
  var subs = M.subcategories(subItems, "weapon");
  assert.strictEqual(subs.length, 2);
  assert.deepStrictEqual(subs[0], { value: "Assault Rifle", count: 2 });
  assert.deepStrictEqual(subs[1], { value: "Sniper Rifle", count: 1 });
  var all = M.subcategories(subItems, "");
  assert.strictEqual(all.length, 2);
  assert.strictEqual(all[0].count, 3);
  assert.deepStrictEqual(M.subcategories([], "weapon"), []);
});

test("normalizeItem precomputes a lowercase haystack for the fuzzy find", function() {
  var it = M.normalizeItem({ id: "x", name: "AK-74M", type: "Assault Rifle", caliber: "5.45x39mm" });
  assert.ok(it._hay === "ak-74m assault rifle 5.45x39mm");
  // Hand-built items without _hay still match (fallback lowercases).
  assert.strictEqual(M.filterItems([{ id: "y", name: "AK-74M", type: "Assault Rifle" }], "", "ak"), 1);
});

test("filterItems with empty kind searches across all kinds", function() {
  // The popup passes kind "" while a query is active so fuzzy find spans
  // every category and subcategory.
  var rows = M.filterItems(subItems, "", "a");
  assert.strictEqual(rows.length, 3); // A, C (weapons) + E (ammo)
  var none = M.filterItems(subItems, "", "zz");
  assert.deepStrictEqual(none, []);
});

test("releaseCountdown formats the early access countdown like the f1 plugin", function() {
  var rel = new Date(2026, 8, 10).getTime(); // local midnight, like the model
  assert.strictEqual(M.releaseCountdown(rel - 13*86400000 - 3*3600000), "13d 3h");
  assert.strictEqual(M.releaseCountdown(rel - 5*3600000 - 3*60000), "5h 03m");
  assert.strictEqual(M.releaseCountdown(rel - 45*60000), "45m");
  assert.strictEqual(M.releaseCountdown(rel - 60000), "1m");
  assert.strictEqual(M.releaseCountdown(rel + 60000), "LIVE");
  assert.strictEqual(M.releaseCountdown(rel + 12*3600000), "LIVE");
  assert.strictEqual(M.releaseCountdown(rel + 2*86400000), "");
  assert.strictEqual(M.releaseCountdown(NaN) !== "", true);
});

test("bySubcategory filters by type and passes through on empty", function() {
  var base = M.filterItems(subItems, "weapon", "");
  assert.strictEqual(base.length, 4);
  var rifles = M.bySubcategory(base, "Assault Rifle");
  assert.strictEqual(rifles.length, 2);
  assert.deepStrictEqual(M.bySubcategory(base, ""), base);
  assert.deepStrictEqual(M.bySubcategory(base, "Shotgun"), []);
});

if (failed) process.exit(1);
