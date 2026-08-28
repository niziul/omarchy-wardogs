// Wardogs Zone — pure parsing/format helpers for the wardogs.zone API payloads.
// No side effects, no network; every function is small enough to stay under
// the cyclomatic complexity budget enforced by eslint (complexity <= 8).
// The CommonJS export guard keeps this loadable both from QML (import
// "Model.js" as Model) and from plain-node unit tests (require("../Model.js")).

function parseIndex(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var items = data && Array.isArray(data.items) ? data.items : []
    var out = []
    for (var i = 0; i < items.length; i++) {
      var row = normalizeItem(items[i])
      if (row) out.push(row)
    }
    return out
  } catch (e) {
    return []
  }
}

// One index row -> a normalized object, or null when it cannot be shown.
function normalizeItem(it) {
  if (!it || !it.id || !it.name) return null
  return {
    id: String(it.id),
    name: cleanName(it.name),
    kind: String(it.kind || "other"),
    type: String(it.type || ""),
    caliber: String(it.caliber || "")
  }
}

// Names arriving from the API can carry label noise; keep the display text tidy.
function cleanName(name) {
  return String(name || "").replace(/^\s+|\s+$/g, "")
}

// Distinct kinds present, presented in a sensible order (weapons first).
var KIND_ORDER = ["weapon", "ammo", "attachment", "armor", "medical", "vehicle", "storage", "throwable", "supplies", "utility", "deployable", "explosive", "melee", "other"]

function kindsList(items) {
  var seen = {}
  var out = []
  for (var i = 0; i < (items || []).length; i++) {
    var k = (items[i] || {}).kind
    if (seen[k]) continue
    seen[k] = true
    out.push(k)
  }
  out.sort(function(a, b) { return kindRank(a) - kindRank(b) })
  return out
}

function kindRank(kind) {
  var idx = KIND_ORDER.indexOf(kind)
  return idx === -1 ? KIND_ORDER.length : idx
}

var KIND_LABELS = {
  weapon: "Weapons", ammo: "Ammo", attachment: "Attachments",
  armor: "Armor", medical: "Medical", vehicle: "Vehicles",
  storage: "Storage", throwable: "Throwables", supplies: "Supplies",
  utility: "Utility", deployable: "Deployables", explosive: "Explosives",
  melee: "Melee", other: "Other"
}

