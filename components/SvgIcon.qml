import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons

// Tinted SVG icon. The plugin's assets/*.svg draw with currentColor (black
// strokes at render time), so — like the tile artwork and hero badge — they
// are whitened through a ColorOverlay into the theme foreground and stay
// readable on any theme. `source` takes a file name under ../assets/ or any
// resolved url containing "://".
Item {
    id: root

    property string source: ""
    property color color: Qt.rgba(1, 1, 1, 0.9)
    property real size: Style.font.icon

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        source: root.source.indexOf("://") >= 0 ? root.source : Qt.resolvedUrl("../assets/" + root.source)
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        // Decode at device pixels so a 24px-viewBox stroke rasterizes 1:1
        // instead of blurring through bilinear resampling.
        sourceSize.width: Math.round(root.size * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.size * Screen.devicePixelRatio)
    }

    ColorOverlay {
        anchors.fill: img
        visible: img.status === Image.Ready
        source: img
        color: root.color
        cached: false
    }
}
