import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Subcategory (item `type`) picker for the right end of the search row,
// next to the kind dropdown. Options carry live counts and follow the
// active kind; "" selects all types.
Item {
  id: root

  property var items: []
  property string activeKind: ""
  property string activeSub: ""
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property string fontFamily: ""
  property real rowHeight: Style.spacing.controlHeight
  signal setSub(string sub)

  readonly property var options: {
    var subs = Model.subcategories(root.items, root.activeKind)
    var total = 0
    var out = [{ value: "", label: "" }]
    for (var i = 0; i < subs.length; i++) {
      total += subs[i].count
      out.push({ value: subs[i].value, label: subs[i].value + " (" + subs[i].count + ")" })
    }
    out[0].label = "All types (" + total + ")"
    return out
  }

  implicitWidth: Style.space(170)
  implicitHeight: Math.round(root.rowHeight)

  // The kit Dropdown assigns `value` imperatively on selection, which breaks
  // the declarative binding — so external resets (kind switch clears
  // activeSub) must be re-pushed into it explicitly.
  onActiveSubChanged: drop.value = root.activeSub

  Dropdown {
    id: drop
    anchors.fill: parent
    rowHeight: Math.round(root.rowHeight)
    showLabel: false
    options: root.options
    value: root.activeSub
    foreground: root.fg
    fontFamily: root.fontFamily
    onChanged: function(v) { root.setSub(v) }
  }
}
