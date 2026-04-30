import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import "../../shared"

WidgetWindow {
    id: root

    nsName: "nothing-clock-digital"
    variantCount: 2                        // 0 = digital, 1 = world clock
    widgetWidth: 320
    widgetHeight: 100

    // ---- Config (set from shell.qml) ----
    property alias widgetVariant: root.variant   // back-compat
    property int themeMode: 0
    property bool useSystemAccent: false
    property bool use24HourFormat: true

    property string cityName: "London"
    property string timeZone: "Europe/London"

    // ---- Shared visuals ----
    NothingColors {
        id: nColors
        themeMode: root.themeMode
        useSystemAccent: root.useSystemAccent
    }

    FontLoader {
        id: ndotFont
        source: Qt.resolvedUrl("../../shared/fonts/ndot.ttf")
    }

    FontLoader {
        id: ndot55Font
        source: Qt.resolvedUrl("../../shared/fonts/ndot-55.otf")
    }

    // ---- Digital clock state ----
    property string currentHours: ""
    property string currentMinutes: ""
    property string hoursDigit1: "0"
    property string hoursDigit2: "0"
    property string minutesDigit1: "0"
    property string minutesDigit2: "0"

    function updateDigitalTime() {
        var now = new Date()
        var hours = now.getHours()

        root.amPm = hours >= 12 ? "PM" : "AM"

        if (!root.use24HourFormat) {
            hours = hours % 12
            if (hours === 0) hours = 12
        }

        var minutes = now.getMinutes()

        var hoursStr = hours < 10 ? "0" + hours : hours.toString()
        var minutesStr = minutes < 10 ? "0" + minutes : minutes.toString()

        root.currentHours = hoursStr
        root.currentMinutes = minutesStr

        root.hoursDigit1 = hoursStr.length > 1 ? hoursStr[0] : "0"
        root.hoursDigit2 = hoursStr.length > 1 ? hoursStr[1] : hoursStr[0]
        root.minutesDigit1 = minutesStr[0]
        root.minutesDigit2 = minutesStr[1]
    }

    // ---- World clock state ----
    readonly property string cityAbbrev: cityName.substring(0, 3).toUpperCase()
    property string amPm: "AM"
    property string dayOfWeek: "Friday"
    property string hourDifference: "+0.0"
    property int currentSeconds: 0

    TimezonesData { id: timezonesDataSource }
    property var timezonesData: ({})

    function loadTimezones() {
        var timezoneMap = {}
        for (var i = 0; i < timezonesDataSource.timezones.length; i++) {
            var tz = timezonesDataSource.timezones[i]
            timezoneMap[tz.id] = tz
        }
        root.timezonesData = timezoneMap
    }

    // DST helpers (copied verbatim from KDE port)
    function nthWeekday(year, month, weekday, n) {
        var d = new Date(Date.UTC(year, month, 1))
        var count = 0
        while (d.getUTCMonth() === month) {
            if (d.getUTCDay() === weekday) {
                count++
                if (count === n) return d.getUTCDate()
            }
            d.setUTCDate(d.getUTCDate() + 1)
        }
        return 1
    }

    function lastWeekday(year, month, weekday) {
        var d = new Date(Date.UTC(year, month + 1, 0))
        while (d.getUTCDay() !== weekday) {
            d.setUTCDate(d.getUTCDate() - 1)
        }
        return d.getUTCDate()
    }

    function isDSTActive(utcDate, dstGroup) {
        if (!dstGroup || dstGroup === "") return false

        var year = utcDate.getUTCFullYear()
        var month = utcDate.getUTCMonth()
        var day = utcDate.getUTCDate()

        if (dstGroup === "namerica") {
            var marStart = nthWeekday(year, 2, 0, 2)
            var novEnd = nthWeekday(year, 10, 0, 1)
            var afterStart = (month > 2) || (month === 2 && day >= marStart)
            var beforeEnd = (month < 10) || (month === 10 && day < novEnd)
            return afterStart && beforeEnd
        }
        if (dstGroup === "europe") {
            var marLast = lastWeekday(year, 2, 0)
            var octLast = lastWeekday(year, 9, 0)
            var afterStart2 = (month > 2) || (month === 2 && day >= marLast)
            var beforeEnd2 = (month < 9) || (month === 9 && day < octLast)
            return afterStart2 && beforeEnd2
        }
        if (dstGroup === "australia") {
            var octStart = nthWeekday(year, 9, 0, 1)
            var aprEnd = nthWeekday(year, 3, 0, 1)
            var inSummer = (month > 9) || (month === 9 && day >= octStart)
            var beforeApr = (month < 3) || (month === 3 && day < aprEnd)
            return inSummer || beforeApr
        }
        if (dstGroup === "nz") {
            var sepLast = lastWeekday(year, 8, 0)
            var aprEndNZ = nthWeekday(year, 3, 0, 1)
            var inSummerNZ = (month > 8) || (month === 8 && day >= sepLast)
            var beforeAprNZ = (month < 3) || (month === 3 && day < aprEndNZ)
            return inSummerNZ || beforeAprNZ
        }
        return false
    }

    function getTimezoneOffset(timezone) {
        if (!root.timezonesData || !root.timezonesData[timezone]) return 0
        var tz = root.timezonesData[timezone]
        var offset = tz.offset
        if (isDSTActive(new Date(), tz.dst || "")) offset += 1.0
        return offset
    }

    function getTimeInTimezone(timezone) {
        var now = new Date()
        var offset = getTimezoneOffset(timezone)
        var totalMinutes = (now.getUTCHours() * 60 + now.getUTCMinutes()) + (offset * 60)

        while (totalMinutes < 0) totalMinutes += 24 * 60
        while (totalMinutes >= 24 * 60) totalMinutes -= 24 * 60

        var hours = Math.floor(totalMinutes / 60)
        var minutes = totalMinutes % 60

        var ampm = "AM"
        if (hours >= 12) {
            ampm = "PM"
            if (hours > 12) hours -= 12
        }
        if (hours === 0) hours = 12

        var minutesStr = minutes < 10 ? "0" + minutes : minutes.toString()
        var hoursStr = hours < 10 ? "0" + hours : hours.toString()
        return hoursStr + ":" + minutesStr + " " + ampm
    }

    function getDayOfWeekInTimezone(timezone) {
        var now = new Date()
        var offset = getTimezoneOffset(timezone)
        var totalHours = now.getUTCHours() + offset

        var dayOffset = 0
        if (totalHours < 0) dayOffset = -1
        if (totalHours >= 24) dayOffset = 1

        var adjustedDay = (now.getUTCDay() + dayOffset + 7) % 7
        var dayNames = ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
        return dayNames[adjustedDay]
    }

    function calculateHourDifference(timezone) {
        var now = new Date()
        var localOffsetHours = -now.getTimezoneOffset() / 60
        var selectedOffsetHours = getTimezoneOffset(timezone)
        var diff = selectedOffsetHours - localOffsetHours
        var sign = diff >= 0 ? "+" : ""
        if (diff === Math.floor(diff)) return sign + diff.toFixed(0)
        return sign + diff.toFixed(1)
    }

    function updateWorldTime() {
        var timeStr = getTimeInTimezone(timeZone).trim()

        var ampmIndex = -1
        if (timeStr.toUpperCase().indexOf("AM") !== -1) {
            ampmIndex = timeStr.toUpperCase().indexOf("AM"); amPm = "AM"
        } else if (timeStr.toUpperCase().indexOf("PM") !== -1) {
            ampmIndex = timeStr.toUpperCase().indexOf("PM"); amPm = "PM"
        }

        var currentTime = ampmIndex !== -1 ? timeStr.substring(0, ampmIndex).trim() : (function(){ amPm = ""; return timeStr })()
        var timeParts = currentTime.split(":")
        if (timeParts.length >= 2) {
            currentHours = timeParts[0].trim()
            currentMinutes = timeParts[1].trim()
            if (currentHours.length === 1) currentHours = "0" + currentHours
            if (currentMinutes.length === 1) currentMinutes = "0" + currentMinutes
        } else {
            currentHours = "12"; currentMinutes = "00"
        }

        dayOfWeek = getDayOfWeekInTimezone(timeZone)
        hourDifference = calculateHourDifference(timeZone)
    }

    onTimeZoneChanged: if (widgetVariant === 1) updateWorldTime()
    onCityNameChanged: if (widgetVariant === 1) updateWorldTime()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentSeconds = new Date().getSeconds()
            if (root.widgetVariant === 0) root.updateDigitalTime()
            else if (root.widgetVariant === 1) root.updateWorldTime()
        }
    }

    Component.onCompleted: {
        loadTimezones()
        if (widgetVariant === 1) updateWorldTime()
        else if (widgetVariant === 0) updateDigitalTime()
    }

    onWidgetVariantChanged: {
        if (widgetVariant === 0) updateDigitalTime()
        else if (widgetVariant === 1) updateWorldTime()
    }

    // ---- Variant loader ----
    Loader {
        id: variantLoader
        anchors.fill: parent
        sourceComponent: root.widgetVariant === 0 ? digitalComponent : worldComponent
    }

    // ====================================================================
    // DIGITAL CLOCK (variant 0) — pill auto-detected when aspect ratio >=1.8
    // ====================================================================
    Component {
        id: digitalComponent
        Item {
            readonly property real calculatedRadius: {
                var aspectRatio = width / height
                if (aspectRatio >= 1.8) return height / 2
                return 20
            }
            readonly property bool isPillMode: (width / height) >= 1.8

            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                color: nColors.background
                radius: parent.calculatedRadius
                opacity: 0.95

                // Vertical layout (square mode)
                Item {
                    anchors.fill: parent
                    visible: !parent.parent.isPillMode

                    Column {
                        anchors.centerIn: parent
                        spacing: 5

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Text {
                                width: Math.min(parent.parent.parent.width * 0.2, parent.parent.parent.height * 0.15)
                                text: root.hoursDigit1
                                font.family: ndotFont.name
                                font.pixelSize: Math.min(parent.parent.parent.width * 0.25, parent.parent.parent.height * 0.2)
                                color: nColors.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                width: Math.min(parent.parent.parent.width * 0.2, parent.parent.parent.height * 0.15)
                                text: root.hoursDigit2
                                font.family: ndotFont.name
                                font.pixelSize: Math.min(parent.parent.parent.width * 0.25, parent.parent.parent.height * 0.2)
                                color: nColors.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Text {
                                width: Math.min(parent.parent.parent.width * 0.2, parent.parent.parent.height * 0.15)
                                text: root.minutesDigit1
                                font.family: ndotFont.name
                                font.pixelSize: Math.min(parent.parent.parent.width * 0.25, parent.parent.parent.height * 0.2)
                                color: nColors.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                width: Math.min(parent.parent.parent.width * 0.2, parent.parent.parent.height * 0.15)
                                text: root.minutesDigit2
                                font.family: ndotFont.name
                                font.pixelSize: Math.min(parent.parent.parent.width * 0.25, parent.parent.parent.height * 0.2)
                                color: nColors.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !root.use24HourFormat
                            text: root.amPm
                            font.family: ndot55Font.name
                            font.pixelSize: Math.min(parent.parent.parent.width * 0.1, parent.parent.parent.height * 0.09)
                            color: nColors.textPrimary
                            opacity: 0.75
                            topPadding: 4
                        }
                    }
                }

                // Horizontal layout (pill mode)
                Item {
                    anchors.fill: parent
                    visible: parent.parent.isPillMode

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.hoursDigit1
                            font.family: ndotFont.name
                            font.pixelSize: Math.min(parent.parent.width * 0.15, parent.parent.height * 0.5)
                            color: nColors.textPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.hoursDigit2
                            font.family: ndotFont.name
                            font.pixelSize: Math.min(parent.parent.width * 0.15, parent.parent.height * 0.5)
                            color: nColors.textPrimary
                        }

                        BlinkingSeparator {
                            anchors.verticalCenter: parent.verticalCenter
                            dotSize: Math.min(parent.parent.height * 0.07, 10)
                            dotColor: nColors.textPrimary
                            dotSpacing: Math.min(parent.parent.height * 0.1, 8)
                            seconds: root.currentSeconds
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.minutesDigit1
                            font.family: ndotFont.name
                            font.pixelSize: Math.min(parent.parent.width * 0.15, parent.parent.height * 0.5)
                            color: nColors.textPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.minutesDigit2
                            font.family: ndotFont.name
                            font.pixelSize: Math.min(parent.parent.width * 0.15, parent.parent.height * 0.5)
                            color: nColors.textPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.use24HourFormat
                            text: root.amPm
                            font.family: ndot55Font.name
                            font.pixelSize: Math.min(parent.parent.width * 0.08, parent.parent.height * 0.3)
                            color: nColors.textPrimary
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }

    // ====================================================================
    // WORLD CLOCK (variant 1) — square SwipeView + pill mode
    // ====================================================================
    Component {
        id: worldComponent
        Item {
            readonly property bool isPillMode: (width / height) >= 1.8
            readonly property real calculatedRadius: {
                var aspectRatio = width / height
                if (aspectRatio >= 1.8) return height / 2
                return 20
            }

            // Square / SwipeView layout
            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                color: nColors.background
                radius: parent.calculatedRadius
                opacity: 0.95
                visible: !parent.isPillMode

                QQC2.SwipeView {
                    id: swipeView
                    anchors.fill: parent
                    anchors.margins: 15
                    currentIndex: 0
                    clip: true
                    orientation: Qt.Vertical

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Text {
                                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                                Layout.topMargin: 5
                                text: root.cityName
                                font.family: ndot55Font.name
                                font.pixelSize: Math.min(parent.width * 0.13, parent.height * 0.13)
                                color: nColors.textPrimary
                                opacity: 0.9
                            }

                            Item { Layout.fillHeight: true }

                            RowLayout {
                                Layout.alignment: Qt.AlignLeft | Qt.AlignBottom
                                Layout.bottomMargin: 10
                                Layout.fillWidth: true
                                spacing: 8

                                Row {
                                    spacing: 4
                                    Text {
                                        text: root.currentHours
                                        font.family: ndotFont.name
                                        font.pixelSize: Math.min(parent.parent.parent.width * 0.18, parent.parent.parent.height * 0.18)
                                        color: nColors.textPrimary
                                    }
                                    Text {
                                        text: ":"
                                        font.family: ndotFont.name
                                        font.pixelSize: Math.min(parent.parent.parent.width * 0.18, parent.parent.parent.height * 0.18)
                                        color: nColors.textPrimary
                                        opacity: (root.currentSeconds % 2) === 0 ? 1.0 : 0.3
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    Text {
                                        text: root.currentMinutes
                                        font.family: ndotFont.name
                                        font.pixelSize: Math.min(parent.parent.parent.width * 0.18, parent.parent.parent.height * 0.18)
                                        color: nColors.textPrimary
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    text: root.amPm
                                    font.family: ndot55Font.name
                                    font.pixelSize: Math.min(parent.parent.width * 0.12, parent.parent.height * 0.12)
                                    color: nColors.textPrimary
                                    opacity: 0.85
                                }

                                Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }
                            }
                        }
                    }

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Text {
                                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                                Layout.topMargin: 5
                                text: root.dayOfWeek
                                font.family: ndot55Font.name
                                font.pixelSize: Math.min(parent.width * 0.13, parent.height * 0.13)
                                color: nColors.textPrimary
                                opacity: 0.9
                            }

                            Item { Layout.fillHeight: true }

                            RowLayout {
                                Layout.alignment: Qt.AlignLeft | Qt.AlignBottom
                                Layout.bottomMargin: 10
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.alignment: Qt.AlignBottom
                                    text: root.hourDifference
                                    font.family: ndotFont.name
                                    font.pixelSize: Math.min(parent.parent.width * 0.18, parent.parent.height * 0.18)
                                    color: nColors.textPrimary
                                }
                                Text {
                                    Layout.alignment: Qt.AlignBottom
                                    text: "H"
                                    font.family: ndot55Font.name
                                    font.pixelSize: Math.min(parent.parent.width * 0.075, parent.parent.height * 0.075)
                                    color: nColors.textPrimary
                                    opacity: 0.85
                                    Layout.bottomMargin: 5
                                }
                            }
                        }
                    }
                }
            }

            // Page indicator
            Column {
                anchors {
                    right: parent.right
                    rightMargin: 16
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8
                z: 100
                visible: !parent.isPillMode

                Repeater {
                    model: 2
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: swipeView.currentIndex === index ? nColors.indicatorActive : nColors.indicatorInactive
                        opacity: swipeView.currentIndex === index ? 0.95 : 0.45
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: swipeView.currentIndex = index
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                z: 5
                visible: !parent.isPillMode
                onWheel: (wheel) => {
                    if (wheel.angleDelta.y < 0) swipeView.incrementCurrentIndex()
                    else if (wheel.angleDelta.y > 0) swipeView.decrementCurrentIndex()
                }
            }

            // Pill mode
            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                color: nColors.background
                radius: parent.calculatedRadius
                opacity: 0.95
                visible: parent.isPillMode

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: parent.radius * 0.5
                    anchors.topMargin: parent.height * 0.12
                    text: root.cityAbbrev
                    font.family: ndot55Font.name
                    font.pixelSize: parent.height * 0.18
                    color: nColors.textSecondary
                    opacity: 0.8
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.currentHours
                        font.family: ndotFont.name
                        font.pixelSize: Math.min(parent.parent.width * 0.12, parent.parent.height * 0.5)
                        color: nColors.textPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        font.family: ndotFont.name
                        font.pixelSize: Math.min(parent.parent.width * 0.12, parent.parent.height * 0.5)
                        color: nColors.textPrimary
                        opacity: (root.currentSeconds % 2) === 0 ? 1.0 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.currentMinutes
                        font.family: ndotFont.name
                        font.pixelSize: Math.min(parent.parent.width * 0.12, parent.parent.height * 0.5)
                        color: nColors.textPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.amPm
                        font.family: ndot55Font.name
                        font.pixelSize: Math.min(parent.parent.width * 0.08, parent.parent.height * 0.3)
                        color: nColors.textPrimary
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
