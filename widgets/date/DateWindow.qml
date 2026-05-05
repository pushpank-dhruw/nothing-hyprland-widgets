import QtQuick
import QtQuick.Layouts
import "../../shared"

WidgetWindow {
    id: root

    nsName: "nothing-date"
    variantCount: 1
    widgetWidth: 200
    widgetHeight: 200

    // ---- Config (set from shell.qml) ----
    property int themeMode: 0
    property bool useSystemAccent: false

    // ---- Shared visuals ----
    NothingColors {
        id: nColors
        themeMode: root.themeMode
        useSystemAccent: root.useSystemAccent
    }

    FontLoader {
        id: serifFont
        source: Qt.resolvedUrl("../../shared/fonts/serif.otf")
    }

    FontLoader {
        id: serifLightFont
        source: Qt.resolvedUrl("../../shared/fonts/serif-light.otf")
    }

    // ---- Date state ----
    property string currentDayName: ""
    property string currentDate: ""

    function updateDate() {
        var now = new Date()
        root.currentDayName = Qt.formatDate(now, "ddd")
        root.currentDate = Qt.formatDate(now, "d")
    }

    Timer {
        interval: 60000           // refresh every minute to catch day changes
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateDate()
    }

    // ---- Render ----
    Item {
        anchors.fill: parent

        property bool foldHovered: false

        Rectangle {
            id: mainRect
            anchors.fill: parent
            anchors.margins: 10
            color: nColors.background
            radius: 20
            opacity: 0.95

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: -10

                Text {
                    Layout.alignment: Qt.AlignRight | Qt.AlignTop
                    Layout.topMargin: 10
                    Layout.rightMargin: 10
                    text: root.currentDayName
                    font.family: serifLightFont.name
                    font.pixelSize: Math.min(parent.width * 0.12, parent.height * 0.12)
                    color: nColors.accent
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.currentDate
                    font.family: serifFont.name
                    font.pixelSize: Math.min(parent.width * 0.7, parent.height * 0.7)
                    font.weight: Font.Bold
                    color: nColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Page-peel triangle in the bottom-right corner (matches KDE port)
        Canvas {
            id: peelTriangle
            x: mainRect.x + mainRect.width - width
            y: mainRect.y + mainRect.height - height
            width: parent.foldHovered ? 45 : 30
            height: parent.foldHovered ? 45 : 30

            Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                var outerRadius = parent.foldHovered ? 18 : 16
                var innerRadius = 4

                ctx.fillStyle = nColors.pagePeel
                ctx.beginPath()
                ctx.moveTo(outerRadius, 0)
                ctx.arcTo(0, 0, 0, outerRadius, outerRadius)
                ctx.lineTo(0, height - innerRadius)
                ctx.quadraticCurveTo(0, height, innerRadius, height - innerRadius)
                ctx.lineTo(width - innerRadius, innerRadius)
                ctx.quadraticCurveTo(width, 0, width - innerRadius, 0)
                ctx.closePath()
                ctx.fill()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: nColors
                function onPagePeelChanged() { peelTriangle.requestPaint() }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: parent.parent.foldHovered = true
                onExited: parent.parent.foldHovered = false
            }
        }
    }
}
