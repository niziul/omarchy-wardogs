// parseBaseList: window/anchor pairing against card metadata
const assert = require("assert");
const fs = require("fs");
const B = require("../Base.js");
const H = require("../Hub.js");

let page = "";
try {
  page = fs.readFileSync("/tmp/opencode/base-hub.html", "utf8");
} catch (e) {
  page = "";
}

// ---------- fixture-driven pieces (no network needed) ----------
{
  // synthetic card document exercising every optional field
  const card = (id, title, author, age, fobs, comments, wall, supplies, pieces) =>
    `<a href="/loadouts/base/hub/${id}"><h3 class="truncate font-display text-base font-semibold text-wd-text transition-colors group-hover:text-wd-gold">${title}</h3>` +
    `<span class="flex items-center gap-1.5"><img class="rounded-full" src="x"/>${author}</span>` +
    `<span class="text-wd-text-mute">${age}</span>` +
    `<span class="text-wd-text-mute">${fobs}<!-- --> FOB</span>` +
    (comments
      ? `<span class="flex items-center gap-1 text-wd-text-mute"><svg viewBox="0 0 24 24" aria-hidden="true" class="h-3 w-3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5.5h16v11H10l-4.5 4v-4H4z"></path><path d="M8 9.5h8M8 12.5h5"></path></svg>${comments}</span>`
      : "") +
    (wall
      ? `<span class="truncate text-wd-text-mute">mostly <!-- -->${wall}</span>`
      : "") +
    `<div class="shrink-0 text-end"><div class="wd-num text-sm leading-none text-wd-gold">${supplies}</div><div class="wd-label">SUPPLIES</div><div class="piece">${pieces}<!-- --> PIECES</div></div>`;

  const html =
    card("aaaaaaaaaa", "Alpha Base", "Inset", "3d", 1, 1, "Barbed Wire", "2,772", 193) +
    card("bbbbbbbbbb", "Beta Fort", "Garen", "4d", 2, 0, "", "3,664", 250) +
    card("cccccccccc", "Gamma Hold", "Sitka", "5d", 1, 0, "", "4,261", 142);

  const rows = B.dedupeBuilds(B.parseBaseList(html));
  assert.strictEqual(rows.length, 3, "card count");
  assert.strictEqual(rows[0].id, "aaaaaaaaaa");
  assert.strictEqual(rows[0].title, "Alpha Base");
  assert.strictEqual(rows[0].author, "Inset");
  assert.strictEqual(rows[0].age, "3d");
  assert.strictEqual(rows[0].fobs, 1);
  assert.strictEqual(rows[0].comments, 1);
  assert.strictEqual(rows[0].wall, "Barbed Wire");
  assert.strictEqual(rows[0].supplies, 2772);
  assert.strictEqual(rows[0].pieces, 193);
  assert.strictEqual(rows[1].comments, 0, "no comment svg -> 0");
  assert.strictEqual(rows[2].wall, "", "wall absent -> empty");
}

// ---------- live payload (when present) ----------
if (page !== "") {
  const builds = B.dedupeBuilds(B.parseBaseList(page));
  assert.ok(builds.length >= 20, "expected a full page of cards, got " + builds.length);
  assert.strictEqual(builds[0].id, "c0dadbf000");
  assert.strictEqual(builds[0].author, "Inset");
  assert.strictEqual(builds[0].supplies, 2772);
  assert.strictEqual(builds[0].pieces, 193);
  assert.ok(builds[0].wall.length > 0, "wall parsed");
}

// ---------- detail: live payload ----------
{
  const html = fs.readFileSync("/tmp/opencode/base-detail.html", "utf8");
  const d = B.parseBaseDetail(html);
  assert.ok(d !== null, "detail parses");
  assert.strictEqual(d.id, "c0dadbf000");
  assert.strictEqual(d.title, "Small Fortress");
  assert.strictEqual(d.author, "Inset");
  assert.strictEqual(d.wall, "Barbed Wire");
  assert.strictEqual(d.shapes.length, 193);
  assert.strictEqual(d.manifest.length, 11);
  assert.strictEqual(d.manifest[0].name, "Barbed Wire");
  assert.strictEqual(d.manifest[0].count, 93);
  assert.strictEqual(d.manifest[0].supplies, 651);
  assert.strictEqual(d.pieces, 193);
  assert.strictEqual(d.fobs, 1);
  assert.ok(d.view.w > 0 && d.view.h > 0, "view box parsed");
  assert.strictEqual(d.v, B.CACHE_VERSION);
  // shape sanity: first wall's points are finite numbers
  assert.ok(isFinite(d.shapes[0].pts[0][0]) && isFinite(d.shapes[0].pts[0][1]));
}

console.log("ok  Base.js parses list + detail fixtures");
