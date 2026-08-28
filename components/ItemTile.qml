import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

// One armory tile: large item artwork on top, name underneath. Icons are the
// identity of the list, so the tile gives them the majority of the surface.
// Pure presentation — all data comes in as properties. Chrome (fill, border)
// rides the kit's shared control-state tokens so the tile's rest/hover/
// selected borders match the search field, dropdown, and buttons exactly.
BorderSurface {
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

  readonly property color accentColor: Color.accent
  readonly property bool hot: hovered || selected

  color: selected ? Style.selectedFillFor(fg, accentColor)
    : hovered     ? Style.hoverFillFor(fg, accentColor)
    : "transparent"
  borderSpec: selected ? Border.controlSpec("selected", fg, accentColor)
    : hovered          ? Border.controlSpec("hover-cursor", fg, accentColor)
    :                  Border.controlSpec("normal", fg, accentColor)
  radius: Style.cornerRadius

  implicitHeight: Style.space(118)
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

      readonly property int slotPx: Style.space(56)
      // Decode at device pixels (scale 1.25 → 70px): the decoded bitmap then
      // draws 1:1 with no resample, instead of blurring a 96px decode into
      // 70 device pixels through non-power-of-two bilinear.
      readonly property int decodePx: Math.round(slotPx * Screen.devicePixelRatio)

      // Artwork fills a square slot; every cached icon is a transparent
      // square already whitened into an alpha mask at fetch time, so the
      // ColorOverlay re-tints it to the theme foreground. This keeps dark art
      // readable on any theme and re-colors instantly when the theme swaps.
      Image {
        id: iconImg
        anchors.fill: parent
        visible: tile.iconSource !== ""
        source: tile.iconSource
        asynchronous: false
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        sourceSize.width: parent.decodePx
        sourceSize.height: parent.decodePx
      }

      ColorOverlay {
        anchors.fill: iconImg
        visible: iconImg.status === Image.Ready
        source: iconImg
        color: tile.fg
        cached: false
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
      verticalAlignment: Text.AlignVCenter
    }
  }
}
