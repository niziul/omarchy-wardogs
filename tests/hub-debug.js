var H = require("../Hub.js");
var fs = require("fs");
var t = H.chunkOf(fs.readFileSync("tests/fixtures/hub-list.html", "utf8"));
var at = t.indexOf('"buildId":"');
var next = t.indexOf('"buildId":"', at + 10);
var win = t.slice(at, next);
var weaponAt = win.search(/"truncate text-wd-text-mute","children":"/);
var seg = win.slice(1796, 1796 + 16);

var literal = /\],"([^"]{1,32})"\}/;
var built = new RegExp('\\],"([^"]{1,32})"\\}');
console.log("literal.source codes:", literal.source.split("").map(function (c) { return c.charCodeAt(0); }).join(","));
console.log("built.source codes:  ", built.source.split("").map(function (c) { return c.charCodeAt(0); }).join(","));
console.log("seg codes:           ", seg.split("").map(function (c) { return c.charCodeAt(0); }).join(","));
console.log("literal:", JSON.stringify(literal.exec(seg)));
console.log("built:  ", JSON.stringify(built.exec(seg)));
