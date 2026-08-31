import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../Compare.js" as Compare

// Two-item side-by-side stat comparison. Two normalized item details are placed
// into adjacent columns and walked row by row (price, weight, accuracy, recoil,
// ...) with the "better" number highlighted in the accent color. Pure
// presentation: items, details, and per-side loading/error come in as
// properties; keyboard leave/back is handled by the parent (Esc/Back button).
Item {
  id: cp

  property var leftItem: null      // filtered row {id,name,type,caliber,...}
  property var rightItem: null
  property var leftDetail: null    // normalized detail object or null
  property var rightDetail: null
  property bool leftLoading: false
  property bool rightLoading: false
  property bool leftError: false
  property bool rightError: false
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property color dim: Qt.rgba(1, 1, 1, 0.62)
  property string fontFamily: ""

  readonly property color accentColor: Color.accent

  // Sheet geometry: two tinted side columns flank a fixed center label
  // column, and the item headers sit exactly over their side column so each
  // half reads as one block.
  readonly property real labelColW: Style.space(90)
  readonly property real colGap: Style.space(10)
  readonly property real sheetInset: Style.space(2)
  readonly property real sideColW: Math.max(0, (cp.width - labelColW - 2 * colGap - 2 * sheetInset) / 2)
  readonly property color sideTint: Qt.rgba(fg.r, fg.g, fg.b, 0.07)

  // Flattened sheet: group header cells interleaved with their stat rows, in
  // order, skipping groups with no numbers on either side. One GridLayout
  // still aligns the three columns across every group.
  readonly property var sheetRows: {
    var out = [];
    for (var g = 0; g < Compare.groupCount(); g++) {
      var grp = Compare.groupAt(g);
      if (!Compare.groupActive(grp, cp.leftDetail, cp.rightDetail))
        continue;
      out.push({
          "header": grp.label
      });
      for (var i = 0; i < grp.fields.length; i++)
        out.push({
            "field": grp.fields[i]
        });
    }
    return out;
  }

  // A column is usable when it has a committed item with a resolved detail.
  function hasDetail(d) { return d !== null && d !== undefined }
  function columnLoading(loading, detail) { return loading && !hasDetail(detail) }
  function columnError(item, loading, error, detail) { return !loading && !hasDetail(detail) }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // --- header row: aligned over the tinted side columns -----------------
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: cp.sheetInset
      Layout.rightMargin: cp.sheetInset
      spacing: cp.colGap

      Item {
        Layout.preferredWidth: cp.sideColW
        implicitHeight: headerL.implicitHeight

        ColumnHeader {
          id: headerL
          anchors.left: parent.left
          anchors.right: parent.right
          letter: "A"
          item: cp.leftItem
          detail: cp.leftDetail
          loading: cp.leftLoading
          error: cp.leftError
          fg: cp.fg
          dim: cp.dim
          fontFamily: cp.fontFamily
        }
      }

      Item {
        Layout.preferredWidth: cp.labelColW
      }

      Item {
        Layout.preferredWidth: cp.sideColW
        implicitHeight: headerR.implicitHeight

        ColumnHeader {
          id: headerR
          anchors.left: parent.left
          anchors.right: parent.right
          letter: "B"
          item: cp.rightItem
          detail: cp.rightDetail
          loading: cp.rightLoading
          error: cp.rightError
          fg: cp.fg
          dim: cp.dim
          fontFamily: cp.fontFamily
        }
      }
    }

    PanelSeparator { Layout.fillWidth: true; foreground: cp.fg }

    // --- stat rows --------------------------------------------------------
    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: width
      contentHeight: sheet.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Item {
        id: sheet
        x: cp.sheetInset
        width: parent.width - 2 * cp.sheetInset
        implicitHeight: rowsCol.implicitHeight

        // Side tints: each half of the sheet is one continuous block, so
        // "A's stats" and "B's stats" read as separate panels around the
        // neutral label column.
        Rectangle {
          x: 0
          width: cp.sideColW
          height: parent.height
          color: cp.sideTint
        }

        Rectangle {
          x: cp.sideColW + cp.colGap + cp.labelColW + cp.colGap
          width: cp.sideColW
          height: parent.height
          color: cp.sideTint
        }

        // One stat per row: left value | label | right value. Each row is a
        // self-contained full-width line (a ColumnLayout, NOT a GridLayout —
        // with every row spanning all columns the grid has no single-column
        // cells to size columns from and collapses every row to width 0).
        // Group headers separate the sections; hidden rows collapse.
        ColumnLayout {
          id: rowsCol
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(6)

        Repeater {
          model: cp.sheetRows

          delegate: Item {
            id: rowDeleg
            required property int index
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            readonly property var field: isHeader ? null : modelData.field
            readonly property bool active: isHeader || Compare.rowActive(field, cp.leftDetail, cp.rightDetail)
            readonly property string leftVal: isHeader ? "" : Compare.valueText(cp.leftDetail, field)
            readonly property string rightVal: isHeader ? "" : Compare.valueText(cp.rightDetail, field)
            readonly property string better: isHeader ? "" : Compare.betterSide(field, cp.leftDetail, cp.rightDetail)
            // Direction-aware winner arrow: up when the better number is the
            // higher one, down when lower wins (e.g. price) — the arrow always
            // points the way the winning value actually goes, and marks the
            // verdict without relying on color alone (color-blind friendly).
            readonly property string winMark: field !== null && field.higherIsBetter ? "\uF077 " : "\uF078 "

            Layout.fillWidth: true
            Layout.topMargin: isHeader ? Style.space(8) : 0
            visible: active
            implicitHeight: isHeader ? Style.space(14) : Style.space(22)

            // Group header: centered across the full sheet width.
            Text {
                anchors.fill: parent
                visible: rowDeleg.isHeader
                text: rowDeleg.modelData.header !== undefined ? rowDeleg.modelData.header.toUpperCase() : ""
                color: cp.dim
                font.family: cp.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // Stat row: three cells anchored to fixed geometry — left value
            // right-aligned against the label column, label dead-center,
            // right value left-aligned out of it. No layout manager, so the
            // split is a pure function of the row width.
            Text {
                id: leftTxt
                visible: !rowDeleg.isHeader
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: lblTxt.left
                anchors.rightMargin: cp.colGap + Style.space(4)
                width: cp.sideColW - Style.space(8)
                text: rowDeleg.better === "left" ? rowDeleg.winMark + rowDeleg.leftVal : rowDeleg.leftVal
                color: rowDeleg.better === "left" ? cp.accentColor : rowDeleg.better === "right" ? cp.dim : cp.fg
                font.family: cp.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: rowDeleg.better === "left"
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            Text {
                id: lblTxt
                visible: !rowDeleg.isHeader
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                width: cp.labelColW - Style.space(8)
                text: rowDeleg.field ? rowDeleg.field.label : ""
                color: cp.dim
                font.family: cp.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                visible: !rowDeleg.isHeader
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: lblTxt.right
                anchors.leftMargin: cp.colGap + Style.space(4)
                width: cp.sideColW - Style.space(8)
                text: rowDeleg.better === "right" ? rowDeleg.winMark + rowDeleg.rightVal : rowDeleg.rightVal
                color: rowDeleg.better === "right" ? cp.accentColor : rowDeleg.better === "left" ? cp.dim : cp.fg
                font.family: cp.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: rowDeleg.better === "right"
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
            }
          }
        }
      }
      }
    }

    Text {
      visible: cp.leftItem === null && cp.rightItem === null
      Layout.fillWidth: true
      text: "Mark two items with c, then press v to compare them here."
      color: cp.dim
      font.family: cp.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      visible: cp.sheetRows.length === 0 && cp.leftItem !== null && cp.rightItem !== null
      Layout.fillWidth: true
      text: "No comparable stats for this pair."
      color: cp.dim
      font.family: cp.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }

  // One side of the comparison header: an A/B slot chip over the item name,
  // its type · caliber · price line, or a live loading / no-details hint.
  // Presentational only.
  component ColumnHeader: Item {
    id: colHead
    property string letter: ""
    property var item: null
    property var detail: null
    property bool loading: false
    property bool error: false
    property color fg: Qt.rgba(1, 1, 1, 0.9)
    property color dim: Qt.rgba(1, 1, 1, 0.62)
    property string fontFamily: ""

    implicitHeight: headerCol.implicitHeight

    ColumnLayout {
      id: headerCol
      anchors.fill: parent
      spacing: Style.space(2)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        // Slot chip: marks which side of the sheet this column feeds.
        Rectangle {
          implicitWidth: Style.space(18)
          implicitHeight: Style.space(18)
          radius: Style.space(3)
          color: "transparent"
          border.width: 1
          border.color: colHead.fg

          Text {
            anchors.centerIn: parent
            text: colHead.letter
            color: colHead.fg
            font.family: colHead.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Text {
          Layout.fillWidth: true
          text: colHead.item ? String(colHead.item.name || "") : ""
          color: colHead.fg
          font.family: colHead.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
      }

      Text {
        Layout.fillWidth: true
        visible: colHead.item !== null && !colHead.loading && !colHead.error
        text: {
          if (!colHead.item)
            return "";
          var parts = [];
          var t = colHead.detail && colHead.detail.type !== "" ? String(colHead.detail.type || "") : String(colHead.item.type || "");
          if (t !== "")
            parts.push(t);
          var cal = colHead.detail && colHead.detail.caliber !== "" ? String(colHead.detail.caliber) : "";
          if (cal !== "")
            parts.push(cal);
          var price = Compare.formatPrice(colHead.detail ? colHead.detail.price : undefined);
          if (price !== "")
            parts.push(price);
          return parts.join(" · ");
        }
        color: colHead.dim
        font.family: colHead.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: colHead.item === null || colHead.loading || colHead.error
        text: colHead.item === null ? "mark with c" : colHead.loading ? "Loading stats…" : "No stats available"
        color: colHead.dim
        font.family: colHead.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight

        // Gentle pulse while loading so a slow fetch reads as "working",
        // not stuck.
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: colHead.loading
          NumberAnimation {
            to: 0.35
            duration: 700
          }
          NumberAnimation {
            to: 1.0
            duration: 700
          }
        }
      }
    }
  }
}
