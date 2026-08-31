import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

// Loadout hub view: list of published builds, or one build's equipment
// slots. Pure presentation — the already-filtered data, cursor and
// loading/error come in as properties; the parent owns keyboard routing
// (cursor moves, enter, c to mark a slot into the compare sheet, esc/v
// back) and the pinned search/filter bar above this panel.
Item {
    id: hp

    property bool listMode: true
    property var builds: []             // filtered list rows
    property var build: null            // parsed detail or null (detail mode)
    property int cursor: 0
    property bool loading: false
    property string error: ""
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""
    property var iconUrlOf: null        // function(id) -> cached icon url or ""
    property var badgeOf: null          // function(id) -> "A" | "B" | "" compare marker
    property var scroller: null         // parent Flickable, for cursor-follow scrolling
    signal openBuild(string id)
    signal openItem(string url)
    signal markSlot(int index)
    signal markBuild(int index)

    // Delegate registry for cursor-follow scrolling: "c"+index for build
    // cards, "s"+flatIndex for detail slot rows.
    property var rowItems: ({})
    property string rowKey: (listMode ? "c" : "s") + cursor

    onCursorChanged: ensureCursorVisible()
    onRowKeyChanged: ensureCursorVisible()

    function ensureCursorVisible() {
        if (scroller === null)
            return;
        var item = rowItems[rowKey];
        if (item === undefined || item === null)
            return;
        var y = item.mapToItem(scroller.contentItem, 0, 0).y;
        if (y < scroller.contentY + Style.space(4))
            scroller.contentY = Math.max(0, y - Style.space(36));
        else if (y + item.height > scroller.contentY + scroller.height - Style.space(4))
            scroller.contentY = y + item.height - scroller.height + Style.space(8);
    }

    readonly property color accentColor: Color.accent
    readonly property var sections: {
        if (!hp.build)
            return [];
        var out = [];
        var order = ["Equipment", "Gear", "Storage", "Traversal"];
        for (var i = 0; i < order.length; i++) {
            var rows = hp.build.slots.filter(function (s) {
                return s.section === order[i];
            });
            if (rows.length > 0)
                out.push({
                    "label": order[i],
                    "rows": rows
                });
        }
        return out;
    }

    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        Text {
            visible: hp.listMode && hp.builds.length === 0
            Layout.fillWidth: true
            text: hp.loading ? "Loading hub…" : (hp.error !== "" ? hp.error : "No builds match.")
            color: hp.dim
            font.family: hp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
        }

        // --- list of builds -------------------------------------------------
        ColumnLayout {
            visible: hp.listMode
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
                model: hp.builds

                delegate: Item {
                    id: card
                    required property int index
                    required property var modelData
                    readonly property bool hot: index === hp.cursor

                    Layout.fillWidth: true
                    implicitHeight: Style.space(58)
                    Component.onCompleted: hp.rowItems["c" + index] = card
                    Component.onDestruction: delete hp.rowItems["c" + index]

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.space(3)
                        color: card.hot ? Style.hoverFillFor(hp.fg, hp.accentColor) : "transparent"
                        border.width: 1
                        border.color: card.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function (mouse) {
                            hp.cursor = card.index;
                            if (mouse.button === Qt.RightButton)
                                hp.markBuild(card.index);
                            else
                                hp.openBuild(card.modelData.id);
                        }
                        hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse)
                            hp.cursor = card.index
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(6)
                        spacing: Style.space(10)

                        Item {
                            Layout.preferredWidth: Style.space(44)
                            Layout.preferredHeight: Style.space(44)

                            Image {
                                id: buildImg
                                anchors.fill: parent
                                visible: hp.iconUrlOf !== null && hp.iconUrlOf(card.modelData.iconId) !== ""
                                source: hp.iconUrlOf !== null ? hp.iconUrlOf(card.modelData.iconId) : ""
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                                smooth: true
                            }

                            // Hub art is white-on-transparent; overlay it into
                            // the theme foreground like the armory tiles.
                            ColorOverlay {
                                anchors.fill: buildImg
                                visible: buildImg.status === Image.Ready
                                source: buildImg
                                color: hp.fg
                                cached: false
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: hp.iconUrlOf === null || hp.iconUrlOf(card.modelData.iconId) === ""
                                text: "\uF7C4"
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.title
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(2)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(5)

                                Rectangle {
                                    visible: hp.badgeOf !== null && hp.badgeOf(card.modelData.id) !== ""
                                    implicitWidth: Style.space(16)
                                    implicitHeight: Style.space(16)
                                    radius: Style.space(3)
                                    color: "transparent"
                                    border.width: 1
                                    border.color: hp.accentColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: hp.badgeOf !== null ? hp.badgeOf(card.modelData.id) : ""
                                        color: hp.accentColor
                                        font.family: hp.fontFamily
                                        font.pixelSize: Style.font.caption
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    color: card.hot ? hp.accentColor : hp.fg
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: card.hot
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.weapon + (card.modelData.role !== "" ? " · " + card.modelData.role : "") + (card.modelData.author !== "" ? " · " + card.modelData.author : "")
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            spacing: Style.space(2)

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.cost
                                color: hp.fg
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.weight + " kg · " + card.modelData.items + " items"
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Text {
                            text: "▲ " + card.modelData.score
                            color: hp.dim
                            font.family: hp.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                }
            }
        }

        // --- build detail -----------------------------------------------------
        ColumnLayout {
            visible: !hp.listMode
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
                Layout.fillWidth: true
                text: hp.build ? String(hp.build.title) : ""
                color: hp.fg
                font.family: hp.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: hp.build && hp.build.description !== ""
                text: hp.build ? String(hp.build.description) : ""
                color: hp.dim
                font.family: hp.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: hp.build
                text: hp.build ? [hp.build.role !== "" ? hp.build.role : "", hp.build.cost, hp.build.weight !== "" ? hp.build.weight + " kg" : "", hp.build.itemsCarried !== "" ? hp.build.itemsCarried + " items" : ""].filter(function (p) {
                    return p !== "";
                }).join(" · ") : ""
                color: hp.dim
                font.family: hp.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: hp.error !== ""
                text: hp.error
                color: hp.dim
                font.family: hp.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
                model: hp.sections

                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    readonly property int rowBase: {
                        var n = 0;
                        for (var g = 0; g < index; g++) n += hp.sections[g].rows.length;
                        return n;
                    }

                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.space(6)
                        text: modelData.label.toUpperCase()
                        color: hp.dim
                        font.family: hp.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: modelData.rows

                        delegate: Item {
                            id: slotRow
                            required property int index
                            required property var modelData
                            readonly property int flat: rowBase + index
                            readonly property bool hot: flat === hp.cursor

                            Layout.fillWidth: true
                            implicitHeight: Style.space(26)
                            Component.onCompleted: hp.rowItems["s" + flat] = slotRow
                            Component.onDestruction: delete hp.rowItems["s" + flat]

                            Rectangle {
                                anchors.fill: parent
                                radius: Style.space(3)
                                color: slotRow.hot ? Style.hoverFillFor(hp.fg, hp.accentColor) : "transparent"
                                border.width: 1
                                border.color: slotRow.hot ? hp.accentColor : "transparent"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function (mouse) {
                                    hp.cursor = slotRow.flat;
                                    if (mouse.button === Qt.RightButton)
                                        hp.markSlot(slotRow.flat);
                                    else
                                        hp.openItem("https://wardogs.zone/database/" + slotRow.modelData.itemId);
                                }
                                hoverEnabled: true
                                onContainsMouseChanged: if (containsMouse)
                                    hp.cursor = slotRow.flat
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(6)
                                anchors.rightMargin: Style.space(6)
                                spacing: Style.space(8)

                                Rectangle {
                                    visible: hp.badgeOf !== null && hp.badgeOf(slotRow.modelData.itemId) !== ""
                                    implicitWidth: Style.space(16)
                                    implicitHeight: Style.space(16)
                                    radius: Style.space(3)
                                    color: "transparent"
                                    border.width: 1
                                    border.color: hp.accentColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: hp.badgeOf !== null ? hp.badgeOf(slotRow.modelData.itemId) : ""
                                        color: hp.accentColor
                                        font.family: hp.fontFamily
                                        font.pixelSize: Style.font.caption
                                        font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: slotRow.modelData.name
                                    color: slotRow.hot ? hp.accentColor : hp.fg
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: slotRow.hot
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: slotRow.modelData.weight > 0
                                    text: slotRow.modelData.weight + " kg"
                                    color: hp.dim
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    text: slotRow.modelData.price
                                    color: hp.fg
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
