import QtQuick
import "Singletons"

Rectangle {
    id: chip
    property real s: 1
    property string glyph: ""
    property bool on: false
    property string tipTitle: ""
    property string tipDesc: ""
    signal toggled()

    width: 26 * s
    height: 26 * s
    radius: 8 * s
    color: chip.on ? Theme.frameBg : "transparent"
    border.width: 1
    border.color: chip.on ? Theme.frameBorder : Theme.border

    GlyphIcon {
        anchors.centerIn: parent
        width: 15 * s
        height: 15 * s
        name: chip.glyph
        color: chip.on ? Theme.vermLit : Theme.iconDim
        stroke: 1.7
    }
    HoverHandler {
        id: chipHover
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.toggled()
    }

    Tooltip {
        s: chip.s
        placement: "below"
        title: chip.tipTitle
        desc: chip.tipDesc
        show: chipHover.hovered
    }
}
