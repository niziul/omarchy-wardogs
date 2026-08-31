import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui
import "../Hub.js" as Hub

// Loadout hub view: list of published builds, or one build's equipment
// slots. Pure presentation — data, cursor and loading/error come in as
// properties; the parent owns keyboard routing (cursor moves, enter, c to
// mark a slot into the compare sheet, esc/v back). The list embeds its own
// search + hot/top/role filters; `filteredBuilds` is what the cursor and
// openBuild refer to.
Item {
    id: hp

    property bool listMode: true
    property var builds: []
    property var build: null            // parsed detail or null (detail mode)
    property int cursor: 0
    property bool loading: false
    property string error: ""
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""
    property var iconUrlOf: null        // function(id) -> cached icon url or ""
    property var focusTarget: null      // where keyboard focus returns on esc from search
    property alias searchField: hubSearch
    signal openBuild(string id)
    signal openItem(string url)
    signal markSlot(int index)

    // Filter state (list-local).
    property string query: ""
    property string roleFilter: ""
    property string sortMode: "hot"

    readonly property color accentColor: Color.accent
    readonly property var filteredBuilds: Hub.filterBuilds(hp.builds, hp.query, hp.roleFilter, hp.sortMode)
    readonly property var roleOptions: Hub.hubRoles()

    onFilteredBuildsChanged: {
        if (hp.cursor >= hp.filteredBuilds.length)
            hp.cursor = Math.max(0, hp.filteredBuilds.length - 1);
    }

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

        // --- list filter bar ------------------------------------------------
        ColumnLayout {
            visible: hp.listMode
            Layout.fillWidth: true
            spacing: Style.space(6)

            TextField {
                id: hubSearch
                Layout.fillWidth: true
                placeholderText: "Search builds by name, author, weapon…"
                foreground: hp.fg
                accent: hp.accentColor
                font.family: hp.fontFamily
                font.pixelSize: Style.font.caption
                text: hp.query
                onTextEdited: hp.query = hubSearch.text
                Keys.onEscapePressed: {
                    hp.query = "";
                    hubSearch.text = "";
                    if (hp.focusTarget)
                        hp.focusTarget.forceActiveFocus();
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Button {
                    text: "Hot"
                    tooltipText: "Score blended with recency"
                    radius: Style.space(3)
                    active: hp.sortMode === "hot"
                    foreground: hp.fg
                    fontFamily: hp.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(2)
                    onClicked: hp.sortMode = "hot"
                }

                Button {
                    text: "Top"
                    tooltipText: "Highest scored first"
                    radius: Style.space(3)
                    active: hp.sortMode === "top"
                    foreground: hp.fg
                    fontFamily: hp.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(2)
                    onClicked: hp.sortMode = "top"
                }

                Item {
                    Layout.preferredWidth: Style.space(6)
                }

                Repeater {
                    model: ["All"].concat(hp.roleOptions)

                    delegate: Button {
                        required property string modelData
                        readonly property bool isAll: modelData === "All"
                        readonly property bool selected: isAll ? hp.roleFilter === "" : hp.roleFilter.toLowerCase() === modelData.toLowerCase()

                        text: modelData
                        radius: Style.space(3)
                        active: selected
                        foreground: hp.fg
                        fontFamily: hp.fontFamily
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(2)
                        onClicked: hp.roleFilter = isAll ? "" : modelData
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: hp.filteredBuilds.length + " / " + hp.builds.length + " builds"
                    color: hp.dim
                    font.family: hp.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }
        }

        Text {
            visible: hp.listMode && hp.builds.length === 0
            Layout.fillWidth: true
            text: hp.loading ? "Loading hub…" : (hp.error !== "" ? hp.error : "No builds published yet.")
            color: hp.dim
            font.family: hp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: hp.listMode && hp.builds.length > 0 && hp.filteredBuilds.length === 0
            Layout.fillWidth: true
            text: "No builds match."
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
                model: hp.filteredBuilds

                delegate: Item {
                    id: card
                    required property int index
                    required property var modelData
                    readonly property bool hot: index === hp.cursor

                    Layout.fillWidth: true
                    implicitHeight: Style.space(58)

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
                        onClicked: {
                            hp.cursor = card.index;
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

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                color: card.hot ? hp.accentColor : hp.fg
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: card.hot
                                elide: Text.ElideRight
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
                                anchors.right: parent.right
                                text: card.modelData.cost
                                color: hp.fg
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }

                            Text {
                                anchors.right: parent.right
                                text: card.modelData.weight + " kg · " + card.modelData.items + " items"
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
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
                                onClicked: {
                                    hp.cursor = slotRow.flat;
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
