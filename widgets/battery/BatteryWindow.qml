import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import "../../shared"

WidgetWindow {
    id: root

    nsName: "nothing-battery"
    variantCount: 1                  // single layout for now
    posX: 400
    posY: 40
    property int widgetSize: 220
    widgetWidth: widgetSize
    widgetHeight: widgetSize

    // ---- Config ----
    property int themeMode: 0
    property bool useSystemAccent: false
    property bool showBluetoothDevices: true

    Component.onCompleted: refreshBluetoothDevices()

    NothingColors {
        id: nColors
        themeMode: root.themeMode
        useSystemAccent: root.useSystemAccent
    }

    FontLoader { id: ndotFont; source: Qt.resolvedUrl("../../shared/fonts/ndot-55.otf") }

    // ---- System battery (UPower display device) ----
    readonly property var displayDevice: UPower.displayDevice
    readonly property bool hasBattery: displayDevice && displayDevice.isPresent && displayDevice.isLaptopBattery
    readonly property int batteryPercent: displayDevice ? Math.round(displayDevice.percentage) : 0
    readonly property bool isCharging: displayDevice && displayDevice.state === UPowerDeviceState.Charging
    readonly property bool showMainBattery: hasBattery && !(batteryPercent === 0 && isCharging)

    // ---- Bluetooth devices with battery ----
    property var bluetoothDevices: []

    function refreshBluetoothDevices() {
        if (!root.showBluetoothDevices) {
            bluetoothDevices = []
            return
        }
        var list = []
        var devices = Bluetooth.devices ? Bluetooth.devices.values : []
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (d.connected && d.batteryAvailable) {
                list.push({
                    name: d.name || d.deviceName || "Device",
                    address: d.address,
                    percentage: Math.round(d.battery * 100),
                    icon: mapBluetoothIcon(d.icon, d.name || d.deviceName || "")
                })
            }
        }
        bluetoothDevices = list
    }

    function mapBluetoothIcon(iconName, deviceName) {
        var icon = (iconName || "").toLowerCase()
        var name = (deviceName || "").toLowerCase()
        var combined = icon + " " + name
        if (combined.indexOf("earbud") !== -1) return "earbuds"
        if (combined.indexOf("audio") !== -1 || combined.indexOf("headset") !== -1 || combined.indexOf("headphone") !== -1) return "headset"
        if (combined.indexOf("mouse") !== -1) return "mouse"
        if (combined.indexOf("keyboard") !== -1) return "keyboard"
        if (combined.indexOf("watch") !== -1) return "watch"
        if (combined.indexOf("phone") !== -1) return "watch"
        if (combined.indexOf("speaker") !== -1) return "speaker"
        if (combined.indexOf("controller") !== -1 || combined.indexOf("gamepad") !== -1) return "controller"
        if (combined.indexOf("computer") !== -1) return "computer"
        return ""
    }

    Connections {
        target: Bluetooth.devices
        function onValuesChanged() { refreshBluetoothDevices() }
    }

    Timer {
        interval: 10000
        running: root.showBluetoothDevices
        repeat: true
        onTriggered: refreshBluetoothDevices()
    }


    // ---- Layout ----
    Rectangle {
        id: mainBackground
        anchors.fill: parent
        anchors.margins: 10
        color: nColors.background
        radius: 20
        opacity: 0.95

        readonly property int deviceCount: (root.showMainBattery ? 1 : 0) + root.bluetoothDevices.length
        readonly property real cellWidth: (width - 40) / 2
        readonly property real cellHeight: (height - 40) / 2

        function slotDevice(slot) {
            var mainOffset = root.showMainBattery ? 1 : 0
            if (slot === 0 && root.showMainBattery) return { type: "main" }
            var btIndex = slot - mainOffset
            if (btIndex >= 0 && btIndex < root.bluetoothDevices.length) return { type: "bt", index: btIndex }
            return null
        }

        function slotPercentage(slot) {
            var dev = slotDevice(slot); if (!dev) return 0
            return dev.type === "main" ? root.batteryPercent : root.bluetoothDevices[dev.index].percentage
        }
        function slotIsCharging(slot) {
            var dev = slotDevice(slot)
            return dev && dev.type === "main" ? root.isCharging : false
        }
        function slotDeviceType(slot) {
            var dev = slotDevice(slot)
            return dev && dev.type === "main" ? "laptop" : ""
        }
        function slotDeviceIcon(slot) {
            var dev = slotDevice(slot); if (!dev || dev.type === "main") return ""
            return root.bluetoothDevices[dev.index].icon
        }
        function slotIsSystem(slot) {
            var dev = slotDevice(slot)
            return dev ? dev.type === "main" : false
        }

        readonly property var gridPositions: [
            { gx: 15, gy: 15 },
            { gx: 15 + cellWidth + 10, gy: 15 },
            { gx: 15, gy: 15 + cellHeight + 10 },
            { gx: 15 + cellWidth + 10, gy: 15 + cellHeight + 10 }
        ]

        Repeater {
            model: 4
            delegate: Item {
                required property int index
                x: mainBackground.gridPositions[index].gx
                y: mainBackground.gridPositions[index].gy
                width: mainBackground.cellWidth
                height: mainBackground.cellHeight
                visible: mainBackground.deviceCount > index

                CircularBatteryProgress {
                    anchors.fill: parent
                    percentage: mainBackground.slotPercentage(parent.index)
                    isCharging: mainBackground.slotIsCharging(parent.index)
                    deviceType: mainBackground.slotDeviceType(parent.index)
                    deviceIcon: mainBackground.slotDeviceIcon(parent.index)
                    isSystemDevice: mainBackground.slotIsSystem(parent.index)
                    colors: nColors
                }
            }
        }

        // PC label when no battery present
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 20
            anchors.bottomMargin: 20
            text: "PC"
            font.family: ndotFont.name
            font.pixelSize: 17
            color: nColors.textPrimary
            opacity: 0.6
            visible: !root.showMainBattery && root.bluetoothDevices.length === 0
        }
    }
}
