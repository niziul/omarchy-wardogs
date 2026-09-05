// Wardogs Zone — pure parsers for the base-plan hub
// (https://wardogs.zone/loadouts/base/hub). The site is an RSC app: list
// pages carry a server-rendered DOM per search-result card, and detail
// pages stream a structured planning blob (per-piece drawing shapes and
// a supply manifest) inside the flight payload. No Qt, no network —
// unit-testable from node like Hub.js / Details.js.

// Bump when a parse-output shape changes so cached JSON from older code
// is discarded on read (same policy as Hub.js).
var CACHE_VERSION = 1

// --- list ------------------------------------------------------------------
// The server-rendered DOM carries one <article> per published base (~24 per
// page). Cards anchor on the <h3> title; the trailing metadata block after
// each h3 (author, age, FOB count, comments, wall type, supplies, pieces)
// belongs to that card, and the relative href carries the id — both anchor
// lists appear once per card in document order, so they pair by position.
function parseBaseList(html) {
  var out = [];
  var hrefRe = /href="\/loadouts\/base\/hub\/([a-z0-9]+)"/g;
  var ids = [];
  var mm;
  while ((mm = hrefRe.exec(html)) !== null)
    ids.push(mm[1]);
  if (ids.length === 0)
    return [];

  var h3Re = /<h3 class="truncate font-display text-base font-semibold text-wd-text[^"]*">([^<]+)<\/h3>/g;
  var h3s = [];
  while ((mm = h3Re.exec(html)) !== null)
    h3s.push({ title: mm[1], at: mm.index });
  if (h3s.length !== ids.length)
    return [];

  for (var i = 0; i < h3s.length; i++) {
    var w = html.substring(h3s[i].at, i + 1 < h3s.length ? h3s[i + 1].at : h3s[i].at + 400000);
    var pick = function (r) {
      var x = r.exec(w);
      return x ? x[1] : "";
    };
    out.push({
      id: ids[i],
      title: h3s[i].title,
      author: pick(/rounded-full"[^>]*\/>([^<]+)<\/span>/),
      age: pick(/mute">(\d+[dh]\d?)</),
      fobs: Number(pick(/>(\d+)<!-- --> FOB/) || 0),
      comments: Number(pick(/M8 9\.5h8M8 12\.5h5"><\/path><\/svg>(\d+)<\/span>/) || 0),
      wall: pick(/mostly <!-- -->([^<]+)</),
      supplies: Number(pick(/text-wd-gold">([\d,]+)</).replace(/,/g, "") || 0),
      pieces: Number(pick(/>([\d,]+)<!-- --> PIECES/).replace(/,/g, "") || 0)
    });
  }
  return out;
}

// Pages can re-serve entries around publish-time; drop repeats.
function unescapePayload(t) {
  return String(t || "").replace(/\\"/g, '"');
}

// the detail page only links itself relatively inside the flight payload;
// elsewhere the canonical link is absolute
function _detailId(blob) {
  var m = /href="[^"]*\/loadouts\/base\/hub\/([a-z0-9]+)"/.exec(blob);
  return m ? m[1] : "";
}

function dedupeBuilds(builds) {
  var seen = {};
  var out = [];
  for (var i = 0; i < builds.length; i++) {
    if (seen[builds[i].id])
      continue;
    seen[builds[i].id] = true;
    out.push(builds[i]);
  }
  return out;
}

// --- detail -----------------------------------------------------------------
// The flight payload carries a structured block:
//   "drawing":{"shapes":[{"d":"M..L..Z","id":..,"label":..,"kind":..,
//                         "cx":..,"cy":..},...],
//              "viewBox":"x y w h","span":N},
//   "manifest":[{"id":..,"name":..,"count":N,"supplies":N,"cash":N},...]
// The static header adds title / wall type; supplies/pieces arrive
// recomputed per manifest entry.
function parseBaseDetail(html) {
  var blob = unescapePayload(html);

  var dAt = blob.indexOf('"drawing":{"shapes":[');
  if (dAt === -1)
    return null;

  var shapesEnd = blob.indexOf('"viewBox"', dAt);
  var shapesBlob = blob.substring(dAt, shapesEnd);

  var shapes = [];
  var shapeRe = /\{"d":"([^"]+)","id":"([^"]*)","label":"([^"]*)","kind":"([^"]*)","cx":(-?[\d.]+),"cy":(-?[\d.]+)\}/g;
  var sm;
  function num(v) {
    return parseFloat(v);
  }
  while ((sm = shapeRe.exec(shapesBlob)) !== null) {
    var pts = [];
    var pre = /([ML])(-?[\d.]+) (-?[\d.]+)/g;
    var p;
    while ((p = pre.exec(sm[1])) !== null)
      pts.push([parseFloat(p[2]), parseFloat(p[3])]);
    shapes.push({ pts: pts, id: sm[2], label: sm[3], kind: sm[4], cx: parseFloat(sm[5]), cy: parseFloat(sm[6]) });
  }
  if (shapes.length === 0)
    return null;

  var vb = /"viewBox":"(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"/.exec(blob.substring(shapesEnd, shapesEnd + 160));
  var view = vb ? { x: parseFloat(vb[1]), y: parseFloat(vb[2]), w: parseFloat(vb[3]), h: parseFloat(vb[4]) } : { x: 0, y: 0, w: 80, h: 80 };

  var mAt = blob.indexOf('"manifest":[', shapesEnd);
  var manifest = [];
  if (mAt !== -1) {
    var manBlob = blob.substring(mAt, mAt + 8000);
    var reMan = /\{"id":"([a-z0-9\-]+)","name":"([^"]+)","count":(\d+),"supplies":(\d+),"cash":(\d+)\}/g;
    var mm;
    while ((mm = reMan.exec(manBlob)) !== null)
      manifest.push({ id: mm[1], name: mm[2], count: Number(mm[3]), supplies: Number(mm[4]), cash: Number(mm[5]) });
    if (manifest.length === 0)
      return null;
  }

  // static header: <h1>title</h1><p ...>Built mostly out of X.</p>, author
  // link + age line, upvote count beside the vote button
  var h1 = /<h1 class="wd-display[^"]*">([^<]+)<\/h1>/.exec(blob);
  var wall = /Built mostly out of ([^<.]+)\./.exec(blob);
  var authorRe = /href="\/u\/[a-z0-9\-]+"><img[^>]*\/><span class="font-hud">([^<]+)<\/span>/.exec(blob);
  var mAge = /text-xs[^"]*">(\d+[dh])<!-- --> ago/.exec(blob);
  var mUp = /aria-label="Upvote"[^>]*>\s*<\/button><span class="wd-num[^"]*">(\d+)</.exec(blob);
  var supplies = 0;
  var pieces = 0;
  var fobs = 0;
  for (var i = 0; i < manifest.length; i++) {
    supplies += manifest[i].supplies + manifest[i].cash;
    pieces += manifest[i].count;
    if (manifest[i].id === "fob")
      fobs = manifest[i].count;
  }
  var title = h1 ? h1[1] : "";
  if (title === "")
    return null;

  return {
    id: _detailId(blob),
    title: title,
    author: authorRe ? authorRe[1] : "",
    age: mAge ? mAge[1] : "",
    wall: wall ? wall[1] : "",
    up: mUp ? Number(mUp[1]) : 0,
    supplies: supplies,
    pieces: pieces,
    fobs: fobs,
    shapes: shapes,
    view: view,
    manifest: manifest,
    v: CACHE_VERSION
  };
}

if (typeof module !== "undefined") {
  module.exports = {
    CACHE_VERSION: CACHE_VERSION,
    parseBaseList: parseBaseList,
    dedupeBuilds: dedupeBuilds,
    parseBaseDetail: parseBaseDetail
  }
}
