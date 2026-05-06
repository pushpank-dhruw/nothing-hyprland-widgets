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

    onVisibleChanged: if (visible) panelBody.forceActiveFocus()

    // ---- Theme + fonts ----
    NothingColors { id: nColors; themeMode: 0 }
    FontLoader { id: ndotFont;   source: Qt.resolvedUrl("fonts/ndot.ttf") }
    FontLoader { id: ndot55Font; source: Qt.resolvedUrl("fonts/ndot-55.otf") }

    // ---- Catalog: every widget type the panel can add ----
    readonly property var catalog: [
        { type: "clockDigital", label: "Digital Clock", glyph: "◐",
          variants: ["Digital", "World"],
          defaults: { posX: 100, posY: 100,
                      size: { width: 320, height: 100 },
                      props: { use24HourFormat: false, cityName: "Tokyo", timeZone: "Asia/Tokyo" } } },
        { type: "clockAnalog", label: "Analog Clock", glyph: "◉",
          variants: ["Swiss", "Minimal"],
          defaults: { posX: 100, posY: 220,
                      size: { size: 220 },
                      props: { smoothHands: true } } },
        { type: "battery", label: "Battery", glyph: "▮",
          variants: ["Default"],
          defaults: { posX: 100, posY: 460,
                      size: { size: 220 },
                      props: { showBluetoothDevices: true } } },
        { type: "weather", label: "Weather", glyph: "☼",
          variants: ["Daily", "Hourly", "Now", "H/L"],
          defaults: { posX: 400, posY: 100,
                      props: { location: "Raipur, IN", temperatureUnit: 0 } } },
        { type: "date", label: "Date", glyph: "▢",
          variants: ["Default"],
          defaults: { posX: 600, posY: 100,
                      size: { width: 200, height: 200 } } }
    ]

    // ---- Helpers ----
    function catalogFor(type) {
        for (let i = 0; i < catalog.length; i++)
            if (catalog[i].type === type) return catalog[i]
        return null
    }

    function labelFor(type) {
        const c = catalogFor(type)
        if (c) return c.label
        if (type === "launcher") return "Launcher Dock"
        return type
    }

    function variantsFor(type) {
        const c = catalogFor(type)
        return c ? c.variants : ["Default"]
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
            onClicked: panel.closeRequested()
        }
    }

    // ---- Panel body ----
    Rectangle {
        id: panelBody
        anchors.centerIn: parent
        width: 1100
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
                            onClicked: panel.closeRequested()
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
                    Layout.preferredWidth: 240
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

                        // ---- Selected ----
                        ColumnLayout {
                            id: inspectorSel
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 14
                            visible: panel.selectedItem() !== null

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

                            Item { Layout.fillHeight: true }

                            // Remove (two-step)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
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
