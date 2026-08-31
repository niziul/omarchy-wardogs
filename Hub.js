// Wardogs Zone loadout hub parsers. The hub pages are Next.js RSC streams —
// there is no JSON API — so both parsers walk the flight-chunk payload and
// pull the data out of the presentation elements (same approach as
// Details.js). Pure string in/out, no Qt, no network; unit-testable from
// node via the CommonJS guard.
//
// NOTE: flightChunks is duplicated from Details.js (QML .js imports cannot
// require() each other); keep the two in sync.

// Regex capturing each flight stream row: self.__next_f.push([1,"..."])
// (kept identical to Details.js — QML .js imports cannot require() each
// other, so the extractor is duplicated; sync any change across both).
var FLIGHT_ROW = /self\.__next_f\.push\((\[.*?\])\);?\s*<\/script>/g

function flightChunks(html) {
  var out = []
  FLIGHT_ROW.lastIndex = 0
  var m
  while ((m = FLIGHT_ROW.exec(String(html || ""))) !== null) {
    try {
      var arr = JSON.parse(m[1])
      if (Array.isArray(arr) && typeof arr[1] === "string") out.push(arr[1])
    } catch (e) {
      // skip malformed row
    }
  }
  return out
}

function chunkOf(html) {
  return flightChunks(html).join("\n")
}

function firstRe(t, re) {
  var m = re.exec(t)
  return m ? m[1] : ""
}

// RSC escapes a leading "$" as "$$", so "$9,225" is stored as "$$9,225".
function unescapePrice(s) {
  return String(s || "").replace(/^\$\$/, "$")
}

function num(s) {
  var n = parseFloat(String(s).replace(/,/g, ""))
  return isFinite(n) ? n : 0
}

// Value of a summary stat card, found by its label ("Cost", "Pack", "Role"):
// the big wd-num value span sits within a few hundred chars before the
// label span. Returns the last children string in that window.
function statByLabel(t, label) {
  var at = t.indexOf("\"children\":\"" + label + "\"")
  if (at === -1) return ""
  var win = t.slice(Math.max(0, at - 600), at)
  var vals = win.match(/"children":"([^"]{1,32})"/g)
  if (!vals || vals.length === 0) return ""
  var last = vals[vals.length - 1].replace(/^"children":"|"$/g, "")
  return unescapePrice(last)
}

// One equipment slot card. Cards come in two shapes — equipment rows
// ('["$","div","primary",… "$L4",null,{"href":"/database/x"…') and grid
// cards ('["$","$L4","helmet",{"href":"/database/x"…'), storage being an
// unkeyed grid under its section header. Only anchors carrying a title
// prop count (nav links use label); the weight badge is a bare-number
// children before the icon; the price an escaped "$$…" children after it.
function parseSlots(t) {
  var slots = []
  var sections = []
  var secRe = /"children":"(Equipment|Gear|Storage|Traversal)"\}/g
  var sm
  while ((sm = secRe.exec(t)) !== null) sections.push({ at: sm.index, name: sm[1] })

  function sectionAt(idx) {
    var name = ""
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].at < idx) name = sections[i].name
    }
    return name
  }

  var re = /"href":"\/database\/([a-z0-9_-]+)"/g
  var m
  while ((m = re.exec(t)) !== null) {
    var itemId = m[1]
    var head = t.slice(m.index, m.index + 400)
    var name = firstRe(head, /"title":"([^"]+)"/)
    if (name === "") continue
    var back = t.slice(Math.max(0, m.index - 400), m.index)
    var keyM = back.match(/"(?:div|\$L4)","([a-z]+)",\{/g)
    var key = keyM ? keyM[keyM.length - 1].replace(/"(?:div|\$L4)","|",\{$/g, "") : ""
    var section = sectionAt(m.index)
    // Nav links around the shell carry /database/ hrefs too; only anchors
    // under a known slot section are loadout slots.
    if (["Equipment", "Gear", "Storage", "Traversal"].indexOf(section) === -1) continue
    slots.push({
      key: key,
      section: section,
      itemId: itemId,
      name: name,
      weight: num(firstRe(t.slice(m.index, m.index + 700), /"children":"(\d+(?:\.\d+)?)"/)),
      price: unescapePrice(firstRe(t.slice(m.index, m.index + 1600), /"children":"(\$\$[\d,]+)"/))
    })
  }
  return slots
}

// Detail page: title, description, role, summary totals and the slot list.
// The weight total is a client-component prop ("weightKg":7.43) — its label
// and unit render client-side and are not in the payload.
function parseHubBuild(html) {
  var t = chunkOf(html)
  if (t === "") return null
  var kicker = t.indexOf('"children":"Loadout Hub"')
  var roleAt = t.indexOf('"children":"Role"')
  return {
    title: kicker === -1 ? "" : firstRe(t.slice(kicker), /"wd-display[^"]*","children":"([^"]+)"/),
    description: firstRe(t, /max-w-2xl[^"]*text-wd-text-dim","children":"([^"]+)"/),
    role: roleAt === -1 ? "" : statByLabel(t, "Role"),
    cost: statByLabel(t, "Cost"),
    weight: unescapePrice(firstRe(t, /"weightKg":([\d.]+)/)),
    itemsCarried: statByLabel(t, "Pack"),
    slots: parseSlots(t)
  }
}

// List page: one entry per vote widget ("buildId":"…","score":N); the card
// content follows within the same <li>, ending at the next buildId.
function parseHubList(html) {
  var t = chunkOf(html)
  if (t === "") return []
  var builds = []
  var re = /"buildId":"([a-f0-9]+)","score":(\d+)/g
  var m
  while ((m = re.exec(t)) !== null) {
    var at = m.index
    var next = t.indexOf("\"buildId\":\"", at + 10)
    var win = t.slice(at, next === -1 ? t.length : next)
    var wi = win.match(/"children":\["([\d.]+)"," KG · ",(\d+)/)
    builds.push({
      id: m[1],
      score: parseInt(m[2], 10) || 0,
      title: firstRe(win, /font-display[^"]*","children":"([^"]+)"/),
      author: firstRe(win, /"unoptimized":true\}\],"([^"]+)"\]/),
      age: firstRe(win, /"text-wd-text-mute","children":"([^"]+)"/),
      role: firstRe(win, /"stroke":"none"\}\]\]\}\],"([^"]+)"\]\}/),
      weapon: firstRe(win, /"truncate text-wd-text-mute","children":"([^"]+)"/),
      iconId: firstRe(win, /\/game\/icons\/([a-z0-9_-]+)\.png/),
      cost: unescapePrice(firstRe(win, /text-wd-cash","children":"(\$\$[\d,]+)"/)),
      weight: wi ? wi[1] : "",
      items: wi ? wi[2] : ""
    })
  }
  return builds
}

if (typeof module !== "undefined") {
  module.exports = {
    flightChunks: flightChunks,
    parseHubList: parseHubList,
    parseHubBuild: parseHubBuild
  }
}
