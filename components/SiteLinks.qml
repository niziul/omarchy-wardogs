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

    delegate: Rectangle {
      required property var modelData
      implicitHeight: Style.space(26)
      width: lab.implicitWidth + Style.space(16)
      radius: 0
      color: Qt.rgba(fg.r, fg.g, fg.b, hover.hovered ? 0.16 : 0.06)
      border.color: Qt.rgba(fg.r, fg.g, fg.b, hover.hovered ? 0.4 : 0.1)
      border.width: 1

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
