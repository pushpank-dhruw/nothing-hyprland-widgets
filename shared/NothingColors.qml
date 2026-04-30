import QtQuick

QtObject {
    id: nColors

    property int themeMode: 0
    property bool useSystemAccent: false

    readonly property bool isLight: themeMode === 1

    readonly property color background: isLight ? "#f5f5f5" : "#1a1a1a"
    readonly property color surface:    isLight ? "#ffffff" : "#2a2a2a"

    readonly property color textPrimary:     isLight ? "#1a1a1a" : "#ffffff"
    readonly property color textSecondary:   isLight ? "#666666" : "#aaaaaa"
    readonly property color textMuted:       isLight ? "#777777" : "#888888"
    readonly property color textDisabled:    isLight ? "#aaaaaa" : "#666666"
    readonly property color textPlaceholder: isLight ? "#999999" : "#b0b0b0"

    readonly property color accent:           "#ff4444"
    readonly property color accentSecondHand: "#D71921"

    readonly property color warning: "#ffc107"
    readonly property color error:   "#d32f2f"

    readonly property color divider:  isLight ? "#dddddd" : "#333333"
    readonly property color pagePeel: isLight ? "#cccccc" : "#3a3a3a"

    readonly property color indicatorActive:   isLight ? "#1a1a1a" : "#ffffff"
    readonly property color indicatorInactive: isLight ? "#aaaaaa" : "#666666"

    readonly property color iconColor: isLight ? "#1a1a1a" : "#ffffff"
    readonly property color borderLight: isLight ? "#cccccc" : "#e0e0e0"
    readonly property color neutral: "#808080"

    readonly property color surfaceAlt:      isLight ? "#e8edf2" : "#0f1419"
    readonly property color surfaceGradient: isLight ? "#dce4ed" : "#1a2332"

    readonly property color batteryBgFill:       isLight ? "#0a000000" : "#04ffffff"
    readonly property color batteryProgressFill: isLight ? "#1b000000" : "#1bffffff"
    readonly property color batteryRingFill:     isLight ? "#43000000" : "#43ffffff"
}
