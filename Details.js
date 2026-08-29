// Wardogs Zone — item detail extraction from the site's Next.js /database/{id}
// HTML. The site has no JSON detail API, so the full item object (price, weight,
// recoil, accuracy, ...) is recovered by parsing the flight payload embedded in
// each page (self.__next_f.push(...)). No network here, no Qt: pure functions so
// they can be unit-tested from node.
//
// The CommonJS guard keeps this loadable both from QML ("Details.js" as Details)
// and from plain-node tests (require("../Details.js")).
//
// Robustness contract: parseDetails returns null on ANY failure or when the item
// is not embedded on the page (e.g. some ammo/magazine pages). The caller falls
// back to a "details unavailable" state and an in-browser link.

// Regex capturing each flight stream row: self.__next_f.push([1,"..."])
// The captured group is the full array literal (ending at its own `]`); JSON.parse
// turns the `1` and the (still JS-escaped) payload string into (1, <payload>).
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

// Return the index just past the balanced JSON object that starts at `i` in
// `txt`, or -1 if no balanced close is found. String-aware: braces inside
// quoted strings (and escaped quotes) are ignored.
function objectEndAt(txt, i, n) {
  var depth = 0
  var instr = false
  var j = i
  while (j < n) {
    var c = txt.charAt(j)
    if (c === "\\") { j += 2; continue }
    if (c === "\"") { instr = !instr }
    else if (!instr) {
      if (c === "{") depth++
      else if (c === "}") {
        depth--
        if (depth === 0) return j + 1
      }
    }
    j++
  }
  return -1
}

// Iterate a raw flight string, handing each balanced top-level JSON object to
// `visit`. Stops as soon as visit returns a truthy value (that value is returned).
function scanObjects(txt, visit) {
  var n = txt.length
  var i = 0
  while (i < n) {
    if (txt.charAt(i) !== "{") { i++; continue }
    var end = objectEndAt(txt, i, n)
    if (end === -1) return null
    try {
      var hit = visit(JSON.parse(txt.slice(i, end)))
      if (hit) return hit
    } catch (e) {
      // malformed segment — skip
    }
    i = end
  }
  return null
}

// Walk a parsed JSON value and return the first dict whose `id` equals `want`.
function walkTo(m, want) {
  if (Array.isArray(m)) return walkArray(m, want)
  if (!m || typeof m !== "object") return null
  if (m.id === want) return m
  var keys = Object.keys(m)
  for (var i = 0; i < keys.length; i++) {
    var s = walkTo(m[keys[i]], want)
    if (s) return s
  }
  return null
}

function walkArray(arr, want) {
  for (var i = 0; i < arr.length; i++) {
    var r = walkTo(arr[i], want)
    if (r) return r
  }
  return null
}

// Render an item's `description` (an array of short strings) into one line.
function descLine(desc) {
  if (!Array.isArray(desc)) return ""
  return desc.join(", ")
}

// Whittle an attached/magazine container into a friendly count+sample label,
// e.g. "3 magazines" — enough context without pulling a second page.
function slotLine(items) {
  if (!Array.isArray(items)) return ""
  return String(items.length)
}

function num(d) {
  return typeof d === "number" ? d : null
}

function str(d) {
  return typeof d === "string" ? d : ""
}

// Normalize a raw item object into the fixed set of fields the detail pane
// knows how to show. Unknown/missing fields are left null/"" — the pane decides.
function normalizeDetail(o) {
  var ba = (o && typeof o.baseAttrs === "object" && o.baseAttrs) ? o.baseAttrs : {}
  var d = {
    id: str(o.id),
    name: str(o.name),
    kind: str(o.kind),
    type: str(o.type),
    category: str(o.category),
    role: str(o.role),
    slot: str(o.slot),
    caliber: str(o.caliber),
    price: num(o.price),
    weight: num(o.weight),
    accuracy: num(o.accuracy),
    rpm: num(o.rpm),
    muzzleVelocity: num(o.muzzleVelocity),
    effectiveRange: num(o.effectiveRange),
    meleeDamage: num(o.meleeDamage),
    meleeReach: num(o.meleeReach),
    maxZeroing: num(o.maxZeroing),
    vRecoil: num(ba.vRecoil),
    hRecoil: num(ba.hRecoil),
    zoom: num(ba.zoom),
    ads: num(ba.ads),
    spread: num(ba.spread),
    fireModes: o.fireModes,
    description: descLine(o.description),
    flavor: str(o.flavor),
    magazineCount: slotLine(o.magazines)
  }
  return d
}

// Parse an item detail page's HTML for the item with the given id. Returns a
// normalized object or null on any failure / when the item is not embedded.
function parseDetails(html, id) {
  if (!html || !id) return null
  var want = String(id)
  var chunks = flightChunks(html)
  for (var i = 0; i < chunks.length; i++) {
    try {
      var found = scanObjects(chunks[i], function(o) {
        return walkTo(o, want)
      })
      if (found) return normalizeDetail(found)
    } catch (e) {
      // try the next row
    }
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    parseDetails: parseDetails,
    normalizeDetail: normalizeDetail,
    flightChunks: flightChunks,
    scanObjects: scanObjects,
    walkTo: walkTo,
    descLine: descLine,
    slotLine: slotLine
  }
}
