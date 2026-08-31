import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

// One armory tile, styled after the wardogs.zone item cards: large artwork
// filling the card, the price chip top-right, and the item name over its
// type along the bottom edge. Pure presentation — all data comes in as
// properties. Chrome (fill, border) rides the kit's shared control-state
// tokens so the tile's rest/hover/selected borders match the rest of the
// panel.
BorderSurface {
    id: tile
    property string name: ""
    property string typeText: ""
    property string caliberText: ""
    property string price: ""
    property string iconSource: ""
    property string badge: ""
    property bool selected: false
    property bool hovered: false
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""
    signal openRequested

    readonly property color accentColor: Color.accent
    readonly property color cashColor: "#4ade80"
    readonly property bool hot: hovered || selected

    color: selected ? Style.selectedFillFor(fg, accentColor) : hovered ? Style.hoverFillFor(fg, accentColor) : "transparent"
    borderSpec: selected ? Border.controlSpec("selected", fg, accentColor) : hovered ? Border.controlSpec("hover-cursor", fg, accentColor) : Border.controlSpec("normal", fg, accentColor)
    radius: Style.cornerRadius

    implicitHeight: Style.space(212)
    clip: true

    HoverHandler {
        onHoveredChanged: tile.hovered = hovered
    }

    TapHandler {
        cursorShape: Qt.PointingHandCursor
        onTapped: tile.openRequested()
    }

    // artwork fills the card
    Image {
        id: iconImg
        anchors.fill: parent
        anchors.margins: Style.space(10)
        anchors.bottomMargin: Style.space(68)
        visible: tile.iconSource !== ""
        source: tile.iconSource
        asynchronous: false
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
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

    // price, top-right (only present once stats are cached)
    Text {
        visible: tile.price !== ""
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(8)
        text: tile.price
        color: tile.cashColor
        font.family: tile.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
    }

    // compare-slot marker ("A"/"B"), top-left
    Rectangle {
        visible: tile.badge !== ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Style.space(8)
        implicitWidth: Style.space(18)
        implicitHeight: Style.space(18)
        radius: 0
        color: "transparent"
        border.width: 1
        border.color: tile.accentColor

        Text {
            anchors.centerIn: parent
            text: tile.badge
            color: tile.accentColor
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
    }

    // name over type, pinned to the bottom edge
    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(8)
        spacing: Style.space(1)

        Text {
            Layout.fillWidth: true
            text: tile.name
            color: tile.fg
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: tile.typeText !== ""
            text: tile.typeText
            color: tile.dim
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: tile.caliberText !== ""
            text: tile.caliberText
            color: tile.dim
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }
    }
}
