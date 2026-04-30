import QtQuick
import QtQuick.Effects

Item {
    id: cell

    property int percentage: 0
    property bool isCharging: false
    property string deviceType: "laptop"   // "laptop" | "computer" | "mouse" | "headphones" | "keyboard" | "watch" | "speaker" | "controller" | "earbuds" | "earbuds-case" | ""
    property string deviceIcon: ""         // Specific icon name (overrides deviceType)
    property bool isSystemDevice: true
    property int criticalThreshold: 20
    required property QtObject colors

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real outerRadius: Math.min(width, height) / 2

    // Pie-chart progress
    Canvas {
        id: progressCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            ctx.beginPath()
            ctx.arc(cell.centerX, cell.centerY, cell.outerRadius, 0, 2 * Math.PI)
            ctx.fillStyle = cell.colors.batteryBgFill
            ctx.fill()

            if (cell.percentage > 0) {
                ctx.beginPath()
                ctx.moveTo(cell.centerX, cell.centerY)
                var startAngle = -Math.PI / 2
                var endAngle = startAngle + (cell.percentage / 100 * 2 * Math.PI)
                ctx.arc(cell.centerX, cell.centerY, cell.outerRadius, startAngle, endAngle)
                ctx.closePath()
                ctx.fillStyle = cell.percentage <= cell.criticalThreshold
                                ? cell.colors.accent
                                : cell.colors.batteryProgressFill
                ctx.fill()
            }
        }

        Connections {
            target: cell
            function onPercentageChanged() { progressCanvas.requestPaint() }
        }
        Connections {
            target: cell.colors
            function onBatteryBgFillChanged() { progressCanvas.requestPaint() }
            function onBatteryProgressFillChanged() { progressCanvas.requestPaint() }
            function onAccentChanged() { progressCanvas.requestPaint() }
        }
    }

    function iconUrl() {
        if (cell.deviceIcon !== "") return Qt.resolvedUrl("icons/" + cell.deviceIcon + ".svg")
        switch (cell.deviceType) {
            case "laptop":      return Qt.resolvedUrl("icons/laptop.svg")
            case "computer":    return Qt.resolvedUrl("icons/computer.svg")
            case "mouse":       return Qt.resolvedUrl("icons/mouse.svg")
            case "headphones":  return Qt.resolvedUrl("icons/headset.svg")
            case "keyboard":    return Qt.resolvedUrl("icons/keyboard.svg")
            case "watch":       return Qt.resolvedUrl("icons/watch.svg")
            case "speaker":     return Qt.resolvedUrl("icons/speaker.svg")
            case "controller":  return Qt.resolvedUrl("icons/controller.svg")
            case "earbuds":     return Qt.resolvedUrl("icons/earbuds.svg")
            default:            return ""
        }
    }

    // Centered icon area
    Item {
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6

        Item {
            id: deviceIconContainer
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.75
            height: parent.height * 0.75

            readonly property bool hasStatusIndicator: cell.isSystemDevice && cell.isCharging
            y: hasStatusIndicator ? 0 : (parent.height - height) / 2

            Image {
                id: deviceIcon
                anchors.fill: parent
                source: cell.iconUrl()
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 128
                sourceSize.height: 128
                visible: false   // tinted via MultiEffect
                smooth: true
            }

            MultiEffect {
                anchors.fill: deviceIcon
                source: deviceIcon
                colorization: 1.0
                colorizationColor: cell.colors.iconColor
                opacity: 0.9
            }
        }

        // Charging indicator
        Item {
            id: statusIndicator
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: deviceIconContainer.bottom
            anchors.topMargin: parent.height * 0.05
            width: Math.min(parent.width, parent.height) * 0.5
            height: Math.min(parent.width, parent.height) * 0.5
            visible: cell.isSystemDevice && cell.isCharging

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: cell.colors.accent
                opacity: 0.95
            }

            Image {
                id: chargingIcon
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: parent.height * 0.6
                source: Qt.resolvedUrl("icons/charging_mode.svg")
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 64
                sourceSize.height: 64
                visible: false
                smooth: true
            }

            MultiEffect {
                anchors.fill: chargingIcon
                source: chargingIcon
                colorization: 1.0
                colorizationColor: cell.colors.background
            }
        }
    }
}
