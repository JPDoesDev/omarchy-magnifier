#!/bin/bash
# Unit tests for ZoomOsdModel.js, the pure parsing/layout half of the zoom OSD.
# Runs the model under Node (no Quickshell needed) and prints TAP-ish
# "ok - ..." / "not ok - ..." lines, exiting non-zero on the first failure.
#
#   tests/osd-model-test.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="$SCRIPT_DIR/../ZoomOsdModel.js"

if ! command -v node >/dev/null 2>&1; then
  echo "not ok - node is required to run the model tests"
  exit 1
fi

[[ -f $MODEL ]] || { echo "not ok - model not found: $MODEL"; exit 1; }

node - "$MODEL" <<'EOF'
"use strict"
var M = require(process.argv[2])

var failures = 0
function ok(cond, desc) {
  if (cond) {
    console.log("ok - " + desc)
  } else {
    console.log("not ok - " + desc)
    process.exit(1)
  }
}
function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-9 : eps) }
function eq(actual, expected, desc) {
  ok(typeof actual === "number" && typeof expected === "number" ? near(actual, expected) : actual === expected,
    desc + " (got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected) + ")")
}

var D = M.defaults

// ---------------------------------------------------------------- payloads

var full = M.parsePayload(JSON.stringify({
  zoom: 3,
  style: {
    fontSize: 60, durationMs: 800, borderWidth: 2, padding: 10, minScale: 3,
    pointerGap: 90, pointerDrop: 20,
    background: "#112233", text: "#ffffff", border: "#ABCDEF"
  }
}))
eq(full.zoom, 3, "object payload: zoom")
eq(full.style.fontSize, 60, "object payload: fontSize")
eq(full.style.durationMs, 800, "object payload: durationMs")
eq(full.style.borderWidth, 2, "object payload: borderWidth")
eq(full.style.padding, 10, "object payload: padding")
eq(full.style.minScale, 3, "object payload: minScale")
eq(full.style.pointerGap, 90, "object payload: pointerGap")
eq(full.style.pointerDrop, 20, "object payload: pointerDrop")
eq(full.style.background, "#112233", "object payload: background colour")
eq(full.style.text, "#ffffff", "object payload: text colour")
eq(full.style.border, "#ABCDEF", "object payload: border colour (upper-case hex)")

var bare = M.parsePayload("3")
eq(bare.zoom, 3, "bare number string: zoom")
eq(bare.style.fontSize, D.fontSize, "bare number string: default fontSize")
eq(bare.style.background, "", "bare number string: theme background")

var frac = M.parsePayload("2.5")
eq(frac.zoom, 2.5, "bare fractional number string: zoom")

var strZoom = M.parsePayload('{"zoom": "4"}')
eq(strZoom.zoom, 4, "object payload with zoom as string")

var garbage = M.parsePayload("{not json")
eq(garbage.zoom, 1, "invalid JSON: zoom falls back to 1")
eq(garbage.style.fontSize, D.fontSize, "invalid JSON: default fontSize")
eq(garbage.style.durationMs, D.durationMs, "invalid JSON: default durationMs")
eq(garbage.style.pointerGap, D.pointerGap, "invalid JSON: default pointerGap")

eq(M.parsePayload("").zoom, 1, "empty payload: zoom 1")
eq(M.parsePayload(undefined).zoom, 1, "undefined payload: zoom 1")
eq(M.parsePayload("[1,2]").zoom, 1, "array payload: zoom 1")
eq(M.parsePayload("-2").zoom, 1, "negative zoom: zoom 1")
eq(M.parsePayload('{"zoom": 0}').zoom, 1, "zero zoom: zoom 1")

var badColour = M.parsePayload('{"zoom": 2, "style": {"background": "red", "text": "#fff", "border": "#12345g"}}')
eq(badColour.style.background, "", "invalid colour name ignored (theme)")
eq(badColour.style.text, "", "short hex colour ignored (theme)")
eq(badColour.style.border, "", "non-hex digit colour ignored (theme)")

