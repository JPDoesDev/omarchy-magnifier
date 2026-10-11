// Pure parsing and layout logic for the magnifier zoom OSD. No QML or Qt
// types here so the same file is imported by ZoomOsd.qml and loaded by Node
// in tests/osd-model-test.sh.

// Style defaults. Empty colour strings mean "use the shell theme colour".
var defaults = {
  fontSize: 48,
  durationMs: 1200,
  borderWidth: 4,
  padding: 15,
  minScale: 2,
  pointerGap: 104,
  pointerDrop: 28,
  background: "",
  text: "",
  border: ""
}

var numericKeys = ["fontSize", "durationMs", "borderWidth", "padding", "minScale", "pointerGap", "pointerDrop"]
var colorKeys = ["background", "text", "border"]

function isHexColor(s) {
  return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s)
}

function finiteNumber(value) {
  if (typeof value === "boolean" || value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

function mergeStyle(raw, base) {
  var style = {}
  var i, key, n
  for (i = 0; i < numericKeys.length; i++) {
    key = numericKeys[i]
    n = raw && Object.prototype.hasOwnProperty.call(raw, key) ? finiteNumber(raw[key]) : NaN
    style[key] = isNaN(n) || n < 0 ? base[key] : n
  }
  // minScale 0 would collapse the card to nothing; anything non-positive
  // falls back to the default.
  if (!(style.minScale > 0)) style.minScale = base.minScale > 0 ? base.minScale : defaults.minScale
  for (i = 0; i < colorKeys.length; i++) {
    key = colorKeys[i]
    var v = raw && Object.prototype.hasOwnProperty.call(raw, key) ? raw[key] : undefined
    style[key] = isHexColor(v) ? v : base[key]
  }
  return style
}

// Accepts the IPC payload as text: a JSON object {"zoom": 3, "style": {...}},
// a bare number string "3" (legacy callers), or anything else. Garbage yields
// zoom 1 with default style. Every style key is optional.
function parsePayload(text, base) {
  base = base || defaults
  var zoom = NaN
  var rawStyle = null
  var parsed
  try {
    parsed = JSON.parse(text === undefined || text === null ? "" : String(text))
  } catch (e) {
    parsed = undefined
  }
  if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
    zoom = finiteNumber(parsed.zoom)
    if (parsed.style !== null && typeof parsed.style === "object" && !Array.isArray(parsed.style)) rawStyle = parsed.style
  } else if (typeof parsed === "number") {
    zoom = finiteNumber(parsed)
  } else {
    zoom = finiteNumber(typeof text === "string" ? text.trim() : text)
  }
  if (isNaN(zoom) || zoom <= 0) zoom = 1
  return { zoom: zoom, style: mergeStyle(rawStyle, base) }
}

// `hyprctl cursorpos` prints "x, y" in logical (global) coordinates.
function parseCursorPos(text) {
  var parts = String(text || "").trim().split(",")
  if (parts.length !== 2) return null
  var x = finiteNumber(parts[0].trim())
  var y = finiteNumber(parts[1].trim())
  if (isNaN(x) || isNaN(y)) return null
  return { x: x, y: y }
}

function effectiveZoom(zoom) {
  var z = finiteNumber(zoom)
  return isNaN(z) ? 1 : Math.max(1, z)
}

// Hyprland magnifies the whole output around the pointer, so a card rendered
// at logical size w shows up w * zoom wide. Shrink the card as zoom grows so it
// stays small on screen, but never below minScale times its normal on-screen
// size: it's rasterised before magnification, and text much below that
// turns to mush when blown up (hence the default of 2).
function cardScale(zoom, minScale) {
  var m = finiteNumber(minScale)
  if (isNaN(m) || m <= 0) m = defaults.minScale
  return Math.min(1, m / effectiveZoom(zoom))
}

// Factor from the card's logical size to the size it occupies on screen.
function onScreenScale(zoom, minScale) {
  return cardScale(zoom, minScale) * effectiveZoom(zoom)
}

// Positions the card relative to the pointer. All inputs are in the panel's
// logical coordinates (cursor already made panel-local). Returns the logical
// {x, y} for the card's top-left (its transformOrigin).
//
// The pointer is the one thing Hyprland does not magnify: it stays put at
// normal size while a point d px away from it appears d * zoom px away. So
// the layout is worked out in on-screen pixels (keep pointerGap clear of the
// 64px pointer, flip left near the right edge, clamp vertically to the
// output) and then mapped back to logical coordinates with
//   logical = cursor + (screen - cursor) / zoom
// which is exactly what the compositor's magnification undoes.
function cardPlacement(p) {
  var zoom = effectiveZoom(p.zoom)
  var screenScale = onScreenScale(zoom, p.minScale)
  var gap = finiteNumber(p.pointerGap)
  var drop = finiteNumber(p.pointerDrop)
  if (isNaN(gap)) gap = defaults.pointerGap
  if (isNaN(drop)) drop = defaults.pointerDrop
  var cursorX = finiteNumber(p.cursorX) || 0
  var cursorY = finiteNumber(p.cursorY) || 0
  var panelW = finiteNumber(p.panelW) || 0
  var panelH = finiteNumber(p.panelH) || 0

  var screenW = (finiteNumber(p.cardW) || 0) * screenScale
  var screenH = (finiteNumber(p.cardH) || 0) * screenScale

  // Prefer the right of the pointer; flip to the left if it would overrun.
  var right = cursorX + gap
  var screenLeft = right + screenW <= panelW ? right : cursorX - gap - screenW
  // Centre on the pointer's hotspot (slightly below its tip), but never off
  // the top or bottom of the output.
  var screenTop = Math.max(0, Math.min(panelH - screenH, cursorY + drop - screenH / 2))

  return {
    x: cursorX + (screenLeft - cursorX) / zoom,
    y: cursorY + (screenTop - cursorY) / zoom,
    screenLeft: screenLeft,
    screenTop: screenTop,
    screenW: screenW,
    screenH: screenH
  }
}

function zoomLabel(zoom) {
  return Math.round(effectiveZoom(zoom) * 100) + "%"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaults: defaults,
    isHexColor: isHexColor,
    parsePayload: parsePayload,
    parseCursorPos: parseCursorPos,
    effectiveZoom: effectiveZoom,
    cardScale: cardScale,
    onScreenScale: onScreenScale,
    cardPlacement: cardPlacement,
    zoomLabel: zoomLabel
  }
}
