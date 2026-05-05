import QtQuick
import Quickshell
import "widgets/clockDigital" as ClockDigital
import "widgets/clockAnalog" as ClockAnalog
import "widgets/battery" as Battery
import "widgets/weather" as Weather
import "widgets/date" as DateWidget
import "widgets/launcher" as Launcher

ShellRoot {
    // ============================================================
    // Each widget supports:
    //   • Left-click + drag → move freely on the desktop
    //   • Right-click       → cycle to next variant (where >1 exists)
    //   • Smooth slide      → animates posX/posY changes from config
    //
    // Config below sets the *initial* values. Quickshell hot-reloads
    // on save, so you can tweak anything without restarting.
    //
    // The Launcher at the bottom is the on-screen control panel:
    // click a chip to show/hide that widget. It binds to each
    // widget's `visible` property by id.
    // ============================================================

    // ---------------- Digital Clock ----------------
    ClockDigital.ClockDigitalWindow {
        id: clockDigital

        variant: 0              // 0 = digital, 1 = world clock
        themeMode: 0            // 0 = dark, 1 = light
        use24HourFormat: false

        // World-clock options (used when variant === 1)
        cityName: "Gariyaband"
        timeZone: "India"

        posX: 40
        posY: 40

        // Aspect ratio >= 1.8 → pill mode. 320×100 → pill, 220×220 → square.
        widgetWidth: 320
        widgetHeight: 100
    }

    // ---------------- Analog Clock ----------------
    ClockAnalog.ClockAnalogWindow {
        id: clockAnalog

        variant: 0              // 0 = Swiss, 1 = Minimalist (pill hands)
        themeMode: 0
        smoothHands: true       // false = ticking each second

        posX: 40
        posY: 160
        widgetSize: 220
    }

    // ---------------- Battery ----------------
    Battery.BatteryWindow {
        id: battery

        themeMode: 0
        showBluetoothDevices: true   // false = laptop battery only

        posX: 400
        posY: 40
        widgetSize: 220
    }

    // ---------------- Weather ----------------
    // Right-click cycles 4 variants:
    //   0 = Rect Daily   (480×180 wide — header + 6-day forecast)
    //   1 = Rect Hourly  (480×180 wide — header + next 6 hours)
    //   2 = Square Now   (220×220 — temp + icon + city)
    //   3 = Square H/L   (220×220 — high/low + condition)
    // Uses Open-Meteo (free, no API key).
    Weather.WeatherWindow {
        id: weather

        variant: 0                  // start on Rect Daily
        themeMode: 0
        location: "Raipur, IN"      // city, optional country/region hints
        temperatureUnit: 0          // 0 = °C, 1 = °F

        posX: 280
        posY: 280
    }

    // ---------------- Date ----------------
    DateWidget.DateWindow {
        id: dateWidget

        themeMode: 0

        posX: 680
        posY: 40
        widgetWidth: 200
        widgetHeight: 200
    }

    // ---------------- Launcher (control panel) ----------------
    // Click a chip to toggle that widget's visibility. Add or
    // remove items from the list to change the dock contents.
    // The launcher itself is intentionally not in the list — to hide
    // it, set `visible: false` here.
    Launcher.LauncherWindow {
        id: launcher

        themeMode: 0

        posX: 40
        posY: 880

        items: [
            { label: "Date",   target: dateWidget   },
            { label: "Clock",  target: clockDigital },
            { label: "Analog", target: clockAnalog  },
            { label: "Bat",    target: battery      },
            { label: "Wthr",   target: weather      }
        ]
    }
}
