import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import "../../shared"

WidgetWindow {
    id: root

    nsName: "nothing-launcher"
    variantCount: 1
    variantCyclable: false

    // ---- Config (set from shell.qml) ----
    property int themeMode: 0
    property bool useSystemAccent: false

    // List of widgets to control. Each entry: { label: string, target: <widget> }
    // The launcher toggles target.visible on click.
    property var items: []

    // ---- Layout sizing (driven by chip count) ----
    readonly property int chipHeight: 30
    readonly property int chipSpacing: 6
    readonly property int padding: 12

    widgetWidth: chipsRow.implicitWidth + padding * 2
    widgetHeight: chipHeight + padding * 2

    // ---- Shared visuals ----
    NothingColors {
        id: nColors
        themeMode: root.themeMode
        useSystemAccent: root.useSystemAccent
    }

    FontLoader {
        id: ndot55Font
        source: Qt.resolvedUrl("../../shared/fonts/ndot-55.otf")
    }

    // ---- Render ----
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: height / 2
        color: nColors.background
        opacity: 0.92
        border.color: nColors.divider
        border.width: 1

        Row {
            id: chipsRow
            anchors.centerIn: parent
            spacing: root.chipSpacing

            Repeater {
                model: root.items

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    readonly property var widgetTarget: modelData.target
                    readonly property string chipLabel: modelData.label
                    // Bind to target.visible so the chip reflects external changes too.
                    readonly property bool active: widgetTarget && widgetTarget.visible

                    width: chipRow.implicitWidth + 18
                    height: root.chipHeight
                    radius: height / 2
                    color: active ? nColors.accent : "transparent"
                    border.color: active ? nColors.accent : nColors.divider
                    border.width: 1

                    Behavior on color        { ColorAnimation  { duration: 150 } }
                    Behavior on border.color { ColorAnimation  { duration: 150 } }
                    Behavior on scale        { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: chip.active ? "#ffffff" : nColors.textSecondary
                            opacity: chip.active ? 1.0 : 0.6
                        }

                        QQC2.Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.chipLabel
                            font.family: ndot55Font.name
                            font.pixelSize: 11
                            font.capitalization: Font.AllUppercase
                            color: chip.active ? "#ffffff" : nColors.textPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        // Sit above the parent WidgetWindow drag area so chip clicks
                        // never get swallowed.
                        z: 10
                        onPressed: chip.scale = 0.93
                        onReleased: chip.scale = 1.0
                        onCanceled: chip.scale = 1.0
                        onClicked: {
                            if (chip.widgetTarget) {
                                chip.widgetTarget.visible = !chip.widgetTarget.visible
                            }
                        }
                    }
                }
            }
        }
    }
}
