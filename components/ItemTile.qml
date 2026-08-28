import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One armory tile: large item artwork on top, name underneath. Icons are the
// identity of the list, so the tile gives them the majority of the surface.
// Pure presentation — all data comes in as properties.
Rectangle {
  id: tile
  property string name: ""
  property string url: ""
  property string iconSource: ""
  property bool selected: false
  property bool hovered: false
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property color dim: Qt.rgba(1, 1, 1, 0.62)
  property string fontFamily: ""
  signal openRequested

  readonly property color baseColor: Qt.rgba(fg.r, fg.g, fg.b, (selected || hovered) ? 0.12 : 0.045)
  readonly property color borderColor: Qt.rgba(fg.r, fg.g, fg.b, (selected || hovered) ? 0.38 : 0.08)

  implicitHeight: Style.space(118)
  radius: Style.cornerRadius
  color: baseColor
  border.color: borderColor
  border.width: 1
  clip: true

  HoverHandler {
    onHoveredChanged: tile.hovered = hovered
  }

  TapHandler {
    cursorShape: Qt.PointingHandCursor
    onTapped: tile.openRequested()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    Item {
      Layout.alignment: Qt.AlignHCenter
      Layout.preferredWidth: Style.space(56)
      Layout.preferredHeight: Style.space(56)

      // Artwork fills a square slot; every cached icon is already a 96x96
      // padded square, so all tiles render at a consistent size. Synchronous
      // decode (tiny local files) avoids glyph-flash while the grid rebuilds.
      Image {
        id: iconImg
        anchors.fill: parent
        visible: tile.iconSource !== "" && status !== Image.Error
        source: tile.iconSource
        asynchronous: false
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        sourceSize.width: 96
        sourceSize.height: 96
      }

      Text {
        anchors.centerIn: parent
        visible: tile.iconSource === "" || iconImg.status === Image.Error
        text: "\uF7C4"
        color: tile.dim
        font.family: tile.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.fillHeight: true
      text: tile.name
      color: tile.fg
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: tile.selected
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      elide: Text.ElideRight
      maximumLineCount: 2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignTop
    }
  }
}
