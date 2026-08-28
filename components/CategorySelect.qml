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
  implicitWidth: Style.space(150)
  implicitHeight: drop.implicitHeight

  Dropdown {
    id: drop
    anchors.fill: parent
    showLabel: false
    options: root.options
    value: root.activeKind
    foreground: root.fg
    fontFamily: root.fontFamily
    onChanged: function(v) { root.setKind(v) }
  }
}
