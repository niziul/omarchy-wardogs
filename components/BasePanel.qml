import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

// Base-plan hub: the list of published FOB plans, or one plan's detail —
// stat chips, a plan canvas (10 m grid, pieces colored by kind) and the
// supply manifest rail, styled after the wardogs.zone base pages. Pure
// presentation: already-fetched data, cursor and loader/error come in as
// properties; the parent owns keyboard routing and the window chrome.
Item {
    id: bp

    property bool listMode: true
    property var builds: []             // parsed list rows
    property var base: null             // parsed detail (detail mode)
    property int cursor: 0
    property bool loading: false
    property string error: ""
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""

    signal openBuild(string id)
    signal hoverCard(int index)

    readonly property color accentColor: Color.accent
    // the site's role palette (its wd-* tokens)
    readonly property color goldColor: "#eab308"
    readonly property color dangerColor: "#e05252"
    readonly property color supportColor: "#4ade80"
    readonly property color vehicleColor: "#5b8ec9"

    readonly property var colorByKind: {
        var m = {};
        m["core"] = bp.goldColor;
        m["defence"] = bp.dangerColor;
        m["support"] = bp.supportColor;
        m["vehicle"] = bp.vehicleColor;
        return m;
    }
    function kindColor(kind) {
        return bp.colorByKind[kind] !== undefined ? bp.colorByKind[kind] : Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, 0.62);
    }

    // manifest hover: a row spotlight drives the canvas repaint
    property string manifestHover: ""
    onManifestHoverChanged: planCanvas.requestPaint()

    readonly property int shapeCount: base ? base.shapes.length : 0
    readonly property string hoverManifestLabel: {
        if (base === null || manifestHover === "")
            return "";
        for (var i = 0; i < base.manifest.length; i++)
            if (base.manifest[i].id === manifestHover)
                return base.manifest[i].count + " × " + base.manifest[i].name;
        return manifestHover;
    }

    implicitHeight: content.implicitHeight

    component CornerBrackets: Item {
        property color mark: bp.accentColor
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
            visible: bp.listMode && bp.builds.length === 0
            Layout.fillWidth: true
            text: bp.loading ? "Loading base hub…" : (bp.error !== "" ? bp.error : "No bases published.")
            color: bp.dim
            font.family: bp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
        }

        // --- list of published plans -------------------------------------
        ColumnLayout {
            visible: bp.listMode
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
                model: bp.builds

                delegate: Item {
                    id: card
                    required property int index
                    required property var modelData
                    readonly property bool hot: index === bp.cursor

                    Layout.fillWidth: true
                    implicitHeight: Style.space(52)

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: card.hot ? Style.hoverFillFor(bp.fg, bp.accentColor) : "transparent"
                        border.width: 1
                        border.color: card.hot ? bp.accentColor : Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, 0.15)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bp.openBuild(card.modelData.id)
                        hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse)
                            bp.hoverCard(card.index)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(6)
                        spacing: Style.space(10)

                        // piece count chip, left
                        Rectangle {
                            implicitWidth: Style.space(44)
                            implicitHeight: Style.space(40)
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, card.hot ? 0.5 : 0.2)

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: card.modelData.pieces
                                    color: card.hot ? bp.accentColor : bp.fg
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "PIECES"
                                    color: bp.dim
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.caption - 1
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(2)

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                color: card.hot ? bp.accentColor : bp.fg
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: card.hot
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.author + (card.modelData.age !== "" ? " · " + card.modelData.age : "") + " · " + card.modelData.fobs + " FOB" + (card.modelData.comments > 0 ? " · 💬 " + card.modelData.comments : "") + (card.modelData.wall !== "" ? " · mostly " + card.modelData.wall : "")
                                color: bp.dim
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            spacing: 0

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: card.modelData.supplies > 0 ? card.modelData.supplies.toLocaleString() : "—"
                                color: bp.goldColor
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: "SUPPLIES"
                                color: bp.dim
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption - 1
                                font.letterSpacing: 1
                            }
                        }
                    }
                }
            }
        }

        // --- build sheet ---------------------------------------------------
        ColumnLayout {
            visible: !bp.listMode
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
                visible: bp.error !== ""
                Layout.fillWidth: true
                text: bp.error
                color: bp.dim
                font.family: bp.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                visible: bp.base !== null
                Layout.fillWidth: true
                spacing: Style.space(4)

                // header: kicker over title
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                        Layout.fillWidth: true
                        visible: bp.base !== null
                        text: bp.base ? bp.base.author.toUpperCase() + (bp.base.age !== "" ? " · " + bp.base.age + " AGO" : "") + (bp.base.up > 0 ? " · " + bp.base.up + " UP" : "") : ""
                        color: bp.dim
                        font.family: bp.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                    }

                    Text {
                        Layout.fillWidth: true
                        text: bp.base ? String(bp.base.title) : ""
                        color: bp.fg
                        font.family: bp.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: bp.base !== null && bp.base.wall !== ""
                        text: bp.base !== null && String(bp.base.wall) !== "" ? "built mostly out of " + String(bp.base.wall) : ""
                        color: bp.dim
                        font.family: bp.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                // stat chips with corner brackets
                RowLayout {
                    visible: bp.base !== null
                    Layout.fillWidth: true
                    spacing: Style.space(16)

                    Repeater {
                        model: bp.base === null ? [] : [{
                                    "value": bp.base.supplies > 0 ? bp.base.supplies.toLocaleString() : "—",
                                    "label": "SUPPLIES",
                                    "gold": true
                                }, {
                                    "value": bp.base.pieces,
                                    "label": "PIECES",
                                    "gold": false
                                }, {
                                    "value": bp.base.fobs,
                                    "label": "FOBS"
                                }]

                        delegate: Item {
                            id: statCard
                            required property int index
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: Style.space(52)

                            CornerBrackets {
                                mark: statCard.modelData.gold ? bp.goldColor : Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, 0.55)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Style.space(6)
                                spacing: Style.space(2)

                                Text {
                                    Layout.fillWidth: true
                                    text: String(statCard.modelData.value)
                                    color: statCard.modelData.gold ? bp.goldColor : bp.fg
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.title
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: statCard.modelData.label
                                    color: bp.dim
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.letterSpacing: 1
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // plan (left) + manifest (right)
                Row {
                    visible: bp.base !== null
                    Layout.fillWidth: true
                    spacing: Style.space(12)

                    ColumnLayout {
                        width: Math.round(bp.width * 0.7)
                        spacing: Style.space(6)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: "PLAN"
                                color: bp.fg
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 1
                            }

                            Text {
                                text: bp.base !== null && manifestHover !== "" ? bp.hoverManifestLabel : bp.shapeCount + " pieces · 10 m grid"
                                color: bp.dim
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }

                        Item {
                            id: planWrap
                            Layout.fillWidth: true
                            implicitHeight: Style.space(300)

                            Canvas {
                                id: planCanvas
                                anchors.fill: parent
                                contextType: "2d"
                                antialiasing: true

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.fillStyle = "#0b0d10";
                                    ctx.fillRect(0, 0, width, height);
                                    if (bp.base === null)
                                        return;
                                    var view = bp.base.view;
                                    if (!(view.w > 0) || !(view.h > 0))
                                        return;
                                    var scale = Math.min(width / view.w, height / view.h) * 0.94;
                                    var ox = (width - view.w * scale) / 2 - view.x * scale;
                                    var oy = (height - view.h * scale) / 2 - view.y * scale;

                                    // 10 m grid, aligned on the view box
                                    ctx.lineWidth = 1;
                                    ctx.strokeStyle = Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, 0.07);
                                    var gx = Math.ceil(view.x / 10) * 10;
                                    while (gx < view.x + view.w) {
                                        ctx.beginPath();
                                        ctx.moveTo(ox + gx * scale, oy + view.y * scale);
                                        ctx.lineTo(ox + gx * scale, oy + (view.y + view.h) * scale);
                                        ctx.stroke();
                                        gx += 10;
                                    }
                                    var gy = Math.ceil(view.y / 10) * 10;
                                    while (gy < view.y + view.h) {
                                        ctx.beginPath();
                                        ctx.moveTo(ox + view.x * scale, oy + gy * scale);
                                        ctx.lineTo(ox + (view.x + view.w) * scale, oy + gy * scale);
                                        ctx.stroke();
                                        gy += 10;
                                    }

                                    for (var i = 0; i < bp.base.shapes.length; i++) {
                                        var s = bp.base.shapes[i];
                                        var hi = bp.manifestHover !== "" && s.id === bp.manifestHover;
                                        var col = bp.colorByKind[s.kind] !== undefined ? bp.colorByKind[s.kind] : null;
                                        ctx.beginPath();
                                        ctx.moveTo(ox + s.pts[0][0] * scale, oy + s.pts[0][1] * scale);
                                        for (var j = 1; j < s.pts.length; j++)
                                            ctx.lineTo(ox + s.pts[j][0] * scale, oy + s.pts[j][1] * scale);
                                        ctx.closePath();
                                        ctx.fillStyle = hi ? bp.accentColor : col ? Qt.rgba(col.r, col.g, col.b, s.kind === "fortification" ? 0.16 : 0.85) : Qt.rgba(bp.fg.r, bp.fg.g, bp.fg.b, 0.25);
                                        ctx.fill();
                                        if (s.kind !== "fortification" || hi) {
                                            ctx.strokeStyle = hi ? bp.accentColor : col;
                                            ctx.lineWidth = hi ? 2 : 1;
                                            ctx.stroke();
                                        }
                                    }
                                }

                                Connections {
                                    target: bp
                                    function onBaseChanged() {
                                        planCanvas.requestPaint();
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: bp.base !== null
                            text: bp.base !== null ? "seen from above, ten metres a square. gold is the fob, red the stationary defences, green the support kit, blue the vehicles." : ""
                            color: bp.dim
                            font.family: bp.fontFamily
                            font.pixelSize: Style.font.caption - 1
                            wrapMode: Text.WordWrap
                        }
                    }

                    // manifest rail
                    ColumnLayout {
                        width: Math.round(bp.width * 0.3) - Style.space(12)
                        spacing: Style.space(4)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: "MANIFEST"
                                color: bp.fg
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 1
                            }

                            Text {
                                text: bp.base !== null ? bp.base.manifest.length + "" : ""
                                color: bp.dim
                                font.family: bp.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }

                        Repeater {
                            model: bp.base !== null ? bp.base.manifest : []

                            delegate: Item {
                                id: manRow
                                required property int index
                                required property var modelData
                                readonly property bool hot: bp.manifestHover === manRow.modelData.id

                                Layout.fillWidth: true
                                implicitHeight: Style.space(22)

                                Rectangle {
                                    anchors.fill: parent
                                    color: manRow.hot ? Qt.rgba(bp.accentColor.r, bp.accentColor.g, bp.accentColor.b, 0.12) : "transparent"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onContainsMouseChanged: bp.manifestHover = containsMouse ? manRow.modelData.id : (bp.manifestHover === manRow.modelData.id ? "" : bp.manifestHover)
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - manNumText.implicitWidth
                                    text: manRow.modelData.name
                                    color: manRow.hot ? bp.accentColor : bp.fg
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: manNumText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: manRow.modelData.count + " " + (manRow.modelData.supplies + manRow.modelData.cash).toLocaleString()
                                    color: bp.dim
                                    font.family: bp.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