var partial = M.parsePayload('{"zoom": 2, "style": {"fontSize": 32, "border": "#ffff00"}}')
eq(partial.style.fontSize, 32, "partial style: given fontSize")
eq(partial.style.border, "#ffff00", "partial style: given border")
eq(partial.style.padding, D.padding, "partial style: missing padding keeps default")
eq(partial.style.minScale, D.minScale, "partial style: missing minScale keeps default")
eq(partial.style.background, "", "partial style: missing background keeps theme")
eq(partial.style.text, "", "partial style: missing text keeps theme")

var badNums = M.parsePayload('{"zoom": 2, "style": {"fontSize": "big", "padding": -5, "minScale": 0, "durationMs": null}}')
eq(badNums.style.fontSize, D.fontSize, "non-numeric fontSize keeps default")
eq(badNums.style.padding, D.padding, "negative padding keeps default")
eq(badNums.style.minScale, D.minScale, "minScale 0 keeps default")
eq(badNums.style.durationMs, D.durationMs, "null durationMs keeps default")

eq(M.parsePayload('{"zoom": 2, "style": {"durationMs": 0}}').style.durationMs, 0, "durationMs 0 is accepted (sticky OSD)")

var custom = M.parsePayload("3", { fontSize: 20, durationMs: 1, borderWidth: 1, padding: 1, minScale: 1, pointerGap: 1, pointerDrop: 1, background: "#000000", text: "#ffffff", border: "#ff0000" })
eq(custom.style.fontSize, 20, "caller-supplied defaults are honoured")
eq(custom.style.border, "#ff0000", "caller-supplied default colours are honoured")

// ---------------------------------------------------------------- colours

ok(M.isHexColor("#ffffff"), "isHexColor accepts #ffffff")
ok(M.isHexColor("#AbCdEf"), "isHexColor accepts mixed case")
ok(!M.isHexColor("#fff"), "isHexColor rejects 3-digit hex")
ok(!M.isHexColor("ffffff"), "isHexColor rejects missing #")
ok(!M.isHexColor("#ffffff00"), "isHexColor rejects 8-digit hex")
ok(!M.isHexColor(""), "isHexColor rejects empty")
ok(!M.isHexColor(null), "isHexColor rejects null")
ok(!M.isHexColor(123456), "isHexColor rejects number")

// ---------------------------------------------------------------- cursorpos

var pos = M.parseCursorPos("1234, 567\n")
ok(pos && pos.x === 1234 && pos.y === 567, "parseCursorPos reads 'x, y'")
eq(M.parseCursorPos("garbage"), null, "parseCursorPos rejects garbage")
eq(M.parseCursorPos(""), null, "parseCursorPos rejects empty")

// ---------------------------------------------------------------- scale

eq(M.cardScale(1, 2), 1, "cardScale zoom 1 minScale 2 = 1")
eq(M.cardScale(2, 2), 1, "cardScale zoom 2 minScale 2 = 1")
eq(M.cardScale(7, 2), 2 / 7, "cardScale zoom 7 minScale 2 = 2/7")
eq(M.cardScale(10, 2), 0.2, "cardScale zoom 10 minScale 2 = 0.2")
eq(M.cardScale(0.5, 2), 1, "cardScale below zoom 1 is clamped to 1")
eq(M.cardScale(4, 0), 0.5, "cardScale with minScale 0 falls back to default 2")
eq(M.onScreenScale(1, 2), 1, "onScreenScale zoom 1 = 1")
eq(M.onScreenScale(2, 2), 2, "onScreenScale zoom 2 = 2")
eq(M.onScreenScale(7, 2), 2, "onScreenScale zoom 7 = 2 (pinned at minScale)")
eq(M.onScreenScale(10, 2), 2, "onScreenScale zoom 10 = 2 (pinned at minScale)")

// ---------------------------------------------------------------- placement

var base = { cardW: 200, cardH: 100, panelW: 1920, panelH: 1080, minScale: 2, pointerGap: 104, pointerDrop: 28 }
function place(over) {
  var p = {}
  for (var k in base) p[k] = base[k]
  for (var j in over) p[j] = over[j]
  return M.cardPlacement(p)
}

