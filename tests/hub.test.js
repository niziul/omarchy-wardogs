#!/usr/bin/env node
var assert = require("assert");
var H = require("../Hub.js");
var fs = require("fs");
var path = require("path");

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
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8");
}

test("parseHubList extracts builds with all card fields", function () {
  var builds = H.parseHubList(fixture("hub-list.html"));
  assert.ok(builds.length >= 20, "expected a full page of builds, got " + builds.length);
  var first = builds[0];
  assert.strictEqual(first.id, "ac8ef1364c");
  assert.strictEqual(first.score, 1);
  assert.strictEqual(first.title, "NINJA");
  assert.ok(first.author.length > 0, "author missing");
  assert.strictEqual(first.age, "1d");
  assert.strictEqual(first.role, "Recon");
  assert.strictEqual(first.weapon, "Compound Bow");
  assert.strictEqual(first.iconId, "combatbow");
  assert.strictEqual(first.cost, "$9,225");
  assert.strictEqual(first.weight, "7.4");
  assert.strictEqual(first.items, "38");
  // every build carries the fields the hub list renders
  builds.forEach(function (b) {
    assert.ok(b.id && b.title && b.iconId && b.cost, "incomplete build card: " + JSON.stringify(b));
  });
});

test("parseHubList tolerates empty/garbage input", function () {
  assert.deepStrictEqual(H.parseHubList(""), []);
  assert.deepStrictEqual(H.parseHubList(null), []);
  assert.deepStrictEqual(H.parseHubList("<html>nothing</html>"), []);
});

test("parseHubBuild extracts header, totals and role", function () {
  var b = H.parseHubBuild(fixture("hub-build.html"));
  assert.strictEqual(b.title, "NINJA");
  assert.strictEqual(b.description, "Built around the Compound Bow.");
  assert.strictEqual(b.role, "Recon");
  assert.strictEqual(b.cost, "$9,225");
  assert.strictEqual(b.weight, "7.43"); // client prop weightKg
  assert.strictEqual(b.itemsCarried, "38");
});

test("parseHubBuild slots: sections, ids, prices and weights", function () {
  var b = H.parseHubBuild(fixture("hub-build.html"));
  var byName = {};
  b.slots.forEach(function (s) { byName[s.name] = s; });
  assert.strictEqual(b.slots.length, 13, "unexpected slot count");

  var bow = byName["Compound Bow"];
  assert.strictEqual(bow.section, "Equipment");
  assert.strictEqual(bow.key, "primary");
  assert.strictEqual(bow.itemId, "combatbow");
  assert.strictEqual(bow.price, "$800");
  assert.strictEqual(bow.weight, 1.3);

  assert.strictEqual(byName["Monocular"].key, "specialist");
  assert.strictEqual(byName["Monocular"].price, "$150");
  assert.strictEqual(byName["Ghillie Body Suit"].section, "Gear");
  assert.strictEqual(byName["Ghillie Body Suit"].price, "$3,000");
  assert.strictEqual(byName["Ghillie Body Suit"].weight, 1.5);
  assert.strictEqual(byName["Operator Backpack"].section, "Storage");
  assert.strictEqual(byName["Operator Backpack"].price, "$800");
  assert.strictEqual(byName["Medium Tac Vest"].weight, 1.65);

  // traversal consumables: repeated arrow stacks share the item id
  var arrows = b.slots.filter(function (s) { return s.name === "Broadhead Arrow"; });
  assert.strictEqual(arrows.length, 4, "expected 4 arrow slots (mag + traversal)");
  assert.ok(arrows.every(function (s) { return s.itemId === "arrow"; }));

  // no nav garbage: every slot sits in a known section and has an id
  var known = ["Equipment", "Gear", "Storage", "Traversal"];
  b.slots.forEach(function (s) {
    assert.ok(known.indexOf(s.section) !== -1, "slot outside sections: " + s.name);
    assert.ok(s.itemId, "slot without id: " + s.name);
  });
});

test("parseHubBuild returns null on empty input", function () {
  assert.strictEqual(H.parseHubBuild(""), null);
  assert.strictEqual(H.parseHubBuild(null), null);
});

if (failed > 0) {
  console.error("\n" + failed + " failure(s)");
  process.exit(1);
}
