pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string target: "ch:0"
    property var channels: []
    property var messages: []
    property var node: ({})
    property var mapNodes: []
    property int unread: 0
    property int messageByteLimit: 160
    property string connectionState: "bridge offline"
    property string ai: "disabled"
    property string error: ""
    property bool canSend: false
    property bool sendPending: false
    property bool channelPending: false
    signal channelResult(var result)
    signal contactResult(var result)
    signal aiResult(var result)
    property bool aiPending: false
    signal nodeResult(var result)
    property bool nodePending: false
    signal settingsResult(var result)
    property bool settingsPending: false
    property bool contactPending: false
    property var pendingRequests: []
    signal messageSent(string message, string destination)
    readonly property var socket: socketLoader.item
    readonly property bool online: socket !== null && socket.connected
    function request(op, text, messageId, channel) {
        if (!socket || !socket.connected) return
        if (op === "send") {
            if (!canSend || sendPending || !text.trim()) return
            sendPending = true
            error = ""
        }
        if (op === "channel_add") {
            if (channelPending) return
            channelPending = true
            error = ""
        }
        if (op === "contact_action") {
            if (contactPending) return
            contactPending = true
        }
        if (op === "channel_settings") { if (settingsPending) return; settingsPending = true }
        if (op === "node_settings") { if (nodePending) return; nodePending = true }
        if (op === "ai_settings") { if (aiPending) return; aiPending = true }
        pendingRequests.push({op: op, text: text || "", target: target})
        socket.write(JSON.stringify({op: op, target: target, text: text || "", message_id: messageId, channel: channel}) + "\n")
        socket.flush()
    }
    onTargetChanged: request("snapshot")
    Loader {
        id: socketLoader
        sourceComponent: Component {
    Socket {
        id: connection
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/meshcore-bridge/bridge.sock"
        connected: true
        onConnectionStateChanged: {
            if (connected) root.request("snapshot")
            else { root.connectionState = "bridge offline"; root.canSend = false
                if (root.sendPending) root.error = "Connection lost; delivery unknown. Your draft has been kept."
                root.sendPending = false
                if (root.channelPending) root.channelResult({ok: false, error: "Connection lost; inspect channels before retrying."})
                root.channelPending = false
                if (root.contactPending) root.contactResult({ok: false, error: "Connection lost; check the node before retrying."})
                root.contactPending = false
                if (root.settingsPending) root.settingsResult({ok: false, error: "Connection lost; check before retrying."})
                root.settingsPending = false
                if (root.nodePending) root.nodeResult({ok: false, error: "Connection lost; reopen settings to verify."})
                root.nodePending = false
                if (root.aiPending) root.aiResult({ok: false, error: "Connection lost; refresh settings to check."})
                root.aiPending = false
                root.pendingRequests = []
            }
        }
        parser: SplitParser {
            onRead: function(line) {
                try {
                    const data = JSON.parse(line)
                    const request = root.pendingRequests.shift()
                    if (request && request.op === "send") {
                        root.sendPending = false
                        if (data.ok) root.messageSent(request.text, request.target)
                    }
                    if (request && request.op === "channel_add") {
                        root.channelPending = false
                        root.channelResult(data)
                    }
                    if (request && request.op === "contact_action") { root.contactPending = false; root.contactResult(data) }
                    if (request && request.op === "channel_settings") { root.settingsPending = false; root.settingsResult(data) }
                    if (request && request.op === "node_settings") { root.nodePending = false; root.nodeResult(data) }
                    if (request && request.op === "ai_settings") { root.aiPending = false; root.aiResult(data) }
                    if (!data.ok) { if (!request || request.op !== "channel_settings") root.error = data.error; return }
                    root.messageByteLimit = data.message_byte_limit || 160
                    root.channels = data.channels
                    root.messages = data.messages
                    root.unread = data.unread
                    root.connectionState = data.state
                    root.ai = data.ai
                    root.canSend = data.can_send
                    root.node = data.node || ({})
                    if (JSON.stringify(root.mapNodes) !== JSON.stringify(data.map_nodes || [])) root.mapNodes = data.map_nodes || []
                } catch (e) { root.error = "Invalid bridge response" }
            }
        }
    }
        }
    }
    Timer {
        interval: 1500; repeat: true; running: true
        onTriggered: {
            if (!root.online) {
                socketLoader.active = false
                Qt.callLater(function() { socketLoader.active = true })
            }
            else root.request("snapshot")
        }
    }
}
