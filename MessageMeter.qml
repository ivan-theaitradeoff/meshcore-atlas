import QtQuick
import QtQuick.Controls

Item {
    id: root
    property string message: ""
    property int limit: 160
    readonly property int used: byteLength(message)
    readonly property bool overLimit: used > limit
    implicitWidth: 32
    implicitHeight: 32
    Accessible.role: Accessible.ProgressBar
    Accessible.name: used + " of " + limit + " message bytes"
    function byteLength(value) {
        let count = 0
        for (let i = 0; i < value.length; i++) {
            const c = value.charCodeAt(i)
            if (c < 0x80) count++
            else if (c < 0x800) count += 2
            else if (c >= 0xd800 && c <= 0xdbff && i + 1 < value.length && value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff) { count += 4; i++ }
            else count += 3
        }
        return count
    }
    onUsedChanged: ring.requestPaint()
    onLimitChanged: ring.requestPaint()
    Canvas {
        id: ring
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const radius = Math.min(width, height) / 2 - 4
            ctx.lineWidth = 3
            ctx.strokeStyle = "#465362"
            ctx.beginPath(); ctx.arc(width/2, height/2, radius, 0, Math.PI*2); ctx.stroke()
            ctx.strokeStyle = root.overLimit ? "#ef9b91" : root.used >= root.limit * 0.9 ? "#e3b98f" : "#bdd0e5"
            ctx.beginPath(); ctx.arc(width/2, height/2, radius, -Math.PI/2, -Math.PI/2 + Math.PI*2*Math.min(1,root.used/Math.max(1,root.limit))); ctx.stroke()
        }
    }
    Text { anchors.centerIn: parent; visible: root.used >= root.limit * 0.9; text: root.limit - root.used; font.pixelSize: 10; color: root.overLimit ? "#ef9b91" : "#c7d3df" }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: used + " / " + limit + " bytes"
}
