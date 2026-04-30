import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls as QQC2
import "../../shared"

WidgetWindow {
    id: root

    nsName: "nothing-weather"
    variantCount: 4
    // Variants:
    //   0 = Rect Page 1   — wide layout, header + 6-day daily forecast
    //   1 = Rect Page 2   — wide layout, header + 6-hour hourly forecast
    //   2 = Square Page 1 — temp + icon + city
    //   3 = Square Page 2 — high/low + condition
    posX: 280
    posY: 280

    // Dynamic size: rect variants are 480×180, square are 220×220.
    readonly property bool isRectVariant: variant <= 1
    widgetWidth: isRectVariant ? 480 : 220
    widgetHeight: isRectVariant ? 180 : 220

    // ---- Config ----
    property int themeMode: 0
    property bool useSystemAccent: false
    property string location: "London, UK"
    property int temperatureUnit: 0  // 0 = °C, 1 = °F
    property int refreshIntervalMs: 10 * 60 * 1000   // 10 min

    NothingColors {
        id: nColors
        themeMode: root.themeMode
        useSystemAccent: root.useSystemAccent
    }

    FontLoader { id: ndotFont; source: Qt.resolvedUrl("../../shared/fonts/ndot-55.otf") }

    // ---- Weather state ----
    property string currentTemp: "--"
    property string highTemp: "--"
    property string lowTemp: "--"
    property string condition: "Loading..."
    property int weatherCode: 0
    property double latitude: 0
    property double longitude: 0
    property bool isLoading: true
    property string errorMessage: ""

    property var dailyDays: []
    property var dailyIcons: []
    property var dailyHighs: []
    property var dailyLows: []

    property var hourlyTimes: []
    property var hourlyIcons: []
    property var hourlyTemps: []

    readonly property string apiTempUnit: temperatureUnit === 0 ? "celsius" : "fahrenheit"

    function getWeatherIcon(code) {
        var hour = new Date().getHours()
        var isNight = hour < 7 || hour >= 19
        var base = "icons/"
        if (code === 0) return Qt.resolvedUrl(base + (isNight ? "partly_cloudy_night.svg" : "sunny.svg"))
        if (code === 1 || code === 2) return Qt.resolvedUrl(base + (isNight ? "partly_cloudy_night.svg" : "partly_cloudy_day.svg"))
        if (code === 3) return Qt.resolvedUrl(base + "cloudy.svg")
        if (code === 45 || code === 48) return Qt.resolvedUrl(base + "rain_or_mist.svg")
        if ([51,53,55,56,57,61,63,65,66,67,80,81,82].indexOf(code) !== -1) return Qt.resolvedUrl(base + "rain_or_mist.svg")
        if ([71,73,75,77,85,86].indexOf(code) !== -1) return Qt.resolvedUrl(base + "snow_fall.svg")
        if ([95,96,99].indexOf(code) !== -1) return Qt.resolvedUrl(base + "thunder.svg")
        return Qt.resolvedUrl(base + (isNight ? "partly_cloudy_night.svg" : "sunny.svg"))
    }

    function getWeatherCondition(code) {
        var map = {
            0: "Clear", 1: "Mainly Clear", 2: "Partly Cloudy", 3: "Overcast",
            45: "Fog", 48: "Rime Fog",
            51: "Light Drizzle", 53: "Drizzle", 55: "Dense Drizzle",
            56: "Freezing Drizzle", 57: "Freezing Drizzle",
            61: "Light Rain", 63: "Rain", 65: "Heavy Rain",
            66: "Freezing Rain", 67: "Freezing Rain",
            71: "Light Snow", 73: "Snow", 75: "Heavy Snow", 77: "Snow Grains",
            80: "Rain Showers", 81: "Rain Showers", 82: "Heavy Showers",
            85: "Snow Showers", 86: "Heavy Snow Showers",
            95: "Thunderstorm", 96: "Thunderstorm", 99: "Heavy Thunderstorm"
        }
        return map[code] || "Unknown"
    }

    function getDayName(daysAhead) {
        var d = new Date(); d.setDate(d.getDate() + daysAhead)
        return ["SUN","MON","TUE","WED","THU","FRI","SAT"][d.getDay()]
    }

    function processDailyForecast(daily) {
        var days = [], icons = [], highs = [], lows = []
        for (var i = 1; i <= 6; i++) {
            days.push(getDayName(i))
            icons.push(daily.weather_code[i])
            highs.push(Math.round(daily.temperature_2m_max[i]).toString())
            lows.push(Math.round(daily.temperature_2m_min[i]).toString())
        }
        dailyDays = days; dailyIcons = icons; dailyHighs = highs; dailyLows = lows
    }

    function processHourlyForecast(hourly) {
        var times = [], icons = [], temps = []
        var now = new Date()
        var startHour = now.getHours() + 1
        var maxHour = startHour + 11

        for (var i = 0; i < hourly.time.length && times.length < 6; i++) {
            var hour = parseInt(hourly.time[i].substring(11, 13))
            if (hour < startHour || hour > maxHour) continue

            var displayHour = hour, ampm = " AM"
            if (hour >= 12) { ampm = " PM"; if (hour > 12) displayHour = hour - 12 }
            if (displayHour === 0) displayHour = 12

            times.push(displayHour + ampm)
            icons.push(hourly.weather_code[i])
            temps.push(Math.round(hourly.temperature_2m[i]).toString())
        }
        hourlyTimes = times; hourlyIcons = icons; hourlyTemps = temps
    }

    readonly property string weatherIconPath: getWeatherIcon(weatherCode)

    // ---- Geocoding ----
    function hintMatches(hint, words, fullFields) {
        if (words.indexOf(hint) !== -1 || fullFields.indexOf(hint) !== -1) return true
        if (hint.length >= 2 && hint.length <= 5) {
            for (var i = 0; i < fullFields.length; i++) {
                var fw = fullFields[i].split(/\s+/)
                if (fw.length === hint.length) {
                    var ok = true
                    for (var c = 0; c < hint.length; c++) {
                        if (!fw[c] || fw[c].charAt(0) !== hint.charAt(c)) { ok = false; break }
                    }
                    if (ok) return true
                }
            }
        }
        return false
    }

    function pickBestResult(results, hints) {
        if (hints.length === 0 || results.length === 1) return results[0]
        for (var i = 0; i < results.length; i++) {
            var r = results[i]
            var fields = [r.country || "", r.country_code || "", r.admin1 || "", r.admin2 || "", r.admin3 || ""]
            var words = fields.join(" ").toLowerCase().split(/\s+/)
            var fullFields = fields.map(function(f) { return f.toLowerCase() })
            var allMatch = true
            for (var j = 0; j < hints.length; j++) {
                if (!hintMatches(hints[j].toLowerCase(), words, fullFields)) { allMatch = false; break }
            }
            if (allMatch) return r
        }
        return results[0]
    }

    function geocodeLocation() {
        isLoading = true; errorMessage = ""
        var parts = location.split(",").map(function(s) { return s.trim() })
        var city = parts[0]
        var hints = parts.slice(1).filter(function(s) { return s.length > 0 })

        var xhr = new XMLHttpRequest()
        var url = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(city) + "&count=10&language=en&format=json"
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.results && resp.results.length > 0) {
                        var best = pickBestResult(resp.results, hints)
                        latitude = best.latitude
                        longitude = best.longitude
                        fetchWeatherData()
                    } else {
                        errorMessage = "Location not found"; isLoading = false
                        currentTemp = "--"; condition = "Location not found"
                    }
                } catch (e) {
                    errorMessage = "Parse error"; isLoading = false
                    console.error("Geocoding parse error:", e)
                }
            } else {
                errorMessage = "Network error"; isLoading = false
            }
        }
        xhr.open("GET", url); xhr.send()
    }

    function fetchWeatherData() {
        if (latitude === 0 && longitude === 0) { geocodeLocation(); return }
        var xhr = new XMLHttpRequest()
        var url = "https://api.open-meteo.com/v1/forecast?" +
                  "latitude=" + latitude + "&longitude=" + longitude +
                  "&current=temperature_2m,weather_code" +
                  "&hourly=temperature_2m,weather_code" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code" +
                  "&temperature_unit=" + apiTempUnit +
                  "&timezone=auto&forecast_days=7"
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.current) {
                        currentTemp = Math.round(resp.current.temperature_2m).toString()
                        weatherCode = resp.current.weather_code || 0
                        condition = getWeatherCondition(weatherCode)
                    }
                    if (resp.daily) {
                        highTemp = Math.round(resp.daily.temperature_2m_max[0]).toString()
                        lowTemp = Math.round(resp.daily.temperature_2m_min[0]).toString()
                        processDailyForecast(resp.daily)
                    }
                    if (resp.hourly) processHourlyForecast(resp.hourly)
                    isLoading = false; errorMessage = ""
                } catch (e) {
                    errorMessage = "Parse error"; isLoading = false
                    console.error("Weather parse error:", e)
                }
            } else {
                errorMessage = "Network error"; isLoading = false
            }
        }
        xhr.open("GET", url); xhr.send()
    }

    onLocationChanged: {
        latitude = 0; longitude = 0
        geocodeLocation()
    }

    Timer {
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: fetchWeatherData()
    }

    Component.onCompleted: geocodeLocation()

    // ---- Card ----
    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        color: nColors.background
        radius: 20
        opacity: 0.95
        clip: true

        Loader {
            id: variantLoader
            anchors.fill: parent
            anchors.margins: root.isRectVariant ? 12 : 5
            sourceComponent: {
                switch (root.variant) {
                    case 0: return rectDailyComponent
                    case 1: return rectHourlyComponent
                    case 2: return squareCurrentComponent
                    case 3: return squareHighLowComponent
                }
                return squareCurrentComponent
            }
        }
    }

    // ====================================================================
    // Reusable wide-layout header (icon + temp + high/low + city + condition)
    // ====================================================================
    Component {
        id: wideHeader
        RowLayout {
            spacing: 14
            Layout.fillWidth: true

            Item {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64

                Image {
                    id: hdrIcon
                    anchors.fill: parent
                    source: root.weatherIconPath
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 128
                    sourceSize.height: 128
                    visible: false
                    smooth: true
                }
                MultiEffect {
                    anchors.fill: hdrIcon
                    source: hdrIcon
                    colorization: 1.0
                    colorizationColor: nColors.iconColor
                    visible: !root.isLoading && root.errorMessage === ""
                }
            }

            Text {
                text: root.currentTemp + "°"
                font.pixelSize: 36
                color: nColors.textPrimary
                opacity: root.isLoading ? 0.5 : 1.0
            }

            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter
                RowLayout {
                    spacing: 4
                    Text { text: "↑"; font.pixelSize: 14; color: nColors.textPrimary; opacity: 0.9 }
                    Text { text: root.highTemp + "°"; font.pixelSize: 14; color: nColors.textPrimary }
                }
                RowLayout {
                    spacing: 4
                    Text { text: "↓"; font.pixelSize: 14; color: nColors.textPrimary; opacity: 0.9 }
                    Text { text: root.lowTemp + "°"; font.pixelSize: 14; color: nColors.textPrimary }
                }
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                spacing: 2
                Text {
                    text: root.errorMessage !== "" ? root.errorMessage : root.location
                    font.pixelSize: 14
                    font.family: ndotFont.name
                    color: root.errorMessage !== "" ? nColors.accent : nColors.textPrimary
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignRight
                }
                Text {
                    text: root.condition
                    font.pixelSize: 13
                    font.weight: Font.Light
                    color: nColors.textPrimary
                    opacity: 0.8
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignRight
                }
            }
        }
    }

    // ====================================================================
    // Rect Page 1 — Daily forecast (6 days)
    // ====================================================================
    Component {
        id: rectDailyComponent
        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Loader { sourceComponent: wideHeader; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: nColors.divider
                    opacity: 0.5
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    Repeater {
                        model: 6
                        delegate: Item {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 1

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.dailyDays[parent.parent.index] || "---"
                                    font.pixelSize: 10
                                    font.family: ndotFont.name
                                    color: nColors.textSecondary
                                }

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22

                                    Image {
                                        id: dIcon
                                        anchors.fill: parent
                                        source: root.getWeatherIcon(root.dailyIcons[parent.parent.parent.index] || 0)
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        visible: false
                                        smooth: true
                                    }
                                    MultiEffect {
                                        anchors.fill: dIcon
                                        source: dIcon
                                        colorization: 1.0
                                        colorizationColor: nColors.iconColor
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (root.dailyHighs[parent.parent.index] || "--") + "°"
                                    font.pixelSize: 12
                                    color: nColors.textPrimary
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (root.dailyLows[parent.parent.index] || "--") + "°"
                                    font.pixelSize: 10
                                    font.weight: Font.Light
                                    color: nColors.textSecondary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ====================================================================
    // Rect Page 2 — Hourly forecast (6 hours)
    // ====================================================================
    Component {
        id: rectHourlyComponent
        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Loader { sourceComponent: wideHeader; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: nColors.divider
                    opacity: 0.5
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    Repeater {
                        model: 6
                        delegate: Item {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 1

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.hourlyTimes[parent.parent.index] || "--"
                                    font.pixelSize: 10
                                    font.family: ndotFont.name
                                    color: nColors.textSecondary
                                }

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22

                                    Image {
                                        id: hIcon
                                        anchors.fill: parent
                                        source: root.getWeatherIcon(root.hourlyIcons[parent.parent.parent.index] || 0)
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        visible: false
                                        smooth: true
                                    }
                                    MultiEffect {
                                        anchors.fill: hIcon
                                        source: hIcon
                                        colorization: 1.0
                                        colorizationColor: nColors.iconColor
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (root.hourlyTemps[parent.parent.index] || "--") + "°"
                                    font.pixelSize: 12
                                    color: nColors.textPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ====================================================================
    // Square Page 1 — Temp + icon + city
    // ====================================================================
    Component {
        id: squareCurrentComponent
        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    Layout.topMargin: 15
                    text: root.currentTemp + "°"
                    font.pixelSize: parent.width * 0.20
                    color: nColors.textPrimary
                    opacity: root.isLoading ? 0.5 : 1.0
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Image {
                        id: sqIcon
                        anchors.centerIn: parent
                        width: parent.width * 0.7
                        height: parent.height * 0.7
                        source: root.weatherIconPath
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 256
                        sourceSize.height: 256
                        visible: false
                        smooth: true
                    }
                    MultiEffect {
                        anchors.fill: sqIcon
                        source: sqIcon
                        colorization: 1.0
                        colorizationColor: nColors.iconColor
                        visible: !root.isLoading && root.errorMessage === ""
                    }
                    QQC2.BusyIndicator {
                        anchors.centerIn: parent
                        width: 48; height: 48
                        running: root.isLoading
                        visible: root.isLoading
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                    Layout.bottomMargin: 12
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.errorMessage !== "" ? root.errorMessage : root.location
                    font.pixelSize: parent.width * 0.09
                    font.family: ndotFont.name
                    color: root.errorMessage !== "" ? nColors.accent : nColors.textPrimary
                    opacity: 0.9
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    // ====================================================================
    // Square Page 2 — High/Low + condition
    // ====================================================================
    Component {
        id: squareHighLowComponent
        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Item { Layout.fillHeight: true; Layout.minimumHeight: 14 }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    Text { text: "↑"; font.pixelSize: parent.parent.width * 0.18; color: nColors.textPrimary; opacity: 0.9 }
                    Text {
                        text: root.highTemp + "°"
                        font.pixelSize: parent.parent.width * 0.18
                        color: nColors.textPrimary
                        opacity: root.isLoading ? 0.5 : 1.0
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    Text { text: "↓"; font.pixelSize: parent.parent.width * 0.18; color: nColors.textPrimary; opacity: 0.9 }
                    Text {
                        text: root.lowTemp + "°"
                        font.pixelSize: parent.parent.width * 0.18
                        color: nColors.textPrimary
                        opacity: root.isLoading ? 0.5 : 1.0
                    }
                }

                Item { Layout.minimumHeight: 4 }

                Text {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                    Layout.bottomMargin: 5
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.condition
                    font.pixelSize: parent.width * 0.09
                    font.family: ndotFont.name
                    color: nColors.textPrimary
                    opacity: 0.9
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 10 }
            }
        }
    }
}
