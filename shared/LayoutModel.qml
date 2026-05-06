import QtQuick
import QtQml
import Qt.labs.platform as LabsPlatform
import Quickshell
import Quickshell.Io

// Single source of truth for which widgets exist on screen, where they
// are, and how they're configured. Persists to JSON and reacts to both
// in-process mutations (drag, IPC) and external edits.
//
// Schema (~/.config/nothing-widgets/layout.json):
//   {
//     "version": 1,
//     "items": [
//       { "id": "...", "type": "...", "variant": 0, "themeMode": 0,
//         "posX": 40, "posY": 40, "visible": true,
//         "size": { "size": 220 }            // OR { "width": ..., "height": ... }
//         "props": { ...widget-specific... } }
//     ]
//   }
QtObject {
    id: model

    // ---- Public state ----
    property var items: []
    property bool ready: false
    readonly property string configDir: {
        const url = LabsPlatform.StandardPaths.writableLocation(LabsPlatform.StandardPaths.GenericConfigLocation).toString()
        // QUrl.toString() yields "file:///home/.../" — strip the scheme.
        const path = url.startsWith("file://") ? url.slice(7) : url
        return path.replace(/\/+$/, "") + "/nothing-widgets"
    }
    readonly property string filePath: configDir + "/layout.json"

    signal itemAdded(var spec)
    signal itemRemoved(string id)
    signal itemUpdated(string id, string key, var value)
    signal layoutReloaded()

    // ---- Default seed used when layout.json is missing/empty ----
    readonly property var defaultLayout: [
        { id: "clockDigital1", type: "clockDigital",
          variant: 0, themeMode: 0, posX: 40, posY: 40, visible: true,
          size: { width: 320, height: 100 },
          props: { use24HourFormat: false, cityName: "Gariyaband", timeZone: "India" } },
        { id: "clockAnalog1", type: "clockAnalog",
          variant: 0, themeMode: 0, posX: 40, posY: 160, visible: true,
          size: { size: 220 },
          props: { smoothHands: true } },
        { id: "battery1", type: "battery",
          variant: 0, themeMode: 0, posX: 400, posY: 40, visible: true,
          size: { size: 220 },
          props: { showBluetoothDevices: true } },
        { id: "weather1", type: "weather",
          variant: 0, themeMode: 0, posX: 280, posY: 280, visible: true,
          props: { location: "Raipur, IN", temperatureUnit: 0 } },
        { id: "date1", type: "date",
          variant: 0, themeMode: 0, posX: 680, posY: 40, visible: true,
          size: { width: 200, height: 200 } },
        { id: "launcher1", type: "launcher",
          variant: 0, themeMode: 0, posX: 40, posY: 880, visible: true }
    ]

    // ---- File reader + watcher ----
    property FileView _fileView: FileView {
        id: fileView
        path: model.filePath
        blockLoading: false
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: model._onFileLoaded()
        onLoadFailed: function(err) { model._onLoadFailed(err) }
        onFileChanged: fileView.reload()
    }

    // ---- Debounced save: coalesces drag spam into one write ----
    property Timer _saveDebounce: Timer {
        id: saveDebounce
        interval: 250
        repeat: false
        onTriggered: model._writeFile()
    }

    // ---- Atomic write via subprocess (mkdir -p + temp file + mv) ----
    property Process _writeProc: Process {
        id: writeProc
        stdinEnabled: false
    }

    // ---- Internals ----
    function _onFileLoaded() {
        const text = fileView.text()
        if (!text || !text.trim()) { _seedDefault(); return }
        let data
        try { data = JSON.parse(text) }
        catch (e) { console.warn("LayoutModel: parse error,", e); _seedDefault(); return }
        const arr = (data && Array.isArray(data.items)) ? data.items : []
        // Skip if disk content matches in-memory (avoids redundant rebuild after our own write)
        if (JSON.stringify(items) === JSON.stringify(arr)) { ready = true; return }
        items = arr
        ready = true
        layoutReloaded()
    }

    function _onLoadFailed(err) {
        // FileNotFound on first run — seed with defaults
        _seedDefault()
    }

    function _seedDefault() {
        items = JSON.parse(JSON.stringify(defaultLayout))
        ready = true
        layoutReloaded()
        _scheduleSave()
    }

    function _scheduleSave() { saveDebounce.restart() }

    function _writeFile() {
        if (!filePath) return
        const json = JSON.stringify({ version: 1, items: items }, null, 2)
        const tmp = filePath + ".tmp"
        const cmd = "mkdir -p " + _shellQuote(configDir)
            + " && cat > " + _shellQuote(tmp)
            + " && mv " + _shellQuote(tmp) + " " + _shellQuote(filePath)
        writeProc.command = ["sh", "-c", cmd]
        writeProc.stdinEnabled = true
        writeProc.running = true
        writeProc.write(json)
        writeProc.stdinEnabled = false   // closes stdin → cat exits → mv runs
    }

    function _shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // ---- Public API ----
    function findItem(id) {
        for (let i = 0; i < items.length; i++)
            if (items[i].id === id) return items[i]
        return null
    }

    function findIndex(id) {
        for (let i = 0; i < items.length; i++)
            if (items[i].id === id) return i
        return -1
    }

    function addItem(spec) {
        const copy = JSON.parse(JSON.stringify(spec))
        if (!copy.id) copy.id = generateId(copy.type)
        if (findItem(copy.id)) {
            console.warn("LayoutModel: id already exists:", copy.id)
            return null
        }
        items = items.concat([copy])
        itemAdded(copy)
        _scheduleSave()
        return copy.id
    }

    function removeItem(id) {
        const idx = findIndex(id)
        if (idx === -1) return false
        const copy = items.slice()
        copy.splice(idx, 1)
        items = copy
        itemRemoved(id)
        _scheduleSave()
        return true
    }

    function updateItem(id, key, value) {
        const idx = findIndex(id)
        if (idx === -1) return false
        const copy = items.slice()
        const item = Object.assign({}, copy[idx])
        if (key.indexOf(".") !== -1) {
            const parts = key.split(".")
            const top = parts[0]
            const sub = parts.slice(1).join(".")
            const subObj = Object.assign({}, item[top] || {})
            if (subObj[sub] === value) return false
            subObj[sub] = value
            item[top] = subObj
        } else {
            if (item[key] === value) return false
            item[key] = value
        }
        copy[idx] = item
        items = copy
        itemUpdated(id, key, value)
        _scheduleSave()
        return true
    }

    function generateId(type) {
        let n = 1
        while (findItem(type + n)) n++
        return type + n
    }

    function reload() { fileView.reload() }
}
