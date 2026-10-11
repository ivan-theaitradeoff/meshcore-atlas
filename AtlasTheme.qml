import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

    property color background: "#171e26"
    property color foreground: "#c7d3df"
    property color accent: "#bdd0e5"
    property color muted: "#899db1"
    property color warning: "#e3b98f"
    property color error: "#ef9b91"
    property color success: "#62ae60"
    property color border: "#444e5c"
    property color surface: "#202a36"
    property color sidebar: "#2e3540"
    property color hover: "#384452"
    property color selected: "#465362"
    property color input: "#2e3540"

    function hexColor(value, fallback) {
        var match = String(value || "").match(/^#([0-9a-fA-F]{6})$/)
        if (!match) return fallback
        return "#" + match[1]
    }

    function channels(value) {
        var hex = String(value || "#000000").replace(/^#/, "")
        return [parseInt(hex.slice(0, 2), 16) / 255,
                parseInt(hex.slice(2, 4), 16) / 255,
                parseInt(hex.slice(4, 6), 16) / 255]
    }

    function mix(base, tint, amount) {
        var a = channels(base)
        var b = channels(tint)
        return Qt.rgba(a[0] * (1 - amount) + b[0] * amount,
                        a[1] * (1 - amount) + b[1] * amount,
                        a[2] * (1 - amount) + b[2] * amount, 1)
    }

    function load(raw) {
        var values = {}
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9a-fA-F]{6})/)
            if (match) values[match[1]] = match[2]
        }

        var bg = hexColor(values.background || values.color0, "#171e26")
        var fg = hexColor(values.foreground || values.color7, "#c7d3df")
        var ansi1 = hexColor(values.color1, "#ef9b91")
        var ansi2 = hexColor(values.color2, "#62ae60")
        var ansi3 = hexColor(values.color3, "#e3b98f")
        var ansi4 = hexColor(values.color4, "#bdd0e5")
        var ansi8 = hexColor(values.color8, "#899db1")
        var activeAccent = hexColor(values.accent || values.selection || values.color4, ansi4)

        background = bg
        foreground = fg
        accent = activeAccent
        muted = mix(fg, bg, 0.32)
        warning = ansi3
        error = ansi1
        success = ansi2
        border = mix(bg, fg, 0.25)
        surface = mix(bg, ansi8, 0.28)
        sidebar = mix(bg, ansi8, 0.48)
        hover = mix(bg, activeAccent, 0.20)
        selected = mix(bg, activeAccent, 0.34)
        input = mix(bg, fg, 0.15)
    }

    property FileView colorsFile: FileView {
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: root.load("")
    }

    // Theme switching replaces the active-theme symlink. Reopening its target
    // periodically also catches that atomic symlink change on every filesystem.
    property Timer refreshTimer: Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.colorsFile.reload()
    }
}
