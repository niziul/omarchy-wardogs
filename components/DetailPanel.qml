import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Right-hand detail pane for the selected armory item. Shows a compact stat
// sheet (class/role, slot, caliber, price, weight, recoil, accuracy, ...) plus
// a flavor line and an "Open in browser" button. Pure presentation: the item
// row and the normalized `detail` object are passed in, and a small state
// set (loading/error/selected/focused) drives which layout is shown.
//
// Keyboard: while this pane owns focus (focused == true, entered via Enter/Tab
// from the grid) Enter opens the browser, Esc/Tab returns to the grid. Arrows
// scroll the sheet. Mouse: clicking the button opens the browser.
Item {
  id: dp

  property var item: null            // filtered row {id,name,type,caliber,...}
  property var detail: null          // normalized detail object or null
  property bool loading: false
  property bool error: false
  property bool selected: false      // an item is committed to the pane
  property bool focused: false       // pane owns keyboard focus
  property color fg: Qt.rgba(1, 1, 1, 0.9)
  property color dim: Qt.rgba(1, 1, 1, 0.62)
  property string fontFamily: ""
  signal openBrowser(string url)
  signal leave

  readonly property color accentColor: Color.accent
  readonly property string itemName: item ? String(item.name || "") : ""
  readonly property string itemId: item ? String(item.id || "") : ""
  readonly property string itemType: item ? String(item.type || "") : ""

  // --- helpers ----------------------------------------------------------------
  function hasDetail() { return dp.detail !== null && dp.detail !== undefined }
  function numText(v) { return (typeof v === "number") ? String(v) : "" }

  // Pane keyboard scope (entered via Enter/Tab from the grid): Enter/space
  // activate the browser button, arrows scroll, Esc/Tab hand focus back to the
  // grid. Only meaningful while the parent keeps `focused == true`.
  activeFocusOnTab: true
  Keys.onEscapePressed: { if (dp.focused) dp.leave() }
  Keys.onTabPressed: { if (dp.focused) dp.leave() }
  Keys.onReturnPressed: { if (dp.focused && dp.selected) dp.openBrowser(Model.itemUrl(dp.itemId)) }
  Keys.onEnterPressed: { if (dp.focused && dp.selected) dp.openBrowser(Model.itemUrl(dp.itemId)) }
  Keys.onSpacePressed: { if (dp.focused && dp.selected) dp.openBrowser(Model.itemUrl(dp.itemId)) }
  Keys.onUpPressed: { if (dp.focused) dp.sheet.contentY = Math.max(0, dp.sheet.contentY - Style.space(48)) }
  Keys.onDownPressed: { if (dp.focused) dp.sheet.contentY = Math.min(dp.sheet.contentHeight - dp.sheet.height, dp.sheet.contentY + Style.space(48)) }

  BorderSurface {
    id: chrome
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.selectedFillFor(fg, accentColor)
    borderSpec: focused
      ? Border.controlSpec("selected", fg, accentColor)
      : Border.controlSpec("normal", fg, accentColor)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(6)

      // --- header: item name + subtitle -------------------------------
      Text {
        Layout.fillWidth: true
        text: dp.selected ? dp.itemName : "Details"
        color: dp.fg
        font.family: dp.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: dp.selected
        text: dp.itemType
        color: dp.dim
        font.family: dp.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      PanelSeparator { Layout.fillWidth: true; foreground: dp.fg }

      // --- body --------------------------------------------------------
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Hint: nothing selected yet.
        Text {
          anchors.centerIn: parent
          visible: !dp.selected
          text: "Select an item\n(Enter) to view details"
          color: dp.dim
          font.family: dp.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          lineHeight: 1.4
        }

        // Loading.
        Text {
          anchors.centerIn: parent
          visible: dp.selected && dp.loading
          text: "Loading details…"
          color: dp.dim
          font.family: dp.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Error / no data available.
        ColumnLayout {
          anchors.centerIn: parent
          visible: dp.selected && !dp.loading && !dp.hasDetail()
          spacing: Style.space(8)

          Text {
            visible: dp.error
            Layout.fillWidth: true
            text: "Couldn't load details."
            color: dp.dim
            font.family: dp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            Layout.fillWidth: true
            text: "No details for this item."
            color: dp.dim
            font.family: dp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            Layout.fillWidth: true
            text: "Open in browser to view it on wardogs.zone."
            color: dp.dim
            font.family: dp.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }

        // Scrollable stat sheet.
        Flickable {
          id: sheet
          visible: dp.selected && !dp.loading && dp.hasDetail()
          anchors.fill: parent
          clip: true
          contentWidth: width
          contentHeight: sheetCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: sheetCol
            x: 0
            width: sheet.width
            spacing: Style.space(4)

            // Only emit rows for fields that actually carry a value.
            RowLayout {
              visible: dp.detail ? dp.detail.role !== "" : false
              Layout.fillWidth: true
              Text { text: "Role"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail ? dp.detail.role : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.slot !== "" : false
              Layout.fillWidth: true
              Text { text: "Slot"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail ? dp.detail.slot : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.category !== "" : false
              Layout.fillWidth: true
              Text { text: "Category"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail ? dp.detail.category : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.caliber !== "" : false
              Layout.fillWidth: true
              Text { text: "Caliber"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail ? dp.detail.caliber : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.price !== null : false
              Layout.fillWidth: true
              Text { text: "Price"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail && dp.detail.price !== null ? "$" + dp.detail.price : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.weight !== null : false
              Layout.fillWidth: true
              Text { text: "Weight"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail && dp.detail.weight !== null ? dp.detail.weight + " kg" : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.accuracy !== null : false
              Layout.fillWidth: true
              Text { text: "Accuracy"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.numText(dp.detail ? dp.detail.accuracy : null); color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.rpm !== null : false
              Layout.fillWidth: true
              Text { text: "RPM"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail && dp.detail.rpm !== null ? dp.detail.rpm : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.muzzleVelocity !== null : false
              Layout.fillWidth: true
              Text { text: "Muzzle vel."; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail && dp.detail.muzzleVelocity !== null ? dp.detail.muzzleVelocity + " m/s" : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.effectiveRange !== null : false
              Layout.fillWidth: true
              Text { text: "Eff. range"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail && dp.detail.effectiveRange !== null ? dp.detail.effectiveRange + " m" : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? (dp.detail.vRecoil !== null || dp.detail.hRecoil !== null) : false
              Layout.fillWidth: true
              Text { text: "Recoil"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.recoilText(); color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }
            RowLayout {
              visible: dp.detail ? (dp.detail.fireModes && dp.detail.fireModes.length > 0) : false
              Layout.fillWidth: true
              Text { text: "Fire mode"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.modesText(); color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            RowLayout {
              visible: dp.detail ? dp.detail.magazineCount !== "" : false
              Layout.fillWidth: true
              Text { text: "Magazines"; color: dp.dim; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
              Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: dp.detail ? dp.detail.magazineCount : ""; color: dp.fg; font.family: dp.fontFamily; font.pixelSize: Style.font.caption }
            }

            PanelSeparator {
              visible: dp.flavorLine !== ""
              Layout.fillWidth: true
              Layout.topMargin: Style.space(4)
              foreground: dp.fg
            }

            Text {
              visible: dp.flavorLine !== ""
              Layout.fillWidth: true
              text: dp.flavorLine
              color: dp.dim
              font.family: dp.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      // --- footer: open in browser -------------------------------------
      Button {
        Layout.fillWidth: true
        visible: dp.selected
        radius: Style.cornerRadius
        text: dp.hasDetail()
          ? "Open in browser"
          : "\uF08E  Open in browser"
        tooltipText: "Open " + dp.itemName + " on wardogs.zone"
        foreground: dp.fg
        fontFamily: dp.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: dp.openBrowser(Model.itemUrl(dp.itemId))
      }
    }
  }

  // --- state-derived helpers ------------------------------------------------
  readonly property string flavorLine: {
    if (!dp.hasDetail()) return ""
    var d = dp.detail
    var bits = []
    if (d.description) bits.push(d.description)
    if (d.flavor) bits.push(d.flavor)
    return bits.join(" ") || ""
  }

  function recoilText() {
    var d = dp.detail
    if (!d) return ""
    var bits = []
    if (d.vRecoil !== null) bits.push("V" + d.vRecoil)
    if (d.hRecoil !== null) bits.push("H" + d.hRecoil)
    return bits.join(" / ")
  }

  function modesText() {
    var d = dp.detail
    if (!d || !d.fireModes || !Array.isArray(d.fireModes)) return ""
    return d.fireModes.join("/")
  }
}
