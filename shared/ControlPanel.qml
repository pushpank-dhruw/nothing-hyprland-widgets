import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Quickshell
import Quickshell.Wayland

// Modal control panel for adding/removing/configuring widgets.
//
// Opens as a full-screen overlay layer with a scrim + centered panel.
// Click scrim or close button to dismiss.
//
// Communicates with the world purely through `layoutModel` — clicking
// "remove" calls layoutModel.removeItem; dragging a tile calls
// layoutModel.updateItem; etc. The model emits signals back which the
// shell.qml factory translates into actual widget moves on the desktop.
PanelWindow {
    id: panel

    // ---- Public API ----
    property var layoutModel
    property string selectedId: ""

    signal closeRequested()

    // ---- Drag-from-catalog state (live during a catalog tile drag) ----
    property var dragCatalog: null     // catalog entry being dragged, or null
    property real dragLocalX: 0        // cursor position in panelBody coords
    property real dragLocalY: 0
    property bool dragOverCanvas: false

    // ---- Timezone picker state (modal popup, opened from inspector) ----
    property bool tzPopupOpen: false
    property string tzPopupTargetId: ""
    property string tzPopupTargetKey: ""
    property string tzPopupCurrentValue: ""

    function openTimezonePicker(targetId, targetKey, currentValue) {
        tzPopupTargetId = targetId
        tzPopupTargetKey = targetKey
        tzPopupCurrentValue = currentValue || ""
        tzPopupOpen = true
    }

    // ---- Window setup ----
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true

    Component.onCompleted: {
        if (panel.WlrLayershell != null) {
            panel.WlrLayershell.layer = WlrLayer.Overlay
            panel.WlrLayershell.namespace = "nothing-control"
            panel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
        }
    }

    // Stray click/release events from the launcher that opened us can land
    // on the freshly-shown panel ~1–2 s later (the press happened in another
    // surface, the release lands here). Swallow close-requests during a brief
    // grace window after the panel becomes visible.
    property bool clickGuardActive: false
    Timer {
        id: clickGuardTimer
        interval: 2000
        repeat: false
        onTriggered: panel.clickGuardActive = false
    }

    onVisibleChanged: {
        if (visible) {
            clickGuardActive = true
            clickGuardTimer.restart()
            panelBody.forceActiveFocus()
        }
    }

    // ---- Theme + fonts ----
    NothingColors { id: nColors; themeMode: 0 }
    FontLoader { id: ndotFont;   source: Qt.resolvedUrl("fonts/ndot.ttf") }
    FontLoader { id: ndot55Font; source: Qt.resolvedUrl("fonts/ndot-55.otf") }

    // ---- Widget specs: every widget type, with editable property schema ----
    // Each spec describes how the inspector should render that widget's
    // controls. `properties` is the typed editor schema for `props.*`;
    // `sizing` controls the SIZE editor (wh / square / auto).
    // `hideFromCatalog: true` keeps a type out of the addable left-rail list
    // while still letting the inspector recognise it when selected.
    readonly property var widgetSpecs: [
        { type: "clockDigital", label: "Digital Clock", glyph: "◐",
          variants: ["Digital", "World"],
          sizing: { mode: "wh", minW: 180, maxW: 800, minH: 60, maxH: 400 },
          properties: [
              { key: "use24HourFormat", label: "24-Hour Format", kind: "bool" },
              { key: "cityName", label: "City Label", kind: "string",
                placeholder: "Tokyo", showWhenVariant: 1 },
              { key: "timeZone", label: "Timezone", kind: "timezone",
                showWhenVariant: 1 }
          ],
          defaults: { posX: 100, posY: 100,
                      size: { width: 320, height: 100 },
                      props: { use24HourFormat: false, cityName: "Tokyo", timeZone: "Asia/Tokyo" } } },

        { type: "clockAnalog", label: "Analog Clock", glyph: "◉",
          variants: ["Swiss", "Minimal"],
          sizing: { mode: "square", min: 120, max: 400 },
          properties: [
              { key: "smoothHands", label: "Smooth Second Hand", kind: "bool" }
          ],
          defaults: { posX: 100, posY: 220,
                      size: { size: 220 },
                      props: { smoothHands: true } } },

        { type: "battery", label: "Battery", glyph: "▮",
          variants: ["Default"],
          sizing: { mode: "square", min: 120, max: 400 },
          properties: [
              { key: "showBluetoothDevices", label: "Bluetooth Devices", kind: "bool" }
          ],
          defaults: { posX: 100, posY: 460,
                      size: { size: 220 },
                      props: { showBluetoothDevices: true } } },

        { type: "weather", label: "Weather", glyph: "☼",
          variants: ["Daily", "Hourly", "Now", "H/L"],
          sizing: { mode: "auto", note: "Sized by variant" },
          properties: [
              { key: "location", label: "Location", kind: "string", placeholder: "London, UK" },
              { key: "temperatureUnit", label: "Unit", kind: "enum",
                choices: [{ label: "°C", value: 0 }, { label: "°F", value: 1 }] }
          ],
          defaults: { posX: 400, posY: 100,
                      props: { location: "Raipur, IN", temperatureUnit: 0 } } },

        { type: "date", label: "Date", glyph: "▢",
          variants: ["Default"],
          sizing: { mode: "wh", minW: 120, maxW: 400, minH: 120, maxH: 400 },
          properties: [],
          defaults: { posX: 600, posY: 100,
                      size: { width: 200, height: 200 } } },

        { type: "launcher", label: "Launcher", glyph: "▤",
          variants: ["Default"],
          sizing: { mode: "auto", note: "Sized to chip count" },
          hideFromCatalog: true,
          properties: [],
          defaults: { posX: 40, posY: 880 } }
    ]

    // Subset shown in the left rail (excludes launcher).
    readonly property var catalog: {
        const out = []
        for (let i = 0; i < widgetSpecs.length; i++)
            if (!widgetSpecs[i].hideFromCatalog) out.push(widgetSpecs[i])
        return out
    }

    // Timezone list, used by the inspector's timezone picker.
    TimezonesData { id: timezonesData }

    // ---- Helpers ----
    function catalogFor(type) {
        for (let i = 0; i < widgetSpecs.length; i++)
            if (widgetSpecs[i].type === type) return widgetSpecs[i]
        return null
    }

    function labelFor(type) {
        const c = catalogFor(type)
        return c ? c.label : type
    }

    function variantsFor(type) {
        const c = catalogFor(type)
        return c ? c.variants : ["Default"]
    }

    function sizingFor(type) {
        const c = catalogFor(type)
        return c ? c.sizing : { mode: "auto" }
    }

    // Filter the property schema for a given variant. Returning a *new*
    // array each call is fine — the Repeater rebuilds its delegates when
    // the binding fires anyway.
    function propertiesFor(type, variant) {
        const c = catalogFor(type)
        if (!c || !c.properties) return []
        const v = (variant === undefined ? 0 : variant)
        return c.properties.filter(function(p) {
            return p.showWhenVariant === undefined || p.showWhenVariant === v
        })
    }

    // Resolve the *effective* value of a prop: layout JSON wins, catalog
    // default fills the gap. Returns undefined when neither knows.
    function propValue(spec, key) {
        if (spec && spec.props && spec.props[key] !== undefined) return spec.props[key]
        const c = catalogFor(spec ? spec.type : "")
        if (c && c.defaults && c.defaults.props && c.defaults.props[key] !== undefined)
            return c.defaults.props[key]
        return undefined
    }

    // Resolve the effective size triple { mode, w, h, size } for a spec.
    function effectiveSize(spec) {
        const sz = sizingFor(spec.type)
        if (sz.mode === "wh") {
            const sw = (spec.size && spec.size.width  !== undefined) ? spec.size.width  : null
            const sh = (spec.size && spec.size.height !== undefined) ? spec.size.height : null
            const c = catalogFor(spec.type)
            const dw = (c && c.defaults && c.defaults.size && c.defaults.size.width  !== undefined) ? c.defaults.size.width  : 200
            const dh = (c && c.defaults && c.defaults.size && c.defaults.size.height !== undefined) ? c.defaults.size.height : 200
            return { mode: "wh", w: (sw !== null ? sw : dw), h: (sh !== null ? sh : dh) }
        }
        if (sz.mode === "square") {
            const ss = (spec.size && spec.size.size !== undefined) ? spec.size.size : null
            const c = catalogFor(spec.type)
            const ds = (c && c.defaults && c.defaults.size && c.defaults.size.size !== undefined) ? c.defaults.size.size : 220
            return { mode: "square", size: (ss !== null ? ss : ds) }
        }
        return { mode: "auto" }
    }

    function tzLabel(id) {
        if (!id || !timezonesData.timezones) return "—"
        for (let i = 0; i < timezonesData.timezones.length; i++) {
            const t = timezonesData.timezones[i]
            if (t.id === id) {
                const off = t.offset
                const sign = off >= 0 ? "+" : ""
                const offStr = (off === Math.floor(off)) ? off.toFixed(0) : off.toFixed(1)
                return t.city + " · UTC" + sign + offStr
            }
        }
        return id
    }

    function selectedItem() {
        if (!selectedId || !layoutModel) return null
        return layoutModel.findItem(selectedId)
    }

    // Resolve a widget's on-screen footprint for the minimap.
    function widgetSizeFor(spec) {
        if (spec.size) {
            if (spec.size.width !== undefined && spec.size.height !== undefined)
                return { w: spec.size.width, h: spec.size.height }
            if (spec.size.size !== undefined)
                return { w: spec.size.size, h: spec.size.size }
        }
        const c = catalogFor(spec.type)
        if (c && c.defaults && c.defaults.size) {
            const s = c.defaults.size
            if (s.width !== undefined) return { w: s.width, h: s.height }
            if (s.size !== undefined)  return { w: s.size,  h: s.size }
        }
        if (spec.type === "weather")  return { w: 480, h: 180 }
        if (spec.type === "launcher") return { w: 343, h: 54  }
        return { w: 220, h: 220 }
    }

    function addFromCatalog(c) {
        if (!layoutModel) return
        const spec = Object.assign(
            { type: c.type, variant: 0, themeMode: 0, visible: true },
            c.defaults || {}
        )
        const id = layoutModel.addItem(spec)
        if (id) selectedId = id
    }

    // Like addFromCatalog but places at a specific real-screen position.
    // posX/posY are the desired top-left in screen coords; clamped to bounds.
    function addFromCatalogAt(c, posX, posY) {
        if (!layoutModel) return
        const dims = widgetSizeFor({ type: c.type, size: c.defaults ? c.defaults.size : null })
        const clampedX = Math.max(0, Math.min(screenWidth  - dims.w, Math.round(posX)))
        const clampedY = Math.max(0, Math.min(screenHeight - dims.h, Math.round(posY)))
        const spec = Object.assign(
            { type: c.type, variant: 0, themeMode: 0, visible: true },
            c.defaults || {},
            { posX: clampedX, posY: clampedY }
        )
        const id = layoutModel.addItem(spec)
        if (id) selectedId = id
    }

    // ---- Screen geometry (single-monitor for Phase 2) ----
    readonly property real screenWidth:  Quickshell.screens.length ? Quickshell.screens[0].width  : 1920
    readonly property real screenHeight: Quickshell.screens.length ? Quickshell.screens[0].height : 1080

    // ---- Scrim ----
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.45
        MouseArea {
            anchors.fill: parent
            onClicked: if (!panel.clickGuardActive) panel.closeRequested()
        }
    }

    // ---- Panel body ----
    Rectangle {
        id: panelBody
        anchors.centerIn: parent
        width: 1140
        height: 720
        color: nColors.surface
        radius: 16
        border.color: nColors.divider
        border.width: 1
        clip: true
        focus: true

        // Eat clicks so they don't bubble to scrim
        MouseArea { anchors.fill: parent }

        Keys.onEscapePressed: panel.closeRequested()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Delete && panel.selectedId) {
                const sel = panel.selectedItem()
                if (sel) {
                    panel.layoutModel.removeItem(sel.id)
                    panel.selectedId = ""
                }
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ============ HEADER ============
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 14
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: nColors.accent
                    }
                    Text {
                        text: "NOTHING WIDGETS"
                        font.family: ndot55Font.name
                        font.pixelSize: 14
                        font.letterSpacing: 2
                        color: nColors.textPrimary
                    }
                    Item { Layout.fillWidth: true }

                    // Reload
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: reloadHover.containsMouse ? nColors.divider : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "↺"
                            font.pixelSize: 16
                            color: nColors.textSecondary
                        }
                        MouseArea {
                            id: reloadHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (panel.layoutModel) panel.layoutModel.reload()
                        }
                    }
                    // Close
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: closeHover.containsMouse ? nColors.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 14
                            color: closeHover.containsMouse ? "#fff" : nColors.textSecondary
                        }
                        MouseArea {
                            id: closeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!panel.clickGuardActive) panel.closeRequested()
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: nColors.divider }

            // ============ BODY: catalog · canvas · inspector ============
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ---- CATALOG ----
                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.fillHeight: true
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        Text {
                            text: "CATALOG"
                            font.family: ndotFont.name
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            color: nColors.textSecondary
                            opacity: 0.7
                        }

                        QQC2.ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded
                            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: panel.catalog

                                    delegate: Rectangle {
                                        id: tile
                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 64
                                        radius: 10
                                        color: tileHover.containsMouse ? nColors.background : "transparent"
                                        border.color: tileHover.containsMouse ? nColors.accent : nColors.divider
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on border.color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 12

                                            Rectangle {
                                                Layout.preferredWidth: 36
                                                Layout.preferredHeight: 36
                                                radius: 8
                                                color: "#22ff4444"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: tile.modelData.glyph
                                                    font.pixelSize: 18
                                                    color: nColors.accent
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: tile.modelData.label
                                                    font.family: ndot55Font.name
                                                    font.pixelSize: 12
                                                    font.letterSpacing: 1
                                                    color: nColors.textPrimary
                                                }
                                                Text {
                                                    text: tile.modelData.variants.length + (tile.modelData.variants.length === 1 ? " variant" : " variants")
                                                    font.family: ndotFont.name
                                                    font.pixelSize: 9
                                                    color: nColors.textSecondary
                                                    opacity: 0.7
                                                }
                                            }

                                            Text {
                                                text: "+"
                                                font.family: ndot55Font.name
                                                font.pixelSize: 22
                                                color: nColors.accent
                                                opacity: tileHover.containsMouse ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                            }
                                        }

                                        MouseArea {
                                            id: tileHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: panel.dragCatalog ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                            property real pressX: 0
                                            property real pressY: 0
                                            property bool dragStarted: false

                                            onPressed: function(mouse) {
                                                const p = mapToItem(panelBody, mouse.x, mouse.y)
                                                pressX = p.x; pressY = p.y
                                                dragStarted = false
                                            }
                                            onPositionChanged: function(mouse) {
                                                if ((pressedButtons & Qt.LeftButton) === 0) return
                                                const p = mapToItem(panelBody, mouse.x, mouse.y)
                                                if (!dragStarted
                                                    && (Math.abs(p.x - pressX) > 4 || Math.abs(p.y - pressY) > 4)) {
                                                    dragStarted = true
                                                    panel.dragCatalog = tile.modelData
                                                }
                                                if (dragStarted) {
                                                    panel.dragLocalX = p.x
                                                    panel.dragLocalY = p.y
                                                    const c = panelBody.mapToItem(screenRect, p.x, p.y)
                                                    panel.dragOverCanvas = c.x >= 0 && c.x <= screenRect.width
                                                                        && c.y >= 0 && c.y <= screenRect.height
                                                }
                                            }
                                            onReleased: function(mouse) {
                                                const p = mapToItem(panelBody, mouse.x, mouse.y)
                                                if (dragStarted) {
                                                    const c = panelBody.mapToItem(screenRect, p.x, p.y)
                                                    if (c.x >= 0 && c.x <= screenRect.width
                                                        && c.y >= 0 && c.y <= screenRect.height) {
                                                        const sf = screenRect.sf
                                                        const dims = panel.widgetSizeFor({
                                                            type: tile.modelData.type,
                                                            size: tile.modelData.defaults
                                                                ? tile.modelData.defaults.size : null
                                                        })
                                                        panel.addFromCatalogAt(
                                                            tile.modelData,
                                                            c.x / sf - dims.w / 2,
                                                            c.y / sf - dims.h / 2)
                                                    }
                                                } else {
                                                    panel.addFromCatalog(tile.modelData)
                                                }
                                                dragStarted = false
                                                panel.dragCatalog = null
                                                panel.dragOverCanvas = false
                                            }
                                            onCanceled: {
                                                dragStarted = false
                                                panel.dragCatalog = null
                                                panel.dragOverCanvas = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: nColors.divider }

                // ---- CANVAS (dotted minimap) ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        id: canvasContainer
                        anchors.fill: parent
                        anchors.margins: 24

                        Rectangle {
                            id: screenRect
                            anchors.centerIn: parent

                            // Aspect-locked, fits the available area
                            readonly property real availW: parent.width
                            readonly property real availH: parent.height
                            readonly property real sf: Math.min(availW / panel.screenWidth, availH / panel.screenHeight) * 0.96

                            width:  panel.screenWidth  * sf
                            height: panel.screenHeight * sf

                            color: nColors.background
                            border.color: panel.dragOverCanvas ? nColors.accent : nColors.divider
                            border.width: panel.dragOverCanvas ? 2 : 1
                            radius: 4
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            // Click empty canvas to deselect
                            MouseArea {
                                anchors.fill: parent
                                onClicked: panel.selectedId = ""
                            }

                            // Dot grid
                            Canvas {
                                id: dotGrid
                                anchors.fill: parent
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.fillStyle = nColors.divider
                                    const stepReal = 40
                                    const step = stepReal * screenRect.sf
                                    if (step < 4) return
                                    const r = Math.max(0.6, step * 0.04)
                                    for (let x = step; x < width; x += step) {
                                        for (let y = step; y < height; y += step) {
                                            ctx.beginPath()
                                            ctx.arc(x, y, r, 0, Math.PI * 2)
                                            ctx.fill()
                                        }
                                    }
                                }
                                Connections {
                                    target: screenRect
                                    function onSfChanged() { dotGrid.requestPaint() }
                                }
                            }

                            // Placed widget tiles
                            Repeater {
                                model: panel.layoutModel ? panel.layoutModel.items : []

                                delegate: Rectangle {
                                    id: placedTile
                                    required property var modelData

                                    readonly property bool selected: panel.selectedId === modelData.id
                                    readonly property var dims: panel.widgetSizeFor(modelData)
                                    readonly property real sf: screenRect.sf

                                    // Display position — bound to model unless mid-drag
                                    property real displayX: modelData.posX * sf
                                    property real displayY: modelData.posY * sf

                                    x: displayX
                                    y: displayY
                                    width:  dims.w * sf
                                    height: dims.h * sf

                                    color: selected ? nColors.accent : "#22ff4444"
                                    opacity: modelData.visible === false ? 0.35 : (selected ? 0.9 : 0.7)
                                    border.color: nColors.accent
                                    border.width: selected ? 1.6 : 0.8
                                    radius: 2
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.width { NumberAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: panel.labelFor(placedTile.modelData.type)
                                        font.family: ndot55Font.name
                                        font.pixelSize: 9
                                        font.letterSpacing: 1
                                        color: placedTile.selected ? "#fff" : nColors.accent
                                        visible: parent.width > 50 && parent.height > 16
                                    }

                                    MouseArea {
                                        id: dragArea
                                        anchors.fill: parent
                                        cursorShape: dragging ? Qt.SizeAllCursor : Qt.PointingHandCursor

                                        property real pressGX: 0
                                        property real pressGY: 0
                                        property real startX: 0
                                        property real startY: 0
                                        property bool dragging: false

                                        onPressed: function(mouse) {
                                            const g = mapToGlobal(mouse.x, mouse.y)
                                            pressGX = g.x; pressGY = g.y
                                            startX = placedTile.displayX
                                            startY = placedTile.displayY
                                            dragging = false
                                            panel.selectedId = placedTile.modelData.id
                                        }
                                        onPositionChanged: function(mouse) {
                                            if ((pressedButtons & Qt.LeftButton) === 0) return
                                            const g = mapToGlobal(mouse.x, mouse.y)
                                            const dx = g.x - pressGX, dy = g.y - pressGY
                                            if (!dragging && (Math.abs(dx) > 2 || Math.abs(dy) > 2)) dragging = true
                                            if (dragging) {
                                                const maxX = screenRect.width  - placedTile.width
                                                const maxY = screenRect.height - placedTile.height
                                                placedTile.displayX = Math.max(0, Math.min(maxX, startX + dx))
                                                placedTile.displayY = Math.max(0, Math.min(maxY, startY + dy))
                                            }
                                        }
                                        onReleased: function(mouse) {
                                            if (dragging) {
                                                const realX = Math.max(0, Math.round(placedTile.displayX / placedTile.sf))
                                                const realY = Math.max(0, Math.round(placedTile.displayY / placedTile.sf))
                                                panel.layoutModel.updateItem(placedTile.modelData.id, "posX", realX)
                                                panel.layoutModel.updateItem(placedTile.modelData.id, "posY", realY)
                                            }
                                            // Re-bind to model so future external updates flow through
                                            placedTile.displayX = Qt.binding(function() { return placedTile.modelData.posX * placedTile.sf })
                                            placedTile.displayY = Qt.binding(function() { return placedTile.modelData.posY * placedTile.sf })
                                            dragging = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: nColors.divider }

                // ---- INSPECTOR ----
                Rectangle {
                    Layout.preferredWidth: 270
                    Layout.fillHeight: true
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

                        Text {
                            text: "INSPECTOR"
                            font.family: ndotFont.name
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            color: nColors.textSecondary
                            opacity: 0.7
                        }

                        // ---- Empty state ----
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !panel.selectedItem()

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "·"
                                    font.pixelSize: 32
                                    color: nColors.textSecondary
                                    opacity: 0.4
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "select a widget"
                                    font.family: ndotFont.name
                                    font.pixelSize: 10
                                    color: nColors.textSecondary
                                    opacity: 0.6
                                }
                            }
                        }

                        // ---- Selected (scrollable body) ----
                        QQC2.ScrollView {
                            id: inspectorScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: panel.selectedItem() !== null
                            clip: true
                            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded
                            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                            ColumnLayout {
                                id: inspectorSel
                                width: inspectorScroll.availableWidth
                                spacing: 14

                                property var sel: panel.selectedItem()
                                property bool removeArmed: false

                                Connections {
                                    target: panel
                                    function onSelectedIdChanged() { inspectorSel.removeArmed = false }
                                }

                                // Type
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: "TYPE"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }
                                    Text {
                                        text: panel.labelFor(inspectorSel.sel ? inspectorSel.sel.type : "")
                                        font.family: ndot55Font.name; font.pixelSize: 14
                                        color: nColors.textPrimary
                                    }
                                    Text {
                                        text: inspectorSel.sel ? inspectorSel.sel.id : ""
                                        font.family: ndotFont.name; font.pixelSize: 10
                                        color: nColors.textSecondary; opacity: 0.7
                                    }
                                }

                                // Variant
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: inspectorSel.sel
                                        && panel.variantsFor(inspectorSel.sel.type).length > 1

                                    Text {
                                        text: "VARIANT"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: inspectorSel.sel
                                                ? panel.variantsFor(inspectorSel.sel.type).length : 0

                                            delegate: Rectangle {
                                                required property int index
                                                readonly property bool active:
                                                    inspectorSel.sel && inspectorSel.sel.variant === index

                                                width: 28; height: 24
                                                radius: 6
                                                color: active ? nColors.accent : "transparent"
                                                border.color: active ? nColors.accent : nColors.divider
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: index
                                                    font.family: ndot55Font.name; font.pixelSize: 11
                                                    color: active ? "#000" : nColors.textPrimary
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (inspectorSel.sel)
                                                        panel.layoutModel.updateItem(inspectorSel.sel.id, "variant", index)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Theme
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "THEME"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }
                                    Row {
                                        spacing: 6
                                        Repeater {
                                            model: ["DARK", "LIGHT"]
                                            delegate: Rectangle {
                                                required property int index
                                                required property string modelData
                                                readonly property bool active:
                                                    inspectorSel.sel && inspectorSel.sel.themeMode === index

                                                width: themeLbl.implicitWidth + 18
                                                height: 24
                                                radius: 12
                                                color: active ? nColors.accent : "transparent"
                                                border.color: active ? nColors.accent : nColors.divider
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    id: themeLbl
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    font.family: ndotFont.name
                                                    font.pixelSize: 9
                                                    font.letterSpacing: 1.5
                                                    color: active ? "#000" : nColors.textPrimary
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (inspectorSel.sel)
                                                        panel.layoutModel.updateItem(inspectorSel.sel.id, "themeMode", index)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Visibility
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "VISIBILITY"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 28
                                        radius: 14
                                        readonly property bool on:
                                            inspectorSel.sel && inspectorSel.sel.visible !== false
                                        color: on ? nColors.accent : "transparent"
                                        border.color: on ? nColors.accent : nColors.divider
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.on ? "SHOWN" : "HIDDEN"
                                            font.family: ndotFont.name
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: parent.on ? "#000" : nColors.textPrimary
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (inspectorSel.sel)
                                                panel.layoutModel.updateItem(
                                                    inspectorSel.sel.id, "visible",
                                                    !(inspectorSel.sel.visible !== false))
                                        }
                                    }
                                }

                                // ---- PROPERTIES (typed editor, per-widget schema) ----
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    visible: inspectorSel.sel
                                        && panel.propertiesFor(inspectorSel.sel.type,
                                                               inspectorSel.sel.variant).length > 0

                                    Text {
                                        text: "PROPERTIES"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }

                                    Repeater {
                                        // Per-property delegate dispatches on `kind` via Loader.
                                        // The delegate exposes `prop` and `sel` for the loaded
                                        // component to bind to (parent.prop / parent.sel).
                                        model: inspectorSel.sel
                                            ? panel.propertiesFor(inspectorSel.sel.type,
                                                                  inspectorSel.sel.variant)
                                            : []

                                        delegate: Loader {
                                            required property var modelData
                                            Layout.fillWidth: true

                                            property var prop: modelData
                                            property var sel: inspectorSel.sel

                                            sourceComponent: {
                                                switch (modelData.kind) {
                                                case "bool":     return boolFieldComp
                                                case "string":   return stringFieldComp
                                                case "enum":     return enumFieldComp
                                                case "timezone": return tzFieldComp
                                                }
                                                return null
                                            }
                                        }
                                    }
                                }

                                // ---- SIZE editor (wh / square / auto) ----
                                ColumnLayout {
                                    id: sizeBlock
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: inspectorSel.sel !== null

                                    readonly property var sizing: inspectorSel.sel
                                        ? panel.sizingFor(inspectorSel.sel.type) : ({ mode: "auto" })
                                    readonly property var sizeNow: inspectorSel.sel
                                        ? panel.effectiveSize(inspectorSel.sel) : ({ mode: "auto" })

                                    Text {
                                        text: "SIZE"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }

                                    // Auto mode — display only
                                    Text {
                                        Layout.fillWidth: true
                                        visible: sizeBlock.sizing.mode === "auto"
                                        text: sizeBlock.sizing.note || "Auto"
                                        font.family: ndotFont.name; font.pixelSize: 11
                                        color: nColors.textSecondary; opacity: 0.7
                                    }

                                    // wh mode — W and H side-by-side
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        visible: sizeBlock.sizing.mode === "wh"

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: "W"
                                                font.family: ndotFont.name; font.pixelSize: 9
                                                color: nColors.textSecondary; opacity: 0.55
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: wInput.activeFocus ? nColors.background : "transparent"
                                                border.color: wInput.activeFocus ? nColors.accent : nColors.divider
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                                TextInput {
                                                    id: wInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    selectByMouse: true
                                                    inputMethodHints: Qt.ImhDigitsOnly
                                                    validator: IntValidator { bottom: 0; top: 9999 }
                                                    font.family: ndot55Font.name; font.pixelSize: 12
                                                    color: nColors.textPrimary
                                                    text: sizeBlock.sizeNow.w !== undefined
                                                        ? String(sizeBlock.sizeNow.w) : ""
                                                    onEditingFinished: {
                                                        if (!inspectorSel.sel) return
                                                        const sz = sizeBlock.sizing
                                                        const minV = sz.minW !== undefined ? sz.minW : 1
                                                        const maxV = sz.maxW !== undefined ? sz.maxW : 9999
                                                        const v = Math.max(minV, Math.min(maxV, parseInt(text) || minV))
                                                        panel.layoutModel.updateItem(
                                                            inspectorSel.sel.id, "size.width", v)
                                                        text = Qt.binding(function() {
                                                            return sizeBlock.sizeNow.w !== undefined
                                                                ? String(sizeBlock.sizeNow.w) : ""
                                                        })
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: "H"
                                                font.family: ndotFont.name; font.pixelSize: 9
                                                color: nColors.textSecondary; opacity: 0.55
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: hInput.activeFocus ? nColors.background : "transparent"
                                                border.color: hInput.activeFocus ? nColors.accent : nColors.divider
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                                TextInput {
                                                    id: hInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    selectByMouse: true
                                                    inputMethodHints: Qt.ImhDigitsOnly
                                                    validator: IntValidator { bottom: 0; top: 9999 }
                                                    font.family: ndot55Font.name; font.pixelSize: 12
                                                    color: nColors.textPrimary
                                                    text: sizeBlock.sizeNow.h !== undefined
                                                        ? String(sizeBlock.sizeNow.h) : ""
                                                    onEditingFinished: {
                                                        if (!inspectorSel.sel) return
                                                        const sz = sizeBlock.sizing
                                                        const minV = sz.minH !== undefined ? sz.minH : 1
                                                        const maxV = sz.maxH !== undefined ? sz.maxH : 9999
                                                        const v = Math.max(minV, Math.min(maxV, parseInt(text) || minV))
                                                        panel.layoutModel.updateItem(
                                                            inspectorSel.sel.id, "size.height", v)
                                                        text = Qt.binding(function() {
                                                            return sizeBlock.sizeNow.h !== undefined
                                                                ? String(sizeBlock.sizeNow.h) : ""
                                                        })
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // square mode — single dimension
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        visible: sizeBlock.sizing.mode === "square"

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: sInput.activeFocus ? nColors.background : "transparent"
                                                border.color: sInput.activeFocus ? nColors.accent : nColors.divider
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                                TextInput {
                                                    id: sInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    selectByMouse: true
                                                    inputMethodHints: Qt.ImhDigitsOnly
                                                    validator: IntValidator { bottom: 0; top: 9999 }
                                                    font.family: ndot55Font.name; font.pixelSize: 12
                                                    color: nColors.textPrimary
                                                    text: sizeBlock.sizeNow.size !== undefined
                                                        ? String(sizeBlock.sizeNow.size) : ""
                                                    onEditingFinished: {
                                                        if (!inspectorSel.sel) return
                                                        const sz = sizeBlock.sizing
                                                        const minV = sz.min !== undefined ? sz.min : 1
                                                        const maxV = sz.max !== undefined ? sz.max : 9999
                                                        const v = Math.max(minV, Math.min(maxV, parseInt(text) || minV))
                                                        panel.layoutModel.updateItem(
                                                            inspectorSel.sel.id, "size.size", v)
                                                        text = Qt.binding(function() {
                                                            return sizeBlock.sizeNow.size !== undefined
                                                                ? String(sizeBlock.sizeNow.size) : ""
                                                        })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Position
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        text: "POSITION"
                                        font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                                        color: nColors.textSecondary; opacity: 0.6
                                    }
                                    Row {
                                        spacing: 16
                                        Text {
                                            text: "X " + (inspectorSel.sel ? inspectorSel.sel.posX : "—")
                                            font.family: ndotFont.name; font.pixelSize: 11
                                            color: nColors.textPrimary
                                        }
                                        Text {
                                            text: "Y " + (inspectorSel.sel ? inspectorSel.sel.posY : "—")
                                            font.family: ndotFont.name; font.pixelSize: 11
                                            color: nColors.textPrimary
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Remove (pinned to bottom of inspector) ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            visible: panel.selectedItem() !== null
                            radius: 8
                            color: inspectorSel.removeArmed ? nColors.error : "transparent"
                            border.color: inspectorSel.removeArmed ? nColors.error : nColors.divider
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: inspectorSel.removeArmed ? "TAP AGAIN" : "REMOVE"
                                font.family: ndot55Font.name
                                font.pixelSize: 11
                                font.letterSpacing: 2
                                color: inspectorSel.removeArmed ? "#fff" : nColors.textPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (inspectorSel.removeArmed) {
                                        if (inspectorSel.sel)
                                            panel.layoutModel.removeItem(inspectorSel.sel.id)
                                        panel.selectedId = ""
                                        inspectorSel.removeArmed = false
                                    } else {
                                        inspectorSel.removeArmed = true
                                        disarmTimer.restart()
                                    }
                                }
                            }

                            Timer {
                                id: disarmTimer
                                interval: 1800
                                onTriggered: inspectorSel.removeArmed = false
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: nColors.divider }

            // ============ FOOTER ============
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22

                    Text {
                        text: panel.layoutModel
                            ? panel.layoutModel.items.length + " widgets · auto-saved"
                            : "loading…"
                        font.family: ndotFont.name
                        font.pixelSize: 10
                        color: nColors.textSecondary
                        opacity: 0.7
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Math.round(panel.screenWidth) + " × " + Math.round(panel.screenHeight)
                        font.family: ndotFont.name
                        font.pixelSize: 10
                        color: nColors.textSecondary
                        opacity: 0.5
                    }
                }
            }
        }

        // ============================================================
        // Inspector field templates — instantiated by the PROPERTIES
        // Repeater via Loader. Each delegate exposes `prop` (schema)
        // and `sel` (selected layout item) on the Loader; the loaded
        // root pulls them through `parent.prop` / `parent.sel`.
        // ============================================================

        // bool — ON / OFF pill
        Component {
            id: boolFieldComp
            ColumnLayout {
                spacing: 4
                readonly property var prop: parent ? parent.prop : null
                readonly property var sel:  parent ? parent.sel  : null
                readonly property bool current: sel && prop
                    ? (panel.propValue(sel, prop.key) === true) : false

                Text {
                    text: prop ? prop.label.toUpperCase() : ""
                    font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                    color: nColors.textSecondary; opacity: 0.6
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 14
                    color: parent.current ? nColors.accent : "transparent"
                    border.color: parent.current ? nColors.accent : nColors.divider
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: parent.parent.current ? "ON" : "OFF"
                        font.family: ndotFont.name
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        color: parent.parent.current ? "#000" : nColors.textPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const root = parent.parent
                            if (root.sel && root.prop)
                                panel.layoutModel.updateItem(
                                    root.sel.id, "props." + root.prop.key, !root.current)
                        }
                    }
                }
            }
        }

        // string — single-line text input. Commit on focus loss / Enter,
        // then re-bind to the model so external updates flow back in.
        Component {
            id: stringFieldComp
            ColumnLayout {
                id: stringRoot
                spacing: 4
                readonly property var prop: parent ? parent.prop : null
                readonly property var sel:  parent ? parent.sel  : null

                Text {
                    text: stringRoot.prop ? stringRoot.prop.label.toUpperCase() : ""
                    font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                    color: nColors.textSecondary; opacity: 0.6
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: stringInput.activeFocus ? nColors.background : "transparent"
                    border.color: stringInput.activeFocus ? nColors.accent : nColors.divider
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    TextInput {
                        id: stringInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        font.family: ndot55Font.name; font.pixelSize: 12
                        color: nColors.textPrimary
                        text: stringRoot.sel && stringRoot.prop
                            ? (panel.propValue(stringRoot.sel, stringRoot.prop.key) || "") : ""

                        onEditingFinished: {
                            if (!stringRoot.sel || !stringRoot.prop) return
                            const cur = panel.propValue(stringRoot.sel, stringRoot.prop.key) || ""
                            if (text !== cur) {
                                panel.layoutModel.updateItem(
                                    stringRoot.sel.id, "props." + stringRoot.prop.key, text)
                            }
                            text = Qt.binding(function() {
                                return stringRoot.sel && stringRoot.prop
                                    ? (panel.propValue(stringRoot.sel, stringRoot.prop.key) || "") : ""
                            })
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: stringRoot.prop && stringRoot.prop.placeholder
                                ? stringRoot.prop.placeholder : ""
                            visible: !stringInput.text && !stringInput.activeFocus
                            font: stringInput.font
                            color: nColors.textPlaceholder
                            opacity: 0.6
                        }
                    }
                }
            }
        }

        // enum — chip row, like THEME but with custom labels per choice
        Component {
            id: enumFieldComp
            ColumnLayout {
                id: enumRoot
                spacing: 6
                readonly property var prop: parent ? parent.prop : null
                readonly property var sel:  parent ? parent.sel  : null

                Text {
                    text: enumRoot.prop ? enumRoot.prop.label.toUpperCase() : ""
                    font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                    color: nColors.textSecondary; opacity: 0.6
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: enumRoot.prop ? enumRoot.prop.choices : []
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: enumRoot.sel && enumRoot.prop
                                && panel.propValue(enumRoot.sel, enumRoot.prop.key) === modelData.value

                            width: enumLbl.implicitWidth + 18
                            height: 24
                            radius: 12
                            color: active ? nColors.accent : "transparent"
                            border.color: active ? nColors.accent : nColors.divider
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: enumLbl
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                font.family: ndotFont.name
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                color: parent.active ? "#000" : nColors.textPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (enumRoot.sel && enumRoot.prop)
                                        panel.layoutModel.updateItem(
                                            enumRoot.sel.id,
                                            "props." + enumRoot.prop.key,
                                            parent.modelData.value)
                                }
                            }
                        }
                    }
                }
            }
        }

        // timezone — clickable pill that opens the modal picker
        Component {
            id: tzFieldComp
            ColumnLayout {
                id: tzRoot
                spacing: 4
                readonly property var prop: parent ? parent.prop : null
                readonly property var sel:  parent ? parent.sel  : null
                readonly property string currentId: tzRoot.sel && tzRoot.prop
                    ? (panel.propValue(tzRoot.sel, tzRoot.prop.key) || "") : ""

                Text {
                    text: tzRoot.prop ? tzRoot.prop.label.toUpperCase() : ""
                    font.family: ndotFont.name; font.pixelSize: 9; font.letterSpacing: 1.5
                    color: nColors.textSecondary; opacity: 0.6
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: tzHover.containsMouse ? nColors.background : "transparent"
                    border.color: tzHover.containsMouse ? nColors.accent : nColors.divider
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: panel.tzLabel(tzRoot.currentId)
                            font.family: ndot55Font.name; font.pixelSize: 11
                            color: nColors.textPrimary
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "▾"
                            font.pixelSize: 11
                            color: nColors.textSecondary
                        }
                    }
                    MouseArea {
                        id: tzHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tzRoot.sel && tzRoot.prop)
                                panel.openTimezonePicker(
                                    tzRoot.sel.id, tzRoot.prop.key, tzRoot.currentId)
                        }
                    }
                }
            }
        }

        // ============================================================
        // Timezone picker modal — centred over panelBody, dims everything
        // beneath. Search filters the list as you type.
        // ============================================================
        MouseArea {
            // Outside-click catcher — sits below the popup, blocks clicks
            // to the inspector / canvas while the picker is open.
            visible: panel.tzPopupOpen
            anchors.fill: parent
            z: 1499
            onClicked: panel.tzPopupOpen = false
        }

        Rectangle {
            id: tzPopup
            visible: panel.tzPopupOpen
            width: 360
            height: 460
            x: (panelBody.width  - width)  / 2
            y: (panelBody.height - height) / 2
            color: nColors.surface
            border.color: nColors.divider
            border.width: 1
            radius: 12
            z: 1500
            focus: visible

            property string searchText: ""

            onVisibleChanged: {
                if (visible) {
                    searchText = ""
                    tzSearchInput.text = ""
                    tzSearchInput.forceActiveFocus()
                }
            }

            Keys.onEscapePressed: panel.tzPopupOpen = false

            // Filtered list. Returns full list when search is empty.
            function filtered() {
                const list = timezonesData.timezones || []
                const q = (searchText || "").toLowerCase().trim()
                if (!q) return list
                return list.filter(function(tz) {
                    const city = (tz.city    || "").toLowerCase()
                    const cc   = (tz.country || "").toLowerCase()
                    const id   = (tz.id      || "").toLowerCase()
                    return city.indexOf(q) !== -1 || cc.indexOf(q) !== -1 || id.indexOf(q) !== -1
                })
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "SELECT TIMEZONE"
                        font.family: ndot55Font.name
                        font.pixelSize: 11
                        font.letterSpacing: 2
                        color: nColors.textPrimary
                    }
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: tzCloseHover.containsMouse ? nColors.divider : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 12
                            color: nColors.textSecondary
                        }
                        MouseArea {
                            id: tzCloseHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.tzPopupOpen = false
                        }
                    }
                }

                // Search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: tzSearchInput.activeFocus ? nColors.background : "transparent"
                    border.color: tzSearchInput.activeFocus ? nColors.accent : nColors.divider
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    TextInput {
                        id: tzSearchInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        font.family: ndot55Font.name
                        font.pixelSize: 12
                        color: nColors.textPrimary
                        onTextChanged: tzPopup.searchText = text
                        Keys.onEscapePressed: panel.tzPopupOpen = false

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search city or country…"
                            visible: !tzSearchInput.text && !tzSearchInput.activeFocus
                            font: tzSearchInput.font
                            color: nColors.textPlaceholder
                            opacity: 0.6
                        }
                    }
                }

                // List
                ListView {
                    id: tzList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: tzPopup.filtered()

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property var modelData
                        width: tzList.width
                        height: 34
                        radius: 6
                        readonly property bool isCurrent: modelData
                            && modelData.id === panel.tzPopupCurrentValue
                        color: tzRowMa.containsMouse
                            ? nColors.background
                            : (isCurrent ? "#22ff4444" : "transparent")
                        Behavior on color { ColorAnimation { duration: 80 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.modelData
                                    ? (parent.parent.modelData.city + ", "
                                       + (parent.parent.modelData.country || ""))
                                    : ""
                                font.family: ndot55Font.name
                                font.pixelSize: 11
                                color: nColors.textPrimary
                                elide: Text.ElideRight
                            }
                            Text {
                                text: {
                                    const m = parent.parent.modelData
                                    if (!m) return ""
                                    const o = m.offset
                                    const s = o >= 0 ? "+" : ""
                                    const v = (o === Math.floor(o)) ? o.toFixed(0) : o.toFixed(1)
                                    return "UTC" + s + v
                                }
                                font.family: ndotFont.name
                                font.pixelSize: 10
                                color: nColors.textSecondary
                                opacity: 0.8
                            }
                        }

                        MouseArea {
                            id: tzRowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const m = parent.modelData
                                if (m && panel.tzPopupTargetId) {
                                    panel.layoutModel.updateItem(
                                        panel.tzPopupTargetId,
                                        "props." + panel.tzPopupTargetKey,
                                        m.id)
                                }
                                panel.tzPopupOpen = false
                            }
                        }
                    }
                }
            }
        }

        // ---- Drag preview (catalog → canvas) ----
        // Lives at panelBody root with z above all content so it's drawn
        // on top of catalog/canvas/inspector while a drag is in progress.
        Rectangle {
            id: dragPreview
            visible: panel.dragCatalog !== null

            readonly property var c: panel.dragCatalog
            readonly property var dims: c
                ? panel.widgetSizeFor({ type: c.type, size: c.defaults ? c.defaults.size : null })
                : { w: 200, h: 200 }
            readonly property real sf: screenRect.sf

            width:  dims.w * sf
            height: dims.h * sf
            x: panel.dragLocalX - width  / 2
            y: panel.dragLocalY - height / 2

            color: panel.dragOverCanvas ? nColors.accent : "#33ff4444"
            opacity: 0.9
            border.color: nColors.accent
            border.width: 1.5
            radius: 2
            z: 1000
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: dragPreview.c ? dragPreview.c.label : ""
                font.family: ndot55Font.name
                font.pixelSize: 9
                font.letterSpacing: 1
                color: "#fff"
                visible: parent.width > 50 && parent.height > 16
            }
        }
    }

}
