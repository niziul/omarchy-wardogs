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

    // The delegate currently highlighted through the cursor, recorded by
    // the focusable delegates as they become hot. revealCursor() maps it
    // into the scroller's coordinate space and reports it upward — the
    // keyboard handler calls it after stepping so the selection scrolls
    // into view (hover never triggers the scroll).
    property var hotItem: null
    property var scrollContent: null
    signal reveal(int y, int height)
    function revealCursor() {
        if (hp.hotItem === null || hp.scrollContent === null)
            return;
        var pt = hp.hotItem.mapToItem(hp.scrollContent, 0, 0);
        hp.reveal(Math.max(0, pt.y), hp.hotItem.height);
    }

    readonly property color accentColor: Color.accent

    // Detail sections in flat cursor order: Equipment → Gear → Storage
    // (the storage group also carries the Traversal slots — parachute,
    // bandages, throwables — exactly like the site, and they fill the
    // storage board cells below). `base` is the section's first flat row.
    readonly property var sections: {
        if (!hp.build)
            return [];
        var out = [];
        var order = ["Equipment", "Gear", "Storage"];
        var n = 0;
        for (var i = 0; i < order.length; i++) {
            var want = order[i];
            var rows = hp.build.slots.filter(function (s) {
                return s.section === want || (want === "Storage" && s.section === "Traversal");
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
    readonly property int boardBase: build !== null ? build.slots.length - boardSlots.length : 0
    readonly property var board: build !== null && build.board ? build.board : null

    // cash-green for slot prices, the site's price language
    readonly property color cashColor: "#4ade80"

    // Equipment grouping for the site layout: keyed slots render as big
    // numbered cards in canonical order (primary, sidearm, specialist),
    // and canonical slots the build leaves empty synthesize a skeleton
    // card (no itemId, not clickable) so the slot grid always shows.
    // Unkeyed rows following a keyed slot attach to it as its grid-space
    // attachments. `orig` preserves the parsed row order (skeletons use
    // -1) so flat cursor/mark indices stay valid.
    function equipmentGroups(section) {
        var groups = {};
        var order = [];
        var cur = null;
        var orphan = [];
        for (var i = 0; i < section.rows.length; i++) {
            var r = section.rows[i];
            if (r.key !== "") {
                cur = {"slot": r, "orig": i, "atts": []};
                while (orphan.length > 0 && cur.atts.length < 4)
                    cur.atts.push(orphan.shift());
                groups[r.key] = cur;
                order.push(r.key);
            } else {
                var it = {"slot": r, "orig": i};
                if (cur === null)
                    orphan.push(it);
                else if (cur.atts.length < 4)
                    cur.atts.push(it);
            }
        }
        var keys = ["primary", "sidearm", "specialist"];
        for (var k = 0; k < order.length; k++)
            if (keys.indexOf(order[k]) === -1)
                keys.push(order[k]);
        var out = [];
        for (var j = 0; j < keys.length; j++) {
            var key = keys[j];
            if (groups[key]) {
                groups[key].num = out.length + 1;
                out.push(groups[key]);
            } else {
                out.push({
                    "slot": {
                        "key": key,
                        "section": "Equipment",
                        "itemId": "",
                        "name": key.toUpperCase(),
                        "mag": 0,
                        "weight": 0,
                        "price": ""
                    },
                    "orig": -1,
                    "num": out.length + 1,
                    "atts": []
                });
            }
        }
        return out;
    }

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
                    onHotChanged: if (hot)
                        hp.hotItem = card

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

                // --- left: equipment (site-style cards + rail) + gear ------
                ColumnLayout {
                    id: leftCol
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

                            // Equipment: the site's build-page layout —
                            // each keyed slot renders as a big numbered card
                            // with its own four grid spaces beside it, filled
                            // from the unkeyed rows that follow it (its
                            // attachments)
                            Column {
                                visible: leftSection.modelData.label === "Equipment"
                                Layout.fillWidth: true
                                spacing: Style.space(8)

                                Repeater {
                                    model: hp.equipmentGroups(leftSection.modelData)

                                    delegate: Row {
                                        id: eqRow
                                        required property int index
                                        required property var modelData
                                        readonly property var slot: modelData.slot
                                        readonly property int flat: leftSection.modelData.base + modelData.orig
                                        readonly property bool hot: flat === hp.cursor
                                        readonly property int tile: Style.space(71)
                                        onHotChanged: if (hot)
                                            hp.hotItem = eqRow

                                        width: leftCol.width
                                        height: Style.space(148)
                                        spacing: Style.space(8)

                                        // --- the big slot card -------------------------
                                        Item {
                                            id: eqCard
                                            width: parent.width - Style.space(8) - 2 * eqRow.tile - Style.space(6)
                                            height: parent.height

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 0
                                                color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.04)
                                                border.width: 1
                                                border.color: eqRow.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: eqRow.slot.itemId !== ""
                                                cursorShape: eqRow.slot.itemId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: function (mouse) {
                                                    hp.hoverSlot(eqRow.flat);
                                                    if (mouse.button === Qt.RightButton)
                                                        hp.markSlot(eqRow.flat);
                                                    else
                                                        hp.openItem("https://wardogs.zone/database/" + eqRow.slot.itemId);
                                                }
                                                hoverEnabled: true
                                                onContainsMouseChanged: if (containsMouse)
                                                    hp.hoverSlot(eqRow.flat)
                                            }

                                            // slot number, top-left
                                            Text {
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.margins: Style.space(6)
                                                text: "[" + eqRow.modelData.num + "]"
                                                color: hp.dim
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }

                                            // weight chip, top-right
                                            Rectangle {
                                                visible: eqRow.slot.weight > 0
                                                anchors.top: parent.top
                                                anchors.right: parent.right
                                                anchors.margins: Style.space(6)
                                                implicitWidth: eqWeightText.implicitWidth + Style.space(12)
                                                implicitHeight: Style.space(20)
                                                color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.08)
                                                border.width: 1
                                                border.color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.25)

                                                Text {
                                                    id: eqWeightText
                                                    anchors.centerIn: parent
                                                    text: eqRow.slot.weight
                                                    color: hp.dim
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                }
                                            }

                                            // A/B badge, beside the slot number
                                            Rectangle {
                                                visible: hp.badgeOf !== null && hp.badgeOf(eqRow.slot.itemId) !== ""
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.margins: Style.space(6)
                                                anchors.leftMargin: Style.space(36)
                                                implicitWidth: Style.space(16)
                                                implicitHeight: Style.space(16)
                                                color: Color.popups.background
                                                border.width: 1
                                                border.color: hp.accentColor

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: hp.badgeOf !== null ? hp.badgeOf(eqRow.slot.itemId) : ""
                                                    color: hp.accentColor
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                }
                                            }

                                            // art, in the space above the name bar
                                            Item {
                                                anchors.top: parent.top
                                                anchors.bottom: eqBar.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right

                                                Image {
                                                    id: eqImg
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    visible: hp.iconUrlOf !== null && hp.iconUrlOf(eqRow.slot.itemId) !== ""
                                                    source: hp.iconUrlOf !== null ? hp.iconUrlOf(eqRow.slot.itemId) : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    mipmap: true
                                                    smooth: true
                                                }

                                                ColorOverlay {
                                                    anchors.fill: eqImg
                                                    visible: eqImg.status === Image.Ready
                                                    source: eqImg
                                                    color: hp.fg
                                                    cached: false
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: hp.iconUrlOf === null || hp.iconUrlOf(eqRow.slot.itemId) === ""
                                                    text: "\uF7C4"
                                                    color: hp.dim
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.title
                                                }
                                            }

                                            // name over price, bottom bar
                                            Rectangle {
                                                id: eqBar
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                implicitHeight: Style.space(26)
                                                color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.07)

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: Style.space(8)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - eqPriceText.implicitWidth - Style.space(24)
                                                    text: eqRow.slot.name
                                                    color: eqRow.slot.itemId === "" ? hp.dim : (eqRow.hot ? hp.accentColor : hp.fg)
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    id: eqPriceText
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Style.space(8)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: eqRow.slot.price !== ""
                                                    text: eqRow.slot.price
                                                    color: hp.cashColor
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        // --- the four grid spaces (2x2) -----------------
                                        Grid {
                                            columns: 2
                                            spacing: Style.space(6)

                                            Repeater {
                                                model: 4

                                                delegate: Item {
                                                    id: attCell
                                                    required property int index
                                                    readonly property var att: index < eqRow.modelData.atts.length ? eqRow.modelData.atts[index] : null
                                                    readonly property bool filled: att !== null
                                                    readonly property int flat: filled ? leftSection.modelData.base + eqRow.modelData.atts[index].orig : -1
                                                    readonly property bool hot: filled && flat === hp.cursor
                                                    onHotChanged: if (hot)
                                                        hp.hotItem = attCell

                                                    width: eqRow.tile
                                                    height: eqRow.tile

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 0
                                                        color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, attCell.filled ? 0.04 : 0.02)
                                                        border.width: 1
                                                        border.color: attCell.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, attCell.filled ? 0.15 : 0.08)
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: attCell.filled
                                                        cursorShape: attCell.filled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        onClicked: function (mouse) {
                                                            hp.hoverSlot(attCell.flat);
                                                            if (mouse.button === Qt.RightButton)
                                                                hp.markSlot(attCell.flat);
                                                            else
                                                                hp.openItem("https://wardogs.zone/database/" + attCell.att.slot.itemId);
                                                        }
                                                        hoverEnabled: true
                                                        onContainsMouseChanged: if (containsMouse && attCell.filled)
                                                            hp.hoverSlot(attCell.flat)
                                                    }

                                                    Image {
                                                        id: attImg
                                                        anchors.centerIn: parent
                                                        width: parent.width - Style.space(12)
                                                        height: parent.height - Style.space(12)
                                                        visible: attCell.filled && hp.iconUrlOf !== null && hp.iconUrlOf(attCell.att.slot.itemId) !== ""
                                                        source: attCell.filled && hp.iconUrlOf !== null ? hp.iconUrlOf(attCell.att.slot.itemId) : ""
                                                        fillMode: Image.PreserveAspectFit
                                                        mipmap: true
                                                        smooth: true
                                                    }

                                                    ColorOverlay {
                                                        anchors.fill: attImg
                                                        visible: attImg.status === Image.Ready
                                                        source: attImg
                                                        color: hp.fg
                                                        cached: false
                                                    }

                                                    Rectangle {
                                                        visible: attCell.filled && hp.badgeOf !== null && hp.badgeOf(attCell.att.slot.itemId) !== ""
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
                                                            text: attCell.filled && hp.badgeOf !== null ? hp.badgeOf(attCell.att.slot.itemId) : ""
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

                            // Gear: compact three-column grid
                            GridLayout {
                                visible: leftSection.modelData.label === "Gear"
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: Style.space(8)
                                rowSpacing: Style.space(8)

                                Repeater {
                                    model: leftSection.modelData.rows

                                    delegate: Item {
                                        id: gearSlot
                                        required property int index
                                        required property var modelData
                                        readonly property int flat: leftSection.modelData.base + index
                                        readonly property bool hot: flat === hp.cursor
                                        onHotChanged: if (hot)
                                            hp.hotItem = gearSlot

                                        Layout.fillWidth: true
                                        implicitHeight: Style.space(104)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 0
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.04)
                                            border.width: 1
                                            border.color: gearSlot.hot ? hp.accentColor : Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.15)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: function (mouse) {
                                                hp.hoverSlot(gearSlot.flat);
                                                if (mouse.button === Qt.RightButton)
                                                    hp.markSlot(gearSlot.flat);
                                                else
                                                    hp.openItem("https://wardogs.zone/database/" + gearSlot.modelData.itemId);
                                            }
                                            hoverEnabled: true
                                            onContainsMouseChanged: if (containsMouse)
                                                hp.hoverSlot(gearSlot.flat)
                                        }

                                        // weight chip, top-right
                                        Rectangle {
                                            visible: gearSlot.modelData.weight > 0
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: Style.space(4)
                                            implicitWidth: gearWeightText.implicitWidth + Style.space(10)
                                            implicitHeight: Style.space(15)
                                            color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(hp.fg.r, hp.fg.g, hp.fg.b, 0.25)

                                            Text {
                                                id: gearWeightText
                                                anchors.centerIn: parent
                                                text: gearSlot.modelData.weight + " kg"
                                                color: hp.dim
                                                font.family: hp.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        // A/B badge
                                        Rectangle {
                                            visible: hp.badgeOf !== null && hp.badgeOf(gearSlot.modelData.itemId) !== ""
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
                                                text: hp.badgeOf !== null ? hp.badgeOf(gearSlot.modelData.itemId) : ""
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
                                                    id: gearImg
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    visible: hp.iconUrlOf !== null && hp.iconUrlOf(gearSlot.modelData.itemId) !== ""
                                                    source: hp.iconUrlOf !== null ? hp.iconUrlOf(gearSlot.modelData.itemId) : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    mipmap: true
                                                    smooth: true
                                                }

                                                ColorOverlay {
                                                    anchors.fill: gearImg
                                                    visible: gearImg.status === Image.Ready
                                                    source: gearImg
                                                    color: hp.fg
                                                    cached: false
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: hp.iconUrlOf === null || hp.iconUrlOf(gearSlot.modelData.itemId) === ""
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
                                                    text: gearSlot.modelData.name
                                                    color: gearSlot.hot ? hp.accentColor : hp.fg
                                                    font.family: hp.fontFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: gearSlot.hot
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: gearSlot.modelData.price
                                                    color: hp.cashColor
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
                                        onHotChanged: if (hot)
                                            hp.hotItem = rightSlot

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
                                                    color: hp.cashColor
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
                                            property bool mouseHot: false
                                            readonly property bool hot: mouseHot || hp.boardBase + boardCell.index === hp.cursor
                                            onHotChanged: if (hot)
                                                hp.hotItem = boardCell

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
                                                onContainsMouseChanged: boardCell.mouseHot = containsMouse
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
