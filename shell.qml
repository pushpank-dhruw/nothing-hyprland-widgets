import QtQuick
import Quickshell
import Quickshell.Io
import "shared"
import "widgets/clockDigital" as ClockDigital
import "widgets/clockAnalog" as ClockAnalog
import "widgets/battery" as Battery
import "widgets/weather" as Weather
import "widgets/date" as DateWidget
import "widgets/launcher" as Launcher

ShellRoot {
    id: shellRoot

    // ============================================================
    // The active layout lives in ~/.config/nothing-widgets/layout.json
    // and is the single source of truth — drag a widget, cycle a
    // variant, or send an IPC call: all of it persists. Editing the
    // file by hand also reloads (watched).
    //
    // To mutate from a terminal:
    //   qs ipc call nothing list
    //   qs ipc call nothing toggle clockDigital1
    //   qs ipc call nothing setVisible clockDigital1 false
    //   qs ipc call nothing add weather '{"posX":600,"posY":40}'
    //   qs ipc call nothing remove weather2
    //   qs ipc call nothing update clockDigital1 themeMode 1
    //   qs ipc call nothing update weather1 props.location '"Tokyo, JP"'
    //
    // First run: the file doesn't exist yet, so the model seeds itself
    // with one of every widget at sensible positions.
    // ============================================================

    LayoutModel { id: layoutModel }

    // ---- Components for dynamic instantiation ----
    Component { id: clockDigitalComp; ClockDigital.ClockDigitalWindow {} }
    Component { id: clockAnalogComp;  ClockAnalog.ClockAnalogWindow  {} }
    Component { id: batteryComp;      Battery.BatteryWindow          {} }
    Component { id: weatherComp;      Weather.WeatherWindow          {} }
    Component { id: dateComp;         DateWidget.DateWindow          {} }
    Component { id: launcherComp;     Launcher.LauncherWindow        {} }

    // Live instances keyed by id. Stored on the QtObject so QML's GC
    // doesn't collect the windows.
    QtObject {
        id: factory
        property var instances: ({})

        function componentFor(type) {
            switch (type) {
            case "clockDigital": return clockDigitalComp
            case "clockAnalog":  return clockAnalogComp
            case "battery":      return batteryComp
            case "weather":      return weatherComp
            case "date":         return dateComp
            case "launcher":     return launcherComp
            }
            return null
        }

        function shortLabel(type) {
            const map = {
                "clockDigital": "Clock", "clockAnalog": "Analog",
                "battery": "Bat", "weather": "Wthr",
                "date": "Date", "launcher": "Dock"
            }
            return map[type] || type
        }

        function applySpec(inst, spec) {
            if (spec.posX !== undefined && "posX" in inst) inst.posX = spec.posX
            if (spec.posY !== undefined && "posY" in inst) inst.posY = spec.posY
            if (spec.variant !== undefined && "variant" in inst) inst.variant = spec.variant
            if (spec.themeMode !== undefined && "themeMode" in inst) inst.themeMode = spec.themeMode
            if ("visible" in inst) inst.visible = spec.visible !== false
            if (spec.size) {
                if ("size" in spec.size && "widgetSize" in inst) inst.widgetSize = spec.size.size
                if ("width" in spec.size && "widgetWidth" in inst) inst.widgetWidth = spec.size.width
                if ("height" in spec.size && "widgetHeight" in inst) inst.widgetHeight = spec.size.height
            }
            if (spec.props) {
                for (const key in spec.props) {
                    if (key in inst) inst[key] = spec.props[key]
                }
            }
        }

        function createOne(spec) {
            const comp = componentFor(spec.type)
            if (!comp) { console.warn("Unknown widget type:", spec.type); return }
            const inst = comp.createObject(shellRoot)
            if (!inst) { console.warn("Failed to create:", spec.type); return }
            applySpec(inst, spec)

            const id = spec.id

            // Writebacks fire on the *discrete* user actions, not on every
            // posXChanged tick — otherwise the Behavior animation feeds its
            // intermediate values back through the model and hijacks itself.
            inst.dragged.connect(function() {
                if (!factory.instances[id]) return
                layoutModel.updateItem(id, "posX", inst.posX)
                layoutModel.updateItem(id, "posY", inst.posY)
            })
            inst.variantCycled.connect(function() {
                if (!factory.instances[id]) return
                layoutModel.updateItem(id, "variant", inst.variant)
            })
            // Visibility has no Behavior animation — safe to track on change.
            inst.visibleChanged.connect(function() {
                if (factory.instances[id]) layoutModel.updateItem(id, "visible", inst.visible)
            })

            factory.instances[id] = inst
            if (spec.type === "launcher") refreshLauncher(inst)
        }

        function destroyOne(id) {
            const inst = factory.instances[id]
            if (inst) {
                inst.destroy()
                delete factory.instances[id]
                refreshAllLaunchers()
            }
        }

        function applyUpdate(id, key, value) {
            const inst = factory.instances[id]
            if (!inst) return
            if (key.indexOf(".") !== -1) {
                const parts = key.split(".")
                const top = parts[0]
                const sub = parts.slice(1).join(".")
                if (top === "size") {
                    if (sub === "size" && "widgetSize" in inst) inst.widgetSize = value
                    else if (sub === "width" && "widgetWidth" in inst) inst.widgetWidth = value
                    else if (sub === "height" && "widgetHeight" in inst) inst.widgetHeight = value
                } else if (top === "props" && sub in inst) {
                    inst[sub] = value
                }
            } else if (key in inst) {
                inst[key] = value
            }
        }

        function rebuild() {
            for (const id in instances) instances[id].destroy()
            instances = {}
            for (const spec of layoutModel.items) createOne(spec)
        }

        // Launcher: bind its `items` chip list to whatever else is in the model.
        function refreshLauncher(inst) {
            const out = []
            for (const s of layoutModel.items) {
                if (s.type === "launcher") continue
                const target = factory.instances[s.id]
                if (!target) continue
                out.push({ label: shortLabel(s.type), target: target })
            }
            inst.items = out
        }

        function refreshAllLaunchers() {
            for (const id in instances) {
                // Cheap structural test for "is launcher": presence of `items` array property.
                const inst = instances[id]
                if (inst && "items" in inst && Array.isArray(inst.items)) refreshLauncher(inst)
            }
        }
    }

    Connections {
        target: layoutModel
        function onLayoutReloaded() { factory.rebuild() }
        function onItemAdded(spec) {
            factory.createOne(spec)
            factory.refreshAllLaunchers()
        }
        function onItemRemoved(id) { factory.destroyOne(id) }
        function onItemUpdated(id, key, value) { factory.applyUpdate(id, key, value) }
    }

    // ---- IPC: `qs ipc call nothing <fn> [args...]` ----
    IpcHandler {
        target: "nothing"

        function add(type: string, optsJson: string): string {
            let opts = {}
            if (optsJson) { try { opts = JSON.parse(optsJson) } catch (e) {} }
            const spec = Object.assign(
                { type: type, variant: 0, themeMode: 0, posX: 100, posY: 100, visible: true },
                opts
            )
            return layoutModel.addItem(spec) || ""
        }

        function remove(id: string): void { layoutModel.removeItem(id) }

        function update(id: string, key: string, valueJson: string): void {
            let v = valueJson
            try { v = JSON.parse(valueJson) } catch (e) {}
            layoutModel.updateItem(id, key, v)
        }

        function toggle(id: string): void {
            const it = layoutModel.findItem(id)
            if (it) layoutModel.updateItem(id, "visible", !it.visible)
        }

        function setVisible(id: string, visible: bool): void {
            layoutModel.updateItem(id, "visible", visible)
        }

        function list(): string { return JSON.stringify(layoutModel.items, null, 2) }
        function reload(): void { layoutModel.reload() }
        function path(): string { return layoutModel.filePath }

        // Phase-1 placeholder: opens / surfaces the launcher dock.
        // Phase 2 will replace this with the full control panel.
        function openControl(): void {
            const it = layoutModel.items.find(function(s) { return s.type === "launcher" })
            if (it) layoutModel.updateItem(it.id, "visible", true)
        }

        function toggleLauncher(): void {
            const it = layoutModel.items.find(function(s) { return s.type === "launcher" })
            if (it) layoutModel.updateItem(it.id, "visible", !it.visible)
        }
    }
}
