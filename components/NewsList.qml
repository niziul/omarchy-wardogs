import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Item {
    id: root

    property var items: []
    property int maxItems: 4
    property bool compact: true
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""
    signal openRequested(string url)

    readonly property var shown: {
        var src = root.items || [];
        var n = Math.min(src.length, root.maxItems);
        var out = [];
        for (var i = 0; i < n; i++)
            out.push(src[i]);
        return out;
    }

    visible: shown.length > 0
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(4)

        Text {
            Layout.fillWidth: true
            text: "News"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        Repeater {
            model: root.shown

            // Row chrome uses the kit's control tokens so the border weight and
            // hover state match the search field and dropdown exactly. Row height
            // is rounded — Text metrics are fractional and smear a 1px border.
            delegate: BorderSurface {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Math.round(inner.implicitHeight) + Style.space(8)
                radius: Style.cornerRadius
                color: hover.hovered ? Style.hoverFillFor(fg, accentColor) : "transparent"
                borderSpec: hover.hovered ? Border.controlSpec("hover-cursor", fg, accentColor) : Border.controlSpec("normal", fg, accentColor)

                // Components don't inherit Panel's accent; use the theme accent.
                readonly property color accentColor: Color.accent

                ColumnLayout {
                    id: inner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(2)

                    Text {
                        Layout.fillWidth: true
                        text: modelData.title
                        color: fg
                        font.family: fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            var bits = [];
                            if (modelData.category)
                                bits.push(modelData.category);
                            var age = Model.relativeDate(modelData.pubDate);
                            if (age)
                                bits.push(age);
                            return bits.join(" · ");
                        }
                        color: dim
                        font.family: fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: !root.compact && modelData.description
                        Layout.fillWidth: true
                        text: modelData.description || ""
                        color: dim
                        font.family: fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    cursorShape: Qt.PointingHandCursor
                    onTapped: root.openRequested(modelData.link)
                }
            }
        }
    }
}
