import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Item {
  id: root

  property var links: Model.siteLinks()
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property color dim: Qt.rgba(1, 1, 1, 0.62)
  property string fontFamily: ""
  signal openRequested(string url)

  implicitHeight: Style.space(28)

  ListView {
    anchors.fill: parent
    orientation: Qt.Horizontal
    spacing: Style.space(6)
    clip: true
    model: root.links
    boundsBehavior: Flickable.StopAtBounds

    delegate: BorderSurface {
      required property var modelData
      // Chip chrome rides the kit's control tokens so rest/hover borders
      // match the search field. Width is rounded off the Text metrics so the
      // 1px vertical borders stay on the device-pixel grid.
      readonly property color accentColor: Color.accent
      implicitHeight: Style.space(26)
      width: Math.round(lab.implicitWidth) + Style.space(16)
      radius: Style.cornerRadius
      color: hover.hovered ? Style.hoverFillFor(fg, accentColor) : "transparent"
      borderSpec: hover.hovered
        ? Border.controlSpec("hover-cursor", fg, accentColor)
        : Border.controlSpec("normal", fg, accentColor)

      Text {
        id: lab
        anchors.centerIn: parent
        text: modelData.label
        color: hover.hovered ? fg : dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
      }

      HoverHandler { id: hover }
      TapHandler {
        cursorShape: Qt.PointingHandCursor
        onTapped: root.openRequested(modelData.url)
      }
    }
  }
}
