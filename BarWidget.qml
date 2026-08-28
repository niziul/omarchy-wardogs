import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "niziul.wardogs"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function toggleWindow() {
    if (panelLoader.item && panelLoader.item.toggleWindow) panelLoader.item.toggleWindow()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  visible: panelLoader.item ? panelLoader.item.showInBar : true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Plugin emblem (assets/icon.png) tinted to the bar text color, with the
  // countdown/label text rendered to its right (F1-sessions layout). The
  // emblem ships as a white alpha-mask, so a Qt6 ColorOverlay re-tints it.
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Custom content below paints the emblem + label; a single space keeps
    // the button's own visibility logic happy.
    text: " "
    labelVisible: false
    keepSpace: true
    tooltipText: panelLoader.item ? panelLoader.item.barTooltip : "Wardogs Zone"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) { if (panelLoader.item && panelLoader.item.openSettings) panelLoader.item.openSettings() }
      else if (b === Qt.MiddleButton) root.toggleWindow()
      else root.togglePanel()
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Item {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: dogImg
          anchors.fill: parent
          source: Qt.resolvedUrl("assets/icon.png")
          fillMode: Image.PreserveAspectFit
          mipmap: true
          smooth: true
        }

        ColorOverlay {
          anchors.fill: dogImg
          visible: dogImg.status === Image.Ready
          source: dogImg
          color: root.fg
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && panelLoader.item && panelLoader.item.label !== ""
        text: panelLoader.item ? panelLoader.item.label : ""
        textFormat: Text.PlainText
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    // Size the slot to the custom content instead of the hidden label.
    fixedWidth: root.vertical ? -1 : Math.max(12, contentRow.implicitWidth + button.scaledHorizontalMargin * 2)
  }
}
