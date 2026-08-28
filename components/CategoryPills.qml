import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// A horizontally scrolling row of kind chips (Weapons / Ammo / Attachments …).
// Clicking a chip selects that kind for the list; the pill reflects the
// current selection with the bar-foreground accent.
Item {
  id: root

  property var items: []
  property string kinds: ""
  property string activeKind: ""
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property color dim: Qt.rgba(1, 1, 1, 0.62)
  property string fontFamily: ""
  signal setKind(string kind)

  readonly property var kindArray: {
    var raw = String(root.kinds || "").split(",")
    var out = [{ kind: "", label: "All", count: root.items.length }]
    for (var i = 0; i < raw.length; i++) {
      var k = raw[i]
      if (!k) continue
      out.push({ kind: k, label: Model.kindLabel(k), count: Model.itemCountByKind(root.items, k) })
    }
    return out
  }

  implicitHeight: Style.space(30)

  function choose(kind) {
    root.setKind(kind)
  }

  ListView {
    id: list
    anchors.fill: parent
    orientation: Qt.Horizontal
    spacing: Style.space(6)
    clip: true
    model: root.kindArray
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      id: pill
      required property var modelData
      readonly property bool on: modelData.kind === root.activeKind
      implicitHeight: Style.space(28)
      width: pillRow.implicitWidth + Style.space(16)
      radius: 0
      color: Qt.rgba(fg.r, fg.g, fg.b, on ? 0.18 : 0.06)
      border.color: Qt.rgba(fg.r, fg.g, fg.b, on ? 0.45 : 0.1)
      border.width: 1

      RowLayout {
        id: pillRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Text {
          text: modelData.label
          color: on ? fg : dim
          font.family: fontFamily
          font.pixelSize: Style.font.caption
          font.bold: on
        }

        Text {
          text: "(" + modelData.count + ")"
          color: on ? fg : Qt.rgba(fg.r, fg.g, fg.b, 0.5)
          font.family: fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      TapHandler {
        onTapped: root.choose(modelData.kind)
      }
    }
  }
}
