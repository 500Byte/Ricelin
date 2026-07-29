import QtQuick

/**
 * Wheel-to-Flickable bridge for layer-shell surfaces, where the native
 * WheelHandler path is unreliable: a button-less MouseArea converts wheel
 * notches into clamped contentY steps on the target Flickable.
 */
MouseArea {
    id: root

    property real s: 1
    property int orientation: Qt.Vertical
    required property Flickable flick

    acceptedButtons: Qt.NoButton

    onWheel: function(event) {
        if (orientation === Qt.Vertical) {
            var max = Math.max(0, flick.contentHeight - flick.height);
            flick.contentY = Math.max(0, Math.min(max, flick.contentY - event.angleDelta.y / 120 * 36 * s));
        } else {
            var max = Math.max(0, flick.contentWidth - flick.width);
            flick.contentX = Math.max(0, Math.min(max, flick.contentX - event.angleDelta.y / 120 * 36 * s));
        }
        event.accepted = true;
    }
}
