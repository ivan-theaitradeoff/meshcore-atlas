import QtQuick
import QtTest
import "../../" as Plugin

Item {
    width: 760; height: 500
    QtObject {
        id: client
        property bool canSend: true
        property bool sendPending: false
        property bool channelPending: false
        signal channelResult(var result)
        signal aiResult(var result)
        property bool aiPending: false
        signal nodeResult(var result)
        property bool nodePending: false
        signal settingsResult(var result)
        property bool settingsPending: false
        signal contactResult(var result)
        property bool contactPending: false
        property bool online: true
        property var node: ({})
        property var mapNodes: []
        property var channels: [{id:"ch:0", name:"Public"}]
        property var messages: []
        property string target: "ch:0"
        property string connectionState: "demo"
        property string error: ""
        property string ai: "disabled"
        property int sends: 0
        property string sentText: ""
        signal messageSent(string message, string destination)
        function request(op, text) {
            if (op === "send") { sends++; sentText = text; sendPending = true }
        }
    }
    Plugin.MeshPanel { id: panel; anchors.fill: parent; client: client; theme: ({background:"#171e26", foreground:"#c7d3df", muted:"#899db1", surface:"#202a36", sidebar:"#2e3540", border:"#444e5c", accent:"#bdd0e5", selected:"#465362", hover:"#384452", warning:"orange", error:"red", success:"green"}) }
    TestCase {
        name: "Composer"
        when: windowShown
        function init() { client.sendPending = false; client.sends = 0; findChild(panel, "messageComposer").text = "" }
        function test_independent_views_keep_draft_and_map() {
            const messages = findChild(panel, "messagesPane")
            const mapPane = findChild(panel, "mapPane")
            const composer = findChild(panel, "messageComposer")
            composer.text = "Keep this draft"
            compare(messages.visible, true)
            mouseClick(findChild(panel, "mapTab"))
            tryCompare(mapPane, "visible", true)
            compare(messages.visible, true)
            tryVerify(function() { return mapPane.item !== null })
            const mapItem = mapPane.item
            mouseClick(findChild(panel, "channelsTab"))
            compare(messages.visible, false)
            compare(mapPane.visible, true)
            mouseClick(findChild(panel, "channelsTab"))
            compare(messages.visible, true)
            compare(composer.text, "Keep this draft")
            mouseClick(findChild(panel, "mapTab"))
            compare(mapPane.visible, false)
            compare(messages.visible, true)
            compare(mapPane.item, mapItem)
            mouseClick(findChild(panel, "channelsTab"))
            compare(messages.visible, false)
            mouseClick(findChild(panel, "channelsTab"))
            compare(messages.visible, true)
        }
        function test_repeat_update_preserves_row_and_scroll() {
            let items = []
            for (let i = 0; i < 35; i++) items.push({id: i + 1, sender: "me", text: "Message " + i, status: "listening for repeats", metadata: {}})
            client.messages = items
            const history = findChild(panel, "messageHistory")
            tryCompare(history, "count", 35)
            wait(30)
            history.positionViewAtBeginning()
            wait(30)
            const row = history.itemAtIndex(0)
            verify(row !== null)
            const before = history.contentY
            let updated = JSON.parse(JSON.stringify(items))
            updated[0].status = "Heard 2 repeats"
            client.messages = updated
            wait(30)
            compare(history.itemAtIndex(0), row)
            compare(row.modelData.status, "Heard 2 repeats")
            compare(history.contentY, before)
            client.messages = []
        }
        function test_channel_popup_success_and_error() {
            const popup = findChild(panel, "addChannelPopup")
            popup.begin("public")
            tryCompare(popup, "opened", true)
            compare(findChild(popup, "channelName").text, "Public")
            client.channelResult({ok: false, error: "No empty slot"})
            compare(popup.errorText, "No empty slot")
            compare(popup.finished, false)
            client.channelResult({ok: true, channel_added: {target: "ch:2", name: "Friends", share_key: "0123456789abcdef0123456789abcdef"}})
            compare(popup.finished, true)
            compare(client.target, "ch:2")
            popup.close()
            tryCompare(popup, "opened", false)
            compare(popup.shareKey, "")
            client.target = "ch:0"
        }
        function test_click_message_opens_actions() {
            client.messages = [{id: 1, sender: "Alice", text: "hello", status: "received", metadata: {}, can_block: true}]
            tryVerify(function() { return findChild(panel, "messageRow") !== null })
            mouseClick(findChild(panel, "messageRow"))
            const actions = findChild(panel, "messageActions")
            tryCompare(actions, "opened", true)
            compare(actions.message.text, "hello")
            actions.close()
            client.messages = []
        }
        function test_return_sends_and_success_clears() {
            const field = findChild(panel, "messageComposer")
            field.text = "hello"; field.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(client.sends, 1)
            compare(field.text, "hello")
            keyClick(Qt.Key_Return)
            compare(client.sends, 1)
            client.sendPending = false
            client.messageSent(client.sentText, "ch:0")
            compare(field.text, "")
        }
        function test_button_and_failure_keep_draft() {
            const field = findChild(panel, "messageComposer")
            field.text = "retain me"
            mouseClick(findChild(panel, "sendButton"))
            compare(client.sends, 1)
            client.sendPending = false
            client.error = "Send failed"
            compare(field.text, "retain me")
        }
    }
}
