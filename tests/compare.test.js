#!/usr/bin/env node
var assert = require("assert");
var C = require("../Compare.js");

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

// Hand-built normalized detail objects (shape of Details.normalizeDetail).
var ak74 = {
  id: "ak74m", name: "AK74", kind: "weapon", type: "Assault Rifle",
  price: 1600, weight: 3, accuracy: 0.825, rpm: 650,
  muzzleVelocity: 880, effectiveRange: 500, vRecoil: 1, hRecoil: 1,
  zoom: 1.2, ads: 0.45
};
var a91 = {
  id: "a91", name: "A-91", kind: "weapon", type: "Assault Rifle",
  price: 0, weight: 3.17, accuracy: 1.5, rpm: 700,
  muzzleVelocity: 715, effectiveRange: 300, vRecoil: 1, hRecoil: 1,
  zoom: 1.2, ads: 0.525
};

test("fieldCount/fieldAt expose the fixed compare schema", function() {
  assert.strictEqual(C.fieldCount(), 12);
  var f = C.fieldAt(0);
  assert.strictEqual(f.key, "price");
  assert.strictEqual(f.label, "Price");
  assert.strictEqual(C.fieldAt(99), null);
  assert.strictEqual(C.fieldAt(-1), null);
});

test("rowActive is true when at least one side has a number", function() {
  var price = C.fieldAt(0);
  assert.ok(C.rowActive(price, ak74, a91));
  assert.ok(C.rowActive(price, ak74, null));
  assert.ok(!C.rowActive(price, null, null));
  // A field neither carries.
  var rpm = C.fieldAt(3);
  assert.ok(!C.rowActive(rpm, {}, {}));
});

test("valueText formats numbers with prefix/unit and blanks missing", function() {
  var price = C.fieldAt(0);
  var weight = C.fieldAt(1);
  var ads = C.fieldByKey("ads");
  assert.strictEqual(C.valueText(ak74, price), "$1,600"); // matches header formatPrice
  assert.strictEqual(C.valueText(a91, price), "$0");
  assert.strictEqual(C.valueText(ak74, weight), "3 kg");
  assert.strictEqual(C.valueText({ weight: 3.17 }, weight), "3.17 kg");
  assert.strictEqual(C.valueText({ weight: 0.30000000000000004 }, weight), "0.3 kg"); // no float tails
  assert.strictEqual(C.valueText({ ads: 0.45 }, ads), "0.45 s");
  assert.strictEqual(C.valueText(null, price), "");
  assert.strictEqual(C.valueText({}, price), "");
});

test("betterSide respects higher-is-better fields", function() {
  var accuracy = C.fieldByKey("accuracy");
  var rpm = C.fieldByKey("rpm");
  assert.strictEqual(C.betterSide(accuracy, ak74, a91), "right"); // 1.5 > 0.825
  assert.strictEqual(C.betterSide(rpm, ak74, a91), "right");      // 700 > 650
  assert.strictEqual(C.betterSide(accuracy, a91, ak74), "left");
});

test("betterSide respects lower-is-better fields", function() {
  var price = C.fieldAt(0);
  var weight = C.fieldAt(1);
  var ads = C.fieldByKey("ads");
  assert.strictEqual(C.betterSide(price, ak74, a91), "right");   // 0 < 1600
  assert.strictEqual(C.betterSide(weight, ak74, a91), "left");   // 3 < 3.17
  assert.strictEqual(C.betterSide(ads, ak74, a91), "left");      // 0.45 faster
});

test("betterSide is '' on tie or missing", function() {
  var recoil = C.fieldByKey("vRecoil");
  assert.strictEqual(C.betterSide(recoil, ak74, a91), ""); // both 1
  assert.strictEqual(C.betterSide(recoil, null, a91), "");
  assert.strictEqual(C.betterSide(recoil, {}, {}), "");
});

test("formatPrice renders thousands separators and blanks non-numbers", function() {
  assert.strictEqual(C.formatPrice(12500), "$12,500");
  assert.strictEqual(C.formatPrice(0), "$0");
  assert.strictEqual(C.formatPrice(999), "$999");
  assert.strictEqual(C.formatPrice(-1250), "-$1,250");
  assert.strictEqual(C.formatPrice(null), "");
  assert.strictEqual(C.formatPrice("7000"), "");
});

test("groups cover every field and resolve to field objects", function() {
  assert.strictEqual(C.groupCount(), 4);
  var covered = [];
  for (var g = 0; g < C.groupCount(); g++) {
    var grp = C.groupAt(g);
    assert.ok(grp && grp.label && grp.fields.length > 0, "group " + g + " malformed");
    grp.fields.forEach(function(f) { covered.push(f.key); });
  }
  assert.deepStrictEqual(covered, ["price", "weight", "items", "score", "accuracy", "rpm", "muzzleVelocity", "effectiveRange", "vRecoil", "hRecoil", "zoom", "ads"]);
  assert.strictEqual(C.groupAt(99), null);
});

test("item compares hide build-only rows", function() {
  var items = C.fieldAt(2); // items
  var score = C.fieldAt(3); // score
  assert.strictEqual(C.rowActive(items, ak74, a91), false);
  assert.strictEqual(C.rowActive(score, ak74, a91), false);
  // basics group for two items: price+weight only
  var basics = C.groupAt(0);
  var active = basics.fields.filter(function(f) { return C.rowActive(f, ak74, a91); });
  assert.deepStrictEqual(active.map(function(f) { return f.key; }), ["price", "weight"]);
});

test("groupActive hides groups with no numbers on either side", function() {
  var basics = C.groupAt(0);
  var ballistics = C.groupAt(1);
  var optics = C.groupAt(3);
  // Vehicle detail: only price is numeric.
  var vehicle = { id: "ah6m", name: "AH-6M", type: "Air Rotary", price: 7000 };
  assert.strictEqual(C.groupActive(basics, vehicle, null), true);
  assert.strictEqual(C.groupActive(ballistics, vehicle, null), false);
  // Both sides numeric in optics.
  assert.strictEqual(C.groupActive(optics, ak74, a91), true);
  assert.strictEqual(C.groupActive(null, ak74, a91), false);
  assert.strictEqual(C.groupActive(optics, null, null), false);
});

if (failed > 0) {
  console.error("\n" + failed + " failure(s)");
  process.exit(1);
}
