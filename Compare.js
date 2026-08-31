// Wardogs Zone — pure helpers for the two-item side-by-side stat comparison.
// Given two normalized detail objects (see Details.normalizeDetail), this
// module decides which rows to show, how to format each value, and which side
// has the better number. No side effects, no Qt, no network — unit-testable
// from node via the CommonJS guard (same pattern as Model.js / Details.js).

// The compare sheet: an ordered list of fields, each with how to render it and
// which direction is "better". Only rows whose key carries a numeric value on
// at least one side are emitted by the UI; the helpers here just describe the
// schema and decide a winner.
var FIELDS = [
  { key: "price",          label: "Price",        unit: "$",  higherIsBetter: false, prefix: true },
  { key: "weight",         label: "Weight",       unit: " kg", higherIsBetter: false },
  { key: "items",          label: "Items",        unit: "",   higherIsBetter: false },
  { key: "score",          label: "Score",        unit: "",   higherIsBetter: true },
  { key: "accuracy",       label: "Accuracy",     unit: "",   higherIsBetter: true },
  { key: "rpm",            label: "RPM",          unit: "",   higherIsBetter: true },
  { key: "muzzleVelocity", label: "Muzzle vel.",  unit: " m/s", higherIsBetter: true },
  { key: "effectiveRange", label: "Eff. range",   unit: " m", higherIsBetter: true },
  { key: "vRecoil",        label: "V. recoil",    unit: "",   higherIsBetter: false },
  { key: "hRecoil",        label: "H. recoil",    unit: "",   higherIsBetter: false },
  { key: "zoom",           label: "Zoom",         unit: "x",  higherIsBetter: true },
  { key: "ads",            label: "ADS time",     unit: " s", higherIsBetter: false }
]

// The sheet groups its rows under labeled sections so related stats read as
// one block instead of a flat dump; a group whose fields carry no numbers on
// either side is omitted entirely (e.g. vehicles only ever show "Basics",
// and build-vs-build compares resolve to Basics alone — item-only stat
// groups stay hidden because builds carry no numbers for them).
var GROUP_DEFS = [
  { label: "Basics",     keys: ["price", "weight", "items", "score"] },
  { label: "Ballistics", keys: ["accuracy", "rpm", "muzzleVelocity", "effectiveRange"] },
  { label: "Recoil",     keys: ["vRecoil", "hRecoil"] },
  { label: "Optics",     keys: ["zoom", "ads"] }
]

function fieldCount() {
  return FIELDS.length
}

function fieldAt(index) {
  return (index >= 0 && index < FIELDS.length) ? FIELDS[index] : null
}

function fieldByKey(key) {
  for (var i = 0; i < FIELDS.length; i++) {
    if (FIELDS[i].key === key) return FIELDS[i]
  }
  return null
}

function groupCount() {
  return GROUP_DEFS.length
}

// Resolved group: { label, fields: [field objects] } — a copy, so callers can
// hold onto it while FIELDS stays the single source of truth for rendering.
function groupAt(index) {
  var g = (index >= 0 && index < GROUP_DEFS.length) ? GROUP_DEFS[index] : null
  if (!g) return null
  var fields = []
  for (var i = 0; i < g.keys.length; i++) {
    var f = fieldByKey(g.keys[i])
    if (f) fields.push(f)
  }
  return { label: g.label, fields: fields }
}

// A group is active when at least one of its fields carries a numeric value
// on either side.
function groupActive(group, leftDetail, rightDetail) {
  if (!group) return false
  for (var i = 0; i < group.fields.length; i++) {
    if (rowActive(group.fields[i], leftDetail, rightDetail)) return true
  }
  return false
}

// Does any side carry a numeric value for this field? Drives row visibility so
// items that lack a stat (e.g. ammo with no recoil) don't leave blank gaps.
function rowActive(field, leftDetail, rightDetail) {
  var a = leftDetail ? leftDetail[field.key] : undefined
  var b = rightDetail ? rightDetail[field.key] : undefined
  return typeof a === "number" || typeof b === "number"
}

// Number rendered with at most 3 decimals and no float-tail noise
// (0.30000000000000004 → "0.3", 3.17 → "3.17", 1 → "1").
function trimNum(n) {
  return String(Math.round(n * 1000) / 1000)
}

// Display string for one side of a row; "" when the side has no value.
// Every field goes through here so rows and the header subtitle always
// agree on format (price thousands separators, trimmed decimals, units).
function valueText(detail, field) {
  var v = detail ? detail[field.key] : undefined
  if (typeof v !== "number") return ""
  if (field.key === "price") return formatPrice(v)
  if (field.prefix) return field.unit + trimNum(v)
  return trimNum(v) + (field.unit || "")
}

// Which side holds the better value for a row: "left", "right", or "" when the
// values are missing or tied.
function betterSide(field, leftDetail, rightDetail) {
  var a = leftDetail ? leftDetail[field.key] : undefined
  var b = rightDetail ? rightDetail[field.key] : undefined
  if (typeof a !== "number" || typeof b !== "number") return ""
  if (a === b) return ""
  if (field.higherIsBetter) return a > b ? "left" : "right"
  return a < b ? "left" : "right"
}

// "$12,500"-style price for headers and rows; "" when not a number.
function formatPrice(v) {
  if (typeof v !== "number") return ""
  var n = Math.round(Math.abs(v))
  var s = String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return (v < 0 ? "-$" : "$") + s
}

if (typeof module !== "undefined") {
  module.exports = {
    FIELDS: FIELDS,
    fieldCount: fieldCount,
    fieldAt: fieldAt,
    fieldByKey: fieldByKey,
    groupCount: groupCount,
    groupAt: groupAt,
    groupActive: groupActive,
    rowActive: rowActive,
    valueText: valueText,
    betterSide: betterSide,
    formatPrice: formatPrice
  }
}