// zoom 1: the card sits exactly pointerGap to the right of the pointer.
var z1 = place({ cursorX: 500, cursorY: 500, zoom: 1 })
eq(z1.x, 604, "zoom 1: card left edge is cursorX + pointerGap")
eq(z1.y, 500 + 28 - 50, "zoom 1: card centred on cursorY + pointerDrop")

// zoom 1 with a custom gap still honours it exactly.
eq(place({ cursorX: 300, cursorY: 500, zoom: 1, pointerGap: 50 }).x, 350, "zoom 1: custom pointerGap respected")

// zoom 3: on-screen the card is 2x (minScale) and 104px right of the pointer;
// in logical coordinates that is 104/3 px to the right.
var z3 = place({ cursorX: 500, cursorY: 500, zoom: 3 })
eq(z3.screenLeft, 604, "zoom 3: on-screen left edge is cursorX + pointerGap")
eq(z3.screenW, 400, "zoom 3: on-screen width is cardW * minScale")
eq(z3.x, 500 + 104 / 3, "zoom 3: logical x mapped back through the zoom")
eq(z3.y, 500 + (500 + 28 - 100 - 500) / 3, "zoom 3: logical y mapped back through the zoom (half of on-screen height 200)")

// Near the right edge the card flips to the left of the pointer.
var flip = place({ cursorX: 1800, cursorY: 500, zoom: 1 })
eq(flip.x, 1800 - 104 - 200, "zoom 1: flips left when it would overrun the right edge")
ok(flip.x + 200 <= 1800 - 104, "zoom 1: flipped card ends pointerGap left of the pointer")

// Exactly fitting stays on the right.
eq(place({ cursorX: 1920 - 104 - 200, cursorY: 500, zoom: 1 }).x, 1920 - 200, "zoom 1: card that just fits stays on the right")

// Flip at zoom: on-screen width is 400 so it overruns earlier.
var flip3 = place({ cursorX: 1500, cursorY: 500, zoom: 3 })
eq(flip3.screenLeft, 1500 - 104 - 400, "zoom 3: flips left using on-screen width")
eq(flip3.x, 1500 + (1500 - 104 - 400 - 1500) / 3, "zoom 3: flipped logical x mapped back through the zoom")

// Vertical clamping at the top.
var top = place({ cursorX: 500, cursorY: 0, zoom: 1 })
eq(top.y, 0, "zoom 1: clamped to the top edge")
var top3 = place({ cursorX: 500, cursorY: 10, zoom: 3 })
eq(top3.screenTop, 0, "zoom 3: on-screen top clamped to 0")
eq(top3.y, 10 + (0 - 10) / 3, "zoom 3: clamped top mapped back through the zoom")

// Vertical clamping at the bottom.
var bottom = place({ cursorX: 500, cursorY: 1080, zoom: 1 })
eq(bottom.y, 1080 - 100, "zoom 1: clamped to the bottom edge")
var bottom3 = place({ cursorX: 500, cursorY: 1070, zoom: 3 })
eq(bottom3.screenTop, 1080 - 200, "zoom 3: on-screen top clamped so the card ends at the bottom")
eq(bottom3.y, 1070 + (1080 - 200 - 1070) / 3, "zoom 3: clamped bottom mapped back through the zoom")

// Garbage inputs never produce NaN.
var junk = M.cardPlacement({ cursorX: "x", cursorY: null, cardW: undefined, cardH: "y", panelW: NaN, panelH: {}, zoom: "z", minScale: -1, pointerGap: "g", pointerDrop: "d" })
ok(isFinite(junk.x) && isFinite(junk.y), "cardPlacement with junk inputs stays finite")

// ---------------------------------------------------------------- label

eq(M.zoomLabel(3), "300%", "zoomLabel 3 -> 300%")
eq(M.zoomLabel(1.5), "150%", "zoomLabel 1.5 -> 150%")
eq(M.zoomLabel(2.345), "235%", "zoomLabel rounds")
eq(M.zoomLabel("nope"), "100%", "zoomLabel of garbage -> 100%")

console.log("# all zoom OSD model tests passed")
EOF
