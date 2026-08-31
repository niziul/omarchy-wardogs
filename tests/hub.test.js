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
  assert.strictEqual(b.board.cols, 3);
  assert.strictEqual(b.board.rows, 5);
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
  var empty = H.parseHubBuild("<html>no push rows</html>");
  assert.strictEqual(empty === null || empty.board === null, true);
});

test("hubRoles exposes the fixed role set", function () {
  assert.deepStrictEqual(H.hubRoles(), ["Infantry", "Medic", "Recon", "Driver", "Support", "Pilot"]);
});

test("ageDays reads h/d ages and treats unknown as ancient", function () {
  assert.strictEqual(H.ageDays("1d"), 1);
  assert.strictEqual(H.ageDays("12h"), 0.5);
  assert.strictEqual(H.ageDays("3d"), 3);
  assert.strictEqual(H.ageDays(""), 999);
  assert.strictEqual(H.ageDays("soon"), 999);
});

test("filterBuilds searches case-insensitively across fields", function () {
  var builds = H.parseHubList(fixture("hub-list.html"));
  var hits = H.filterBuilds(builds, "mosin", "", "");
  assert.ok(hits.length >= 1);
  hits.forEach(function (b) {
    var hay = (b.title + " " + b.author + " " + b.weapon + " " + b.role).toLowerCase();
    assert.ok(hay.indexOf("mosin") !== -1, "non-match leaked: " + b.title);
  });
  assert.strictEqual(H.filterBuilds(builds, "zzz-nope", "", "").length, 0);
});

test("filterBuilds filters by role and sorts top/hot", function () {
  var builds = H.parseHubList(fixture("hub-list.html"));
  var recon = H.filterBuilds(builds, "", "Recon", "");
  recon.forEach(function (b) {
    assert.strictEqual(b.role.toLowerCase(), "recon");
  });
  var top = H.filterBuilds(builds, "", "", "top");
  for (var i = 1; i < top.length; i++) {
    assert.ok((top[i - 1].score || 0) >= (top[i].score || 0), "top order broken at " + i);
  }
  // new: strictly non-decreasing age across the list
  var fresh = H.filterBuilds(builds, "", "", "new");
  for (var j = 1; j < fresh.length; j++) {
    assert.ok(H.ageDays(fresh[j - 1].age) <= H.ageDays(fresh[j].age), "new order broken at " + j);
  }
  // hot: a same-day build with any score outranks an older one at 0
  var hot = H.filterBuilds(builds, "", "", "hot");
  assert.strictEqual(hot[0].age, "1d");
  assert.strictEqual(H.filterBuilds([], "x", "Recon", "hot").length, 0);
});

test("buildToDetail maps a card onto the compare Basics schema", function () {
  var builds = H.parseHubList(fixture("hub-list.html"));
  var d = H.buildToDetail(builds[0]);
  assert.strictEqual(d.id, "ac8ef1364c");
  assert.strictEqual(d.name, "NINJA");
  assert.strictEqual(d.type, "Recon");
  assert.strictEqual(d.price, 9225);
  assert.strictEqual(d.weight, 7.4);
  assert.strictEqual(d.items, 38);
  assert.strictEqual(d.score, 1);
  assert.strictEqual(H.buildToDetail(null), null);
});

if (failed > 0) {
  console.error("\n" + failed + " failure(s)");
  process.exit(1);
}
