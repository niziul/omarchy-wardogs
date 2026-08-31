import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui
import "../Hub.js" as Hub

// Loadout hub view: list of published builds, or one build's equipment
// sheet styled after the wardogs.zone build page — header block, summary
// stat cards with corner brackets, and a two-column slot body (wide
// equipment cards left; gear cards, storage cards and the bracket-framed
// storage board right). Pure presentation: the already-filtered data,
// cursor and loading/error come in as properties; the parent owns
// keyboard routing and the pinned search/filter bar.
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
    signal openBuild(string id)
    signal openItem(string url)
    signal markSlot(int index)
    signal markBuild(int index)
    // Hover/mouse selection must travel through the parent instead of
    // assigning cursor here — an imperative write would break the cursor
    // binding and freeze keyboard j/k highlight updates.
    signal hoverCard(int index)
    signal hoverSlot(int index)

    readonly property color accentColor: Color.accent

    // Detail sections in flat cursor order: Equipment → Gear → Storage
    // (Traversal slots are rendered by the storage board, not as cards).
    // `base` is the section's first row in the flat index.
    readonly property var sections: {
        if (!hp.build)
            return [];
        var out = [];
        var order = ["Equipment", "Gear", "Storage"];
        var n = 0;
        for (var i = 0; i < order.length; i++) {
            var rows = hp.build.slots.filter(function (s) {
                return s.section === order[i];
            });
            if (rows.length > 0) {
                out.push({
                    "label": order[i],
                    "rows": rows,
                    "base": n
                });
                n += rows.length;
            }
        }
        return out;
    }
    readonly property var leftSections: hp.sections.filter(function (s) {
        return s.label === "Equipment" || s.label === "Gear";
    })
    readonly property var rightSections: hp.sections.filter(function (s) {
        return s.label === "Storage";
    })

    // Storage board: the backpack contents are the Traversal slots (not
    // rendered as cards — the board owns them), filling the parsed cols×rows
    // frame row-major (exact positions/stack counts are client-computed on
    // the site and not in the payload). The flat base is the sum of the
    // card sections since Traversal is last in the parsed order.
    readonly property var boardSlots: build !== null ? build.slots.filter(function (s) {
        return s.section === "Traversal";
    }) : []
    readonly property int boardBase: {
        var n = 0;
        for (var i = 0; i < hp.sections.length; i++) n += hp.sections[i].rows.length;
        return n;
    }
    readonly property var board: build !== null && build.board ? build.board : null

    implicitHeight: content.implicitHeight

    // Thin L-shaped corner marks, the site's stat-card signature.
    component CornerBrackets: Item {
        property color mark: hp.accentColor
        anchors.fill: parent

        Rectangle {
            x: 0
            y: 0
            width: Style.space(10)
            height: 1
            color: parent.mark
        }
        Rectangle {
            x: 0
            y: 0
            width: 1
            height: Style.space(10)
            color: parent.mark
        }
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            width: Style.space(10)
            height: 1
            color: parent.mark
        }
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            width: 1
            height: Style.space(10)
            color: parent.mark
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Style.space(10)
            height: 1
            color: parent.mark
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 1
            height: Style.space(10)
            color: parent.mark
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: Style.space(10)
            height: 1
            color: parent.mark
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 1
            height: Style.space(10)
            color: parent.mark
        }
    }

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

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: card.hot ? Style.hoverFillFor(hp.fg, hp.accentColor) : "transparent"
                        border.width: 1
                        border.color: card.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function (mouse) {
                            hp.hoverCard(card.index);
                            if (mouse.button === Qt.RightButton)
                                hp.markBuild(card.index);
                            else
                                hp.openBuild(card.modelData.id);
                        }
                        hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse)
                            hp.hoverCard(card.index)
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
                                    radius: 0
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

        // --- build sheet ------------------------------------------------------
        ColumnLayout {
            visible: !hp.listMode
            Layout.fillWidth: true
            spacing: Style.space(10)

            // header: kicker, title, description
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                    text: "—  LOADOUT HUB"
                    color: hp.accentColor
                    font.family: hp.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    Layout.fillWidth: true
                    text: hp.build ? String(hp.build.title) : ""
                    color: hp.fg
                    font.family: hp.fontFamily
                    font.pixelSize: Style.font.title
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

            // summary stat cards with corner brackets
            RowLayout {
                visible: hp.build !== null
                Layout.fillWidth: true
                spacing: Style.space(16)

                Repeater {
                    model: hp.build === null ? [] : [{
                            "value": hp.build.cost,
                            "label": "COST",
                            "accented": true
                        }, {
                            "value": hp.build.weight !== "" ? hp.build.weight + " KG" : "",
                            "label": "WEIGHT",
                            "accented": false
                        }, {
                            "value": hp.build.itemsCarried,
                            "label": "PACK · ITEMS CARRIED",
                            "accented": false
                        }, {
                            "value": hp.build.role !== "" ? hp.build.role : "—",
                            "label": "ROLE",
                            "accented": false
                        }]

                    delegate: Item {
                        id: statCard
                        required property int index
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: Style.space(62)

                        CornerBrackets {
                            mark: statCard.modelData.accented ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.55)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(2)

                            Text {
                                Layout.fillWidth: true
                                text: statCard.modelData.value
                                color: statCard.modelData.accented ? hp.accentColor : hp.fg
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: statCard.modelData.label
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // two-column slot body
            Row {
                visible: hp.build !== null && hp.sections.length > 0
                Layout.fillWidth: true
                spacing: Style.space(12)

                // --- left: equipment (wide cards) + gear (grid) -------------
                ColumnLayout {
                    width: Math.round(hp.width * 0.55)
                    spacing: Style.space(10)

                    Repeater {
                        model: hp.leftSections

                        delegate: ColumnLayout {
                            id: leftSection
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: Style.space(6)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)

                                Rectangle {
                                    implicitWidth: Style.space(3)
                                    implicitHeight: Style.space(13)
                                    color: hp.accentColor
                                }

                                Text {
                                    text: leftSection.modelData.label.toUpperCase()
                                    color: hp.fg
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: leftSection.modelData.label === "Equipment" ? 1 : 3
                                columnSpacing: Style.space(8)
                                rowSpacing: Style.space(8)

                                Repeater {
                                    model: leftSection.modelData.rows

                                    delegate: Item {
                                        id: leftSlot
                                        required property int index
                                        required property var modelData
                                        readonly property int flat: leftSection.modelData.base + index
                                        readonly property bool hot: flat === hp.cursor
                                        readonly property bool wide: leftSection.modelData.label === "Equipment"

                                        Layout.fillWidth: true
                                        implicitHeight: wide ? Style.space(88) : Style.space(104)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 0
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.04)
                                            border.width: 1
                                            border.color: leftSlot.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: function (mouse) {
                                                hp.hoverSlot(leftSlot.flat);
                                                if (mouse.button === Qt.RightButton)
                                                    hp.markSlot(leftSlot.flat);
                                                else
                                                    hp.openItem("https://wardogs.zone/database/" + leftSlot.modelData.itemId);
                                            }
                                            hoverEnabled: true
                                            onContainsMouseChanged: if (containsMouse)
                                                hp.hoverSlot(leftSlot.flat)
                                        }

                                        // weight chip, top-right (gear cards)
                                        Rectangle {
                                            visible: !leftSlot.wide && leftSlot.modelData.weight > 0
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: Style.space(4)
                                            implicitWidth: leftWeightText.implicitWidth + Style.space(10)
                                            implicitHeight: Style.space(15)
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.25)

                                            Text {
                                                id: leftWeightText
                                                anchors.centerIn: parent
                                                text: leftSlot.modelData.weight + " kg"
                                                color: hp.dim
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        // mag chip, top-left (equipment cards)
                                        Rectangle {
                                            visible: leftSlot.wide && leftSlot.modelData.mag > 0
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.margins: Style.space(6)
                                            implicitWidth: Style.space(26)
                                            implicitHeight: Style.space(16)
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.25)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "[" + leftSlot.modelData.mag + "]"
                                                color: hp.dim
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        // A/B badge
                                        Rectangle {
                                            visible: hp.badgeOf !== null && hp.badgeOf(leftSlot.modelData.itemId) !== ""
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.margins: Style.space(4)
                                            anchors.leftMargin: leftSlot.wide && leftSlot.modelData.mag > 0 ? Style.space(38) : Style.space(4)
                                            implicitWidth: Style.space(16)
                                            implicitHeight: Style.space(16)
                                            color: Color.popups.background
                                            border.width: 1
                                            border.color: hp.accentColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: hp.badgeOf !== null ? hp.badgeOf(leftSlot.modelData.itemId) : ""
                                                color: hp.accentColor
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Style.space(6)
                                            spacing: Style.space(4)

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                Image {
                                                    id: leftImg
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    visible: hp.iconUrlOf !== null && hp.iconUrlOf(leftSlot.modelData.itemId) !== ""
                                                    source: hp.iconUrlOf !== null ? hp.iconUrlOf(leftSlot.modelData.itemId) : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    mipmap: true
                                                    smooth: true
                                                }

                                                ColorOverlay {
                                                    anchors.fill: leftImg
                                                    visible: leftImg.status === Image.Ready
                                                    source: leftImg
                                                    color: hp.fg
                                                    cached: false
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: hp.iconUrlOf === null || hp.iconUrlOf(leftSlot.modelData.itemId) === ""
                                                    text: "\uF7C4"
                                                    color: hp.dim
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.title
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.space(6)

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: leftSlot.modelData.name
                                                    color: leftSlot.hot ? hp.accentColor : hp.fg
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: leftSlot.hot
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: leftSlot.modelData.price
                                                    color: hp.accentColor
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

                // --- right: storage cards + the bracket-framed board --------
                ColumnLayout {
                    width: Math.round(hp.width * 0.45) - Style.space(12)
                    spacing: Style.space(10)

                    Repeater {
                        model: hp.rightSections

                        delegate: ColumnLayout {
                            id: rightSection
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: Style.space(6)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)

                                Rectangle {
                                    implicitWidth: Style.space(3)
                                    implicitHeight: Style.space(13)
                                    color: hp.accentColor
                                }

                                Text {
                                    text: rightSection.modelData.label.toUpperCase()
                                    color: hp.fg
                                    font.family: hp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Style.space(8)
                                rowSpacing: Style.space(8)

                                Repeater {
                                    model: rightSection.modelData.rows

                                    delegate: Item {
                                        id: rightSlot
                                        required property int index
                                        required property var modelData
                                        readonly property int flat: rightSection.modelData.base + index
                                        readonly property bool hot: flat === hp.cursor

                                        Layout.fillWidth: true
                                        implicitHeight: Style.space(104)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 0
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.04)
                                            border.width: 1
                                            border.color: rightSlot.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: function (mouse) {
                                                hp.hoverSlot(rightSlot.flat);
                                                if (mouse.button === Qt.RightButton)
                                                    hp.markSlot(rightSlot.flat);
                                                else
                                                    hp.openItem("https://wardogs.zone/database/" + rightSlot.modelData.itemId);
                                            }
                                            hoverEnabled: true
                                            onContainsMouseChanged: if (containsMouse)
                                                hp.hoverSlot(rightSlot.flat)
                                        }

                                        Rectangle {
                                            visible: rightSlot.modelData.weight > 0
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: Style.space(4)
                                            implicitWidth: rightWeightText.implicitWidth + Style.space(10)
                                            implicitHeight: Style.space(15)
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.25)

                                            Text {
                                                id: rightWeightText
                                                anchors.centerIn: parent
                                                text: rightSlot.modelData.weight + " kg"
                                                color: hp.dim
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Rectangle {
                                            visible: hp.badgeOf !== null && hp.badgeOf(rightSlot.modelData.itemId) !== ""
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.margins: Style.space(4)
                                            implicitWidth: Style.space(16)
                                            implicitHeight: Style.space(16)
                                            color: Color.popups.background
                                            border.width: 1
                                            border.color: hp.accentColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: hp.badgeOf !== null ? hp.badgeOf(rightSlot.modelData.itemId) : ""
                                                color: hp.accentColor
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Style.space(6)
                                            spacing: Style.space(4)

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                Image {
                                                    id: rightImg
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    visible: hp.iconUrlOf !== null && hp.iconUrlOf(rightSlot.modelData.itemId) !== ""
                                                    source: hp.iconUrlOf !== null ? hp.iconUrlOf(rightSlot.modelData.itemId) : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    mipmap: true
                                                    smooth: true
                                                }

                                                ColorOverlay {
                                                    anchors.fill: rightImg
                                                    visible: rightImg.status === Image.Ready
                                                    source: rightImg
                                                    color: hp.fg
                                                    cached: false
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: hp.iconUrlOf === null || hp.iconUrlOf(rightSlot.modelData.itemId) === ""
                                                    text: "\uF7C4"
                                                    color: hp.dim
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.title
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.space(6)

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: rightSlot.modelData.name
                                                    color: rightSlot.hot ? hp.accentColor : hp.fg
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: rightSlot.hot
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: rightSlot.modelData.price
                                                    color: hp.accentColor
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

                    // storage board: bracket-framed grid box, cells filled
                    // row-major from the traversal slots (exact positions and
                    // stack counts are client-computed on the site)
                    ColumnLayout {
                        visible: hp.board !== null
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)

                            Text {
                                Layout.fillWidth: true
                                text: "STORAGE BOARD"
                                color: hp.fg
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 1
                            }

                            Text {
                                text: hp.board !== null ? hp.board.cols + "×" + hp.board.rows : ""
                                color: hp.dim
                                font.family: hp.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: boardGrid.height + Style.space(24)

                            Item {
                                id: boardWrap
                                anchors.centerIn: parent
                                width: boardGrid.width + Style.space(2)
                                height: boardGrid.height + Style.space(2)

                                CornerBrackets {
                                    mark: hp.accentColor
                                }

                                GridLayout {
                                    id: boardGrid
                                    anchors.centerIn: parent
                                    columns: hp.board !== null ? hp.board.cols : 3
                                    columnSpacing: Style.space(3)
                                    rowSpacing: Style.space(3)

                                    Repeater {
                                        model: hp.board !== null ? hp.board.cols * hp.board.rows : 0

                                        delegate: Item {
                                            id: boardCell
                                            required property int index
                                            readonly property var slot: index < hp.boardSlots.length ? hp.boardSlots[index] : null
                                            readonly property bool filled: slot !== null
                                            property bool hot: false

                                            Layout.preferredWidth: Style.space(46)
                                            Layout.preferredHeight: Style.space(46)

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 0
                                                color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, boardCell.filled ? (boardCell.hot ? 0.09 : 0.05) : 0.02)
                                                border.width: 1
                                                border.color: boardCell.hot && boardCell.filled ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, boardCell.filled ? 0.3 : 0.12)
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: boardCell.filled
                                                cursorShape: boardCell.filled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: function (mouse) {
                                                    if (mouse.button === Qt.RightButton)
                                                        hp.markSlot(hp.boardBase + boardCell.index);
                                                    else
                                                        hp.openItem("https://wardogs.zone/database/" + boardCell.slot.itemId);
                                                }
                                                hoverEnabled: true
                                                onContainsMouseChanged: boardCell.hot = containsMouse
                                            }

                                            Image {
                                                id: cellImg
                                                anchors.centerIn: parent
                                                width: parent.width - Style.space(10)
                                                height: parent.height - Style.space(10)
                                                visible: boardCell.filled && hp.iconUrlOf !== null && hp.iconUrlOf(boardCell.slot.itemId) !== ""
                                                source: boardCell.filled && hp.iconUrlOf !== null ? hp.iconUrlOf(boardCell.slot.itemId) : ""
                                                fillMode: Image.PreserveAspectFit
                                                mipmap: true
                                                smooth: true
                                            }

                                            ColorOverlay {
                                                anchors.fill: cellImg
                                                visible: cellImg.status === Image.Ready
                                                source: cellImg
                                                color: hp.fg
                                                cached: false
                                            }

                                            Rectangle {
                                                visible: boardCell.filled && hp.badgeOf !== null && hp.badgeOf(boardCell.slot.itemId) !== ""
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.margins: Style.space(3)
                                                implicitWidth: Style.space(14)
                                                implicitHeight: Style.space(14)
                                                color: Color.popups.background
                                                border.width: 1
                                                border.color: hp.accentColor

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: boardCell.filled && hp.badgeOf !== null ? hp.badgeOf(boardCell.slot.itemId) : ""
                                                    color: hp.accentColor
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
            }

            Text {
                Layout.fillWidth: true
                visible: hp.build !== null && hp.sections.length === 0 && hp.boardSlots.length === 0
                text: "No slots on this build."
                color: hp.dim
                font.family: hp.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
