import QtQuick
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

  // Plugin emblem (assets/icon.png) instead of a font glyph; falls back to
  // the OpticalGlyph text whenever iconComponent is null.
  Component {
    id: dogIconComponent

    Image {
      anchors.fill: parent
      source: Qt.resolvedUrl("assets/icon.png")
      fillMode: Image.PreserveAspectFit
      mipmap: true
      smooth: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: dogIconComponent
    text: panelLoader.item ? panelLoader.item.label : "󰊓"
    slotSize: Style.bar.statusSlot
    tooltipText: panelLoader.item ? panelLoader.item.barTooltip : "Wardogs Zone"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) { if (panelLoader.item && panelLoader.item.openSettings) panelLoader.item.openSettings() }
      else if (b === Qt.MiddleButton) root.toggleWindow()
      else root.togglePanel()
    }
  }
}
