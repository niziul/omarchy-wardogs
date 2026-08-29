#!/usr/bin/env node
var assert = require("assert");
var fs = require("fs");
var path = require("path");
var D = require("../Details.js");

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

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name + ".html"), "utf8");
}

test("flightChunks returns [] for empty/non-flight html", function() {
  assert.deepStrictEqual(D.flightChunks(""), []);
  assert.deepStrictEqual(D.flightChunks("<html><body>hi</body></html>"), []);
});

test("flightChunks extracts the flight stream payload of a weapon page", function() {
  var chunks = D.flightChunks(fixture("ak74m"));
  assert.strictEqual(chunks.length, 1);
  assert.ok(chunks[0].indexOf('"id":"ak74m"') !== -1);
});

test("parseDetails returns null for missing args or gibberish", function() {
  assert.strictEqual(D.parseDetails(null, "ak74m"), null);
  assert.strictEqual(D.parseDetails("<html>no flight</html>", "ak74m"), null);
  assert.strictEqual(D.parseDetails(fixture("ak74m"), ""), null);
  assert.strictEqual(D.parseDetails(fixture("ak74m"), "no-such-item"), null);
});

test("parseDetails extracts the full normalized weapon object", function() {
  var d = D.parseDetails(fixture("ak74m"), "ak74m");
  assert.ok(d, "ak74m should parse");
  assert.strictEqual(d.id, "ak74m");
  assert.strictEqual(d.name, "AK74");
  assert.strictEqual(d.kind, "weapon");
  assert.strictEqual(d.type, "Assault Rifle");
  assert.strictEqual(d.role, "Infantry");
  assert.strictEqual(d.slot, "Primary");
  assert.strictEqual(d.caliber, "5.45x39mm");
  assert.strictEqual(d.price, 1600);
  assert.strictEqual(d.weight, 3);
  assert.strictEqual(d.accuracy, 0.825);
  assert.strictEqual(d.rpm, 650);
  assert.strictEqual(d.muzzleVelocity, 880);
  assert.strictEqual(d.effectiveRange, 500);
});

test("parseDetails exposes recoil/zoom/ads from baseAttrs", function() {
  var d = D.parseDetails(fixture("ak74m"), "ak74m");
  assert.strictEqual(d.vRecoil, 1);
  assert.strictEqual(d.hRecoil, 1);
  assert.strictEqual(d.zoom, 1.2);
  assert.strictEqual(d.ads, 0.45);
});

test("parseDetails reports fire modes and magazine count", function() {
  var d = D.parseDetails(fixture("ak74m"), "ak74m");
  assert.deepStrictEqual(d.fireModes, ["Auto", "Semi"]);
  assert.strictEqual(d.magazineCount, "3");
});

test("parseDetails recovers an embedded ammo item on an ammo page", function() {
  var d = D.parseDetails(fixture("545mm"), "545mm-armorpiercing");
  assert.ok(d, "embedded ammo should parse");
  assert.strictEqual(d.kind, "ammo");
});

test("parseDetails returns null for an item not embedded on its page", function() {
  // The 545mm page embeds AP/tracer variants but not the base 545mm item.
  assert.strictEqual(D.parseDetails(fixture("545mm"), "545mm"), null);
});

test("normalizeDetail tolerates a partial/empty object", function() {
  var d = D.normalizeDetail({});
  assert.strictEqual(d.id, "");
  assert.strictEqual(d.name, "");
  assert.strictEqual(d.price, null);
  assert.strictEqual(d.description, "");
  assert.strictEqual(d.magazineCount, "");
});

if (failed > 0) {
  console.error("\n" + failed + " failure(s)");
  process.exit(1);
}
