import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Deep links to the wardogs.zone tools, rendered as a compact row of icon
// buttons (kit Button) so the chrome, hover, and tooltips match every other
// control in the panel. Labels live in the tooltip.
Item {
  id: root

  property var links: Model.siteLinks()
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property string fontFamily: ""
  property real cornerRadius: 0
  signal openRequested(string url)

  implicitWidth: toolsRow.implicitWidth
  implicitHeight: toolsRow.implicitHeight

  RowLayout {
    id: toolsRow
    anchors.centerIn: parent
    spacing: Style.space(6)

    Repeater {
      model: root.links

      delegate: Button {
        required property var modelData
        radius: root.cornerRadius
        focusable: true
        iconText: modelData.glyph
        tooltipText: modelData.label
        foreground: root.fg
        fontFamily: root.fontFamily
        iconSize: Style.font.icon
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(3)
        onClicked: root.openRequested(modelData.url)
      }
    }
  }
}
