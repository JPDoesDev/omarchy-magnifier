import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import "ZoomOsdModel.js" as ZoomOsdModel

// Small card beside the mouse pointer showing the magnifier zoom level, e.g.
// "300%". Driven entirely over IPC; the zoom factor and every style value
// arrive in the payload, so this file never reads the user's config itself:
//
//   omarchy-shell magnifier show '{"zoom": 3, "style": {"fontSize": 48}}'
//   omarchy-shell magnifier show 3                       (bare number)
//   omarchy-shell shell summon jpdoesdev.magnifier '{"zoom": 3}'
//
// Colours default to the active Omarchy theme and can be overridden per key
// with "#rrggbb" values in style.background / style.text / style.border.
Item {
  id: root

  property bool opened: false
  property real zoom: 1
  // Global logical pointer position from `hyprctl cursorpos`.
  property real cursorX: 0
  property real cursorY: 0

  // Style, as last delivered in the payload (defaults from the model).
  property int fontSize: ZoomOsdModel.defaults.fontSize
  property int duration: ZoomOsdModel.defaults.durationMs
  property int borderWidth: ZoomOsdModel.defaults.borderWidth
  property int pad: ZoomOsdModel.defaults.padding
  property real minScale: ZoomOsdModel.defaults.minScale
  property real pointerGap: ZoomOsdModel.defaults.pointerGap
  property real pointerDrop: ZoomOsdModel.defaults.pointerDrop
  // "" means follow the theme.
  property string backgroundOverride: ""
  property string textOverride: ""
  property string borderOverride: ""

  // Qualified as Commons.Color on purpose: Qt 6.12 shadows an unqualified
  // `Color`, so the alias import is the only reliable way at the palette.
  readonly property color backgroundColor: ZoomOsdModel.isHexColor(backgroundOverride) ? backgroundOverride : Commons.Color.background
  readonly property color textColor: ZoomOsdModel.isHexColor(textOverride) ? textOverride : Commons.Color.foreground
  readonly property color borderColor: ZoomOsdModel.isHexColor(borderOverride) ? borderOverride : Commons.Color.accent

  // Hyprland magnifies the whole output around the pointer but draws the
  // pointer itself at normal size. The card is shrunk as zoom grows so it
  // stays small on screen, but never below `minScale` (default 2x) its normal
  // on-screen size: it's rendered before magnification and tiny text turns to
  // mush when blown up. See ZoomOsdModel.cardScale / cardPlacement.
  readonly property real cardScale: ZoomOsdModel.cardScale(zoom, minScale)
  readonly property real onScreenScale: ZoomOsdModel.onScreenScale(zoom, minScale)

  function applyPayload(payloadJson) {
    var p = ZoomOsdModel.parsePayload(payloadJson, ZoomOsdModel.defaults)
    zoom = p.zoom
    fontSize = p.style.fontSize
    duration = p.style.durationMs
    borderWidth = p.style.borderWidth
    pad = p.style.padding
    minScale = p.style.minScale
    pointerGap = p.style.pointerGap
    pointerDrop = p.style.pointerDrop
    backgroundOverride = p.style.background
    textOverride = p.style.text
    borderOverride = p.style.border
  }

  function show(payloadJson) {
    applyPayload(payloadJson)
    // Ask the compositor where the pointer is; the card opens when it answers.
    cursorProc.running = true
  }

  // `open` / `close` are the panel-plugin contract the shell drives through
  // `omarchy-shell summon` / `hide`.
  function open(payloadJson) {
    show(payloadJson)
  }

  function close() {
    hideTimer.stop()
    opened = false
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        var pos = ZoomOsdModel.parseCursorPos(this.text)
        if (pos) {
          root.cursorX = pos.x
          root.cursorY = pos.y
        }
        root.opened = true
        if (root.duration > 0) hideTimer.restart()
        else hideTimer.stop()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  IpcHandler {
    target: "magnifier"
    function show(payloadJson: string): string { root.show(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function ping(): string { return "ok" }
    // What the lock screen watch last saw and what Hyprland was told.
    function lock(): string {
      return JSON.stringify({ known: root.lockKnown, locked: root.sessionLocked, delivered: root.lockDelivered })
    }
  }

  // ---- Lock screen watch -------------------------------------------------
  //
  // The lock screen has to come up at 100%, and neither Hyprland (0.56.2) nor
  // Omarchy tells anyone that the session locked. This half of the plugin
  // lives in the shell, where a query costs nothing that matters, so it
  // watches Hyprland's monitor list for the lock (see sessionLockState in the
  // model) and passes each change to the Hyprland half, which owns the zoom:
  // OmarchyMagnifier.screen_lock(true | false) in hypr/screenlock.lua.
  //
  // Hyprland drops the focus when a lock starts, which shows as an
  // `activewindowv2` event; that event asks for a fresh monitor list at once.
  // The slow poll covers a lock that started with nothing focused. Nothing
  // announces the unlock, so the poll runs fast while locked.
  property bool lockKnown: false
  property bool sessionLocked: false
  // "true" / "false" once Hyprland has taken that state, "" before.
  property string lockDelivered: ""

  function refreshLock() {
    Hyprland.refreshMonitors()
  }

  function evaluateLock() {
    var monitors = Hyprland.monitors.values
    var objects = []
    for (var i = 0; i < monitors.length; i++) objects.push(monitors[i].lastIpcObject)
    var state = ZoomOsdModel.sessionLockState(objects)
    if (state === null) return
    if (!lockKnown || state !== sessionLocked) {
      lockKnown = true
      sessionLocked = state
    }
    deliverLock()
  }

  function deliverLock() {
    if (!lockKnown || lockProc.running) return
    var want = sessionLocked ? "true" : "false"
    if (want === lockDelivered) return
    lockProc.sending = want
    lockProc.command = ["hyprctl", "eval", ZoomOsdModel.screenLockCall(sessionLocked)]
    lockProc.running = true
  }

  Process {
    id: lockProc
    property string sending: ""
    onExited: function(exitCode) {
      // A failed call is tried again by the next poll, not in a tight loop.
      if (exitCode !== 0) return
      root.lockDelivered = sending
      root.deliverLock()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activewindowv2") return
      root.refreshLock()
      lockRecheck.restart()
    }
  }

  Instantiator {
    model: Hyprland.monitors
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { root.evaluateLock() }
    }
  }

  // The focus can drop a moment before the lock is in the monitor list.
  Timer {
    id: lockRecheck
    interval: 150
    onTriggered: root.refreshLock()
  }

  Timer {
    interval: root.sessionLocked ? 250 : 2000
    running: true
    repeat: true
    onTriggered: {
      root.evaluateLock()
      root.refreshLock()
    }
  }

  // Monospace bold so the digits keep their width as the zoom changes; the
  // card is sized to the widest readout so it never jitters.
  TextMetrics {
    id: labelMetrics
    font.family: "monospace"
    font.bold: true
    font.pixelSize: root.fontSize
    text: "1000%"
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      // Pointer position in this screen's own logical coordinates; only the
      // screen under the pointer shows the card.
      readonly property real localX: root.cursorX - modelData.x
      readonly property real localY: root.cursorY - modelData.y
      readonly property bool hasCursor: localX >= 0 && localX < modelData.width
        && localY >= 0 && localY < modelData.height

      visible: root.opened && hasCursor
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-magnifier-osd"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Visual only: an empty input region never blocks clicks.
      mask: Region {}

      Rectangle {
        id: card
        width: root.borderWidth + root.pad + Math.ceil(labelMetrics.advanceWidth) + root.pad + root.borderWidth
        height: root.borderWidth + root.pad + Math.ceil(labelMetrics.height) + root.pad + root.borderWidth
        transformOrigin: Item.TopLeft
        scale: root.cardScale
        // Laid out in on-screen pixels, then mapped back through the zoom.
        readonly property var placement: ZoomOsdModel.cardPlacement({
          cursorX: panel.localX,
          cursorY: panel.localY,
          cardW: width,
          cardH: height,
          panelW: panel.width,
          panelH: panel.height,
          zoom: root.zoom,
          minScale: root.minScale,
          pointerGap: root.pointerGap,
          pointerDrop: root.pointerDrop
        })
        x: placement.x
        y: placement.y
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: root.borderWidth

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: ZoomOsdModel.zoomLabel(root.zoom)
          font: labelMetrics.font
          color: root.textColor
        }
      }
    }
  }
}
