import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    // ---- Public API ----
    property string nsName: "nothing-widget"
    property int posX: 40
    property int posY: 40
    property int widgetWidth: 220
    property int widgetHeight: 220

    property int variant: 0
    property int variantCount: 1
    property bool draggable: true
    property bool variantCyclable: true

    signal dragged()
    signal variantCycled()

    // ---- Window setup ----
    color: "transparent"
    anchors { top: true; left: true }
    margins.top: posY
    margins.left: posX
    implicitWidth: widgetWidth
    implicitHeight: widgetHeight
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: false

    // Smooth slide for non-drag position changes (e.g. config edit, snap)
    Behavior on posX {
        enabled: !dragArea.dragging
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    Behavior on posY {
        enabled: !dragArea.dragging
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: {
        if (window.WlrLayershell != null) {
            window.WlrLayershell.layer = WlrLayer.Bottom
            window.WlrLayershell.namespace = window.nsName
        }
    }

    // Drag + variant cycle handler. z: -1 keeps it below user content
    // so inner MouseAreas (e.g. SwipeView dots) still receive their clicks;
    // empty regions of the widget fall through to this.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: dragging ? Qt.SizeAllCursor : Qt.ArrowCursor

        // Track cursor in *global* screen coords so deltas don't drift
        // as the window itself moves underneath the mouse.
        property real pressGlobalX: 0
        property real pressGlobalY: 0
        property int pressPosX: 0
        property int pressPosY: 0
        property bool dragging: false

        onPressed: function(mouse) {
            var g = mapToGlobal(mouse.x, mouse.y)
            pressGlobalX = g.x
            pressGlobalY = g.y
            pressPosX = window.posX
            pressPosY = window.posY
            dragging = false
        }

        onPositionChanged: function(mouse) {
            if (!window.draggable) return
            if ((pressedButtons & Qt.LeftButton) === 0) return

            var g = mapToGlobal(mouse.x, mouse.y)
            var dx = g.x - pressGlobalX
            var dy = g.y - pressGlobalY
            if (!dragging && (Math.abs(dx) > 3 || Math.abs(dy) > 3)) dragging = true
            if (dragging) {
                window.posX = Math.max(0, pressPosX + Math.round(dx))
                window.posY = Math.max(0, pressPosY + Math.round(dy))
            }
        }

        onReleased: function(mouse) {
            if (dragging) window.dragged()
            dragging = false
        }

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton && !dragging
                && window.variantCyclable && window.variantCount > 1) {
                window.variant = (window.variant + 1) % window.variantCount
                window.variantCycled()
            }
        }
    }
}