function kindLabel(kind) {
  var label = KIND_LABELS[kind]
  if (label) return label
  var s = String(kind || "")
  if (s === "") return ""
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function itemCountByKind(items, kind) {
  var n = 0
  for (var i = 0; i < (items || []).length; i++) {
    if ((items[i] || {}).kind === kind) n++
  }
  return n
}

// Fuzzy subsequence match with a light score: characters must appear in
// order (not necessarily adjacent). Bonuses reward contiguous runs and
// word-boundary hits; a length nudge prefers specific (short) haystacks.
// Returns -1 when the needle is not a subsequence, else a score >= 0.
function fuzzyScore(needle, haystack) {
  var n = String(needle || "").toLowerCase()
  var h = String(haystack || "").toLowerCase()
  if (n === "") return 0
  var score = 0
  var from = 0
  var prev = -2
  for (var i = 0; i < n.length; i++) {
    var at = h.indexOf(n.charAt(i), from)
    if (at === -1) return -1
    if (at === prev + 1) score += 3
    else score += 1
    if (isWordStart(h, at)) score += 2
    prev = at
    from = at + 1
  }
  score += Math.max(0, 6 - Math.floor(h.length / 8))
  return score
}

function isWordStart(h, at) {
  return at === 0 || h.charAt(at - 1) === " "
}

function itemHaystack(it) {
  return String((it && it.name) || "") + " " + String((it && it.type) || "") + " " + String((it && it.caliber) || "")
}

// Rank rows best-first: fuzzy score descending, name as the tiebreaker.
function byScoreDesc(a, b) {
  if (a.score !== b.score) return b.score - a.score
  return compareNames(a.it, b.it)
}

function filterItems(items, kind, query) {
  var q = String(query || "").trim().toLowerCase()
  var rows = []
  for (var i = 0; i < (items || []).length; i++) {
    var it = items[i]
    if (kind && it.kind !== kind) continue
    var score = fuzzyScore(q, itemHaystack(it).toLowerCase())
    if (score === -1) continue
    rows.push({ it: it, score: score })
  }
  rows.sort(byScoreDesc)
  var out = []
  for (var j = 0; j < rows.length; j++) out.push(rows[j].it)
  return out
}

function compareNames(a, b) {
  if (a.name < b.name) return -1
  if (a.name > b.name) return 1
  return 0
}

// Shared id cleaner: ids feed URLs and filenames, so keep them safe.
function sanitizeId(id) {
  return String(id || "").replace(/[^A-Za-z0-9_-]/g, "")
}

// Detail URL used to deep-link an item to the browser. Falls back to the
// database root for any id we cannot format safely.
function itemUrl(id) {
  var s = sanitizeId(id)
  if (s === "") return "https://wardogs.zone/database"
  return "https://wardogs.zone/database/" + s
}

// The site serves every item's artwork at /game/icons/{id}.png (verified
// across all kinds); empty when the id cannot be formatted safely.
function iconUrlFor(id) {
  var s = sanitizeId(id)
  if (s === "") return ""
  return "https://wardogs.zone/game/icons/" + s + ".png"
}

// Local cache file name for an item icon; empty for unsafe/empty ids.
function iconFileName(id) {
  var s = sanitizeId(id)
  return s === "" ? "" : s + ".png"
}

function parseHealth(raw) {
  var data = null
  try {
    data = JSON.parse(String(raw || "{}"))
  } catch (e) {
    data = null
  }
  var res = { ok: false, version: "", build: "", env: "" }
  if (!data) return res
  res.ok = data.ok === true
  if (data.version) res.version = String(data.version)
  if (data.build) res.build = String(data.build)
  if (data.env) res.env = String(data.env)
  return res
}

// Short build-ish label for the bar ("0.17"); empty until health is known.
function shortVersion(version) {
  var m = /(\d+\.\d+)/.exec(String(version || ""))
  return m ? m[1] : String(version || "")
}

function kindAndCaliber(item) {
  var bits = []
  if (item && item.type) bits.push(item.type)
  if (item && item.caliber) bits.push(item.caliber)
  return bits.join(" · ")
}

function unescapeXml(s) {
  return String(s || "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
}

function tagText(block, tag) {
  var open = "<" + tag + ">"
  var close = "</" + tag + ">"
  var xml = String(block || "")
  var a = xml.indexOf(open)
  if (a === -1) return ""
  var b = xml.indexOf(close, a)
  if (b === -1) return ""
  return unescapeXml(xml.substring(a + open.length, b))
}

function parseRssItem(block) {
  var title = tagText(block, "title")
  var link = tagText(block, "link")
  if (title === "" || link === "") return null
  var guid = tagText(block, "guid")
  return {
    title: title,
    link: link,
    guid: guid === "" ? link : guid,
    pubDate: tagText(block, "pubDate"),
    category: tagText(block, "category"),
    description: tagText(block, "description")
  }
}

function parseRss(raw) {
  var xml = String(raw || "")
  var out = []
  var from = 0
  while (true) {
    var a = xml.indexOf("<item>", from)
    if (a === -1) break
    var b = xml.indexOf("</item>", a)
    if (b === -1) break
    var row = parseRssItem(xml.substring(a, b))
    if (row) out.push(row)
    from = b + 7
  }
  return out
}

function parseNewsCache(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function newestGuid(items) {
  if (!items || items.length === 0) return ""
  return String(items[0].guid || items[0].link || "")
}

function formatAge(sec) {
  if (sec < 60) return "just now"
  if (sec < 3600) return Math.floor(sec / 60) + "m ago"
  if (sec < 86400) return Math.floor(sec / 3600) + "h ago"
  if (sec < 604800) return Math.floor(sec / 86400) + "d ago"
  return Math.floor(sec / 604800) + "w ago"
}

function relativeDate(pubDate, nowMs) {
  var t = Date.parse(String(pubDate || ""))
  if (!isFinite(t)) return String(pubDate || "")
  var now = Date.now()
  if (isFinite(nowMs)) now = nowMs
  var sec = Math.max(0, Math.floor((now - t) / 1000))
  return formatAge(sec)
}

var SITE_LINKS = [
  { label: "Loadouts", url: "https://wardogs.zone/loadouts", glyph: "\uF0B1" },
  { label: "Calculators", url: "https://wardogs.zone/calculators/damage", glyph: "\uF1EC" },
  { label: "Maps", url: "https://wardogs.zone/maps/kavkazi", glyph: "\uF279" },
  { label: "Wiki", url: "https://wardogs.zone/wiki", glyph: "\uF02D" },
  { label: "Updates", url: "https://wardogs.zone/updates", glyph: "\uF1DA" },
  { label: "Community", url: "https://wardogs.zone/community", glyph: "\uF0C0" }
]

function siteLinks() {
  return SITE_LINKS
}

if (typeof module !== "undefined") {
  module.exports = {
    parseIndex: parseIndex,
    normalizeItem: normalizeItem,
    cleanName: cleanName,
    kindsList: kindsList,
    kindRank: kindRank,
    kindLabel: kindLabel,
    itemCountByKind: itemCountByKind,
    filterItems: filterItems,
    fuzzyScore: fuzzyScore,
    itemUrl: itemUrl,
    iconUrlFor: iconUrlFor,
    iconFileName: iconFileName,
    parseHealth: parseHealth,
    shortVersion: shortVersion,
    kindAndCaliber: kindAndCaliber,
    unescapeXml: unescapeXml,
    tagText: tagText,
    parseRssItem: parseRssItem,
    parseRss: parseRss,
    parseNewsCache: parseNewsCache,
    newestGuid: newestGuid,
    relativeDate: relativeDate,
    siteLinks: siteLinks
  }
}
