import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Deep links to the wardogs.zone tools, rendered as a compact row of icon
// buttons (kit Button) so the chrome, hover, and tooltips match every other
// control in the panel. Each link carries a tinted SVG mark from ../assets/
// (see SvgIcon); links without one fall back to the font glyph.
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
                id: linkButton
                required property var modelData

                readonly property bool hasIcon: modelData.icon !== undefined && modelData.icon !== ""
                readonly property real iconPx: Style.font.icon

                radius: root.cornerRadius
                focusable: true
                tooltipText: modelData.label
                iconText: linkButton.hasIcon ? "" : modelData.glyph
                foreground: root.fg
                fontFamily: root.fontFamily
                // Sized by the icon slot: with no glyph/text the kit Row is
                // empty, so the instance supplies the implicit size itself
                // (plus the reserved border so hover/focus never relayout).
                implicitWidth: linkButton.iconPx + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
                implicitHeight: linkButton.iconPx + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: root.openRequested(modelData.url)

                SvgIcon {
                    anchors.centerIn: parent
                    visible: linkButton.hasIcon
                    source: linkButton.hasIcon ? String(linkButton.modelData.icon) : ""
                    color: root.fg
                    size: linkButton.iconPx
                }
            }
        }
    }
}
