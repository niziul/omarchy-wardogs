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

if (failed) process.exit(1);
