import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Category picker rendered as a themed dropdown (kit Dropdown) for the right
// end of the search bar. Options carry the live item counts; selecting emits
// setKind with the kind id ("" = All).
Item {
  id: root

  property var items: []
  property string kinds: ""
  property string activeKind: ""
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property string fontFamily: ""
  // Height of the trigger box. Bind it to the neighboring TextField's height
  // so the borders line up exactly; defaults to the kit control height.
  property real rowHeight: Style.spacing.controlHeight
  // Where keyboard focus should return when the dropdown closes. Dropdowns
  // pull focus onto their trigger, which strands the panel's key catcher —
  // Esc would stop working until something else refocuses it.
  property var focusTarget: null
  signal setKind(string kind)

  readonly property var options: {
    var raw = String(root.kinds || "").split(",")
    var out = [{ value: "", label: "All (" + root.items.length + ")" }]
    for (var i = 0; i < raw.length; i++) {
      var k = raw[i]
      if (!k) continue
      out.push({ value: k, label: Model.kindLabel(k) + " (" + Model.itemCountByKind(root.items, k) + ")" })
    }
    return out
  }

  // The kit Dropdown defaults to Style.spacing.dropdownWidth (240px), which
  // crowds the popup's search row — pin a compact trigger width instead.
  // Heights are rounded so the 1px border lands on the device-pixel grid;
  // raw TextField implicitHeight carries fractional font metrics and the
  // border renders smeared across two rows.
  implicitWidth: Style.space(150)
  implicitHeight: Math.round(root.rowHeight)

  Dropdown {
    id: drop
    anchors.fill: parent
    rowHeight: Math.round(root.rowHeight)
    showLabel: false
    options: root.options
    value: root.activeKind
    foreground: root.fg
    fontFamily: root.fontFamily
    onChanged: function(v) { root.setKind(v) }
    onPopupOpenChanged: if (!drop.popupOpen && root.focusTarget) root.focusTarget.forceActiveFocus()
  }
}
