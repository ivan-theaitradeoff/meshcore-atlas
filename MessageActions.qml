import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    property var theme
    property var message: ({})
    property bool isChannel: true
    property bool showPaths: false
    property string notice: ""
    signal replyRequested(string sender)
    signal actionRequested(string action, int messageId)
    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(540, parent.width - 24)
    height: Math.min(620, parent.height - 24)
    padding: 18
    background: Rectangle { color: root.theme.surface; border.color: root.theme.border; radius: 8 }
    onOpened: { showPaths = false; notice = "" }
    function stamp(value) { return value ? new Date(value * 1000).toLocaleString() : "Unavailable for this message" }
    readonly property var meta: message.metadata || ({})
    TextEdit { id: clipboard; visible: false }
    ColumnLayout {
        anchors.fill: parent; spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Message Actions"; color: root.theme.foreground; font.pixelSize: 20; Layout.fillWidth: true }
            Button { text: "×"; onClicked: root.close() }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 10
                Label { text: root.message.sender || ""; textFormat: Text.PlainText; color: root.theme.muted; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                Label { text: root.message.text || ""; textFormat: Text.PlainText; color: root.theme.foreground; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                Label {
                    visible: Object.keys(root.meta).length === 0
                    text: "This message was saved before metadata capture was added. Its original timing and radio details were not retained."
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: root.theme.warning
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: root.theme.muted; font.family: "monospace"
                    text: "Sent: " + root.stamp(root.meta.sender_timestamp || root.meta.sent_at)
                          + "\nReceived locally: " + root.stamp(root.meta.received_at)
                          + "\nSNR: " + (root.meta.SNR !== undefined ? root.meta.SNR + " dB" : "Unavailable")
                          + "\nHops: " + (root.meta.path_len === 255 ? "Direct" : root.meta.path_len !== undefined ? root.meta.path_len : "Unavailable")
                          + "\nPath hash size: " + (root.meta.path_hash_mode >= 0 ? (root.meta.path_hash_mode + 1) + " bytes" : "Unavailable")
                }
                Button {
                    text: "Copy Text"; Layout.fillWidth: true
                    onClicked: { clipboard.text = root.message.text || ""; clipboard.selectAll(); clipboard.copy(); root.notice = "Copied to clipboard" }
                }
                Button {
                    text: "Reply"; Layout.fillWidth: true
                    onClicked: { root.replyRequested(root.message.sender || ""); root.close() }
                }
                Button { text: root.showPaths ? "Hide Message Paths" : "View Message Paths"; Layout.fillWidth: true; onClicked: root.showPaths = !root.showPaths }
                Label {
                    visible: root.showPaths; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: root.theme.foreground
                    text: root.meta.path ? "Recorded path: " + (Array.isArray(root.meta.path) ? root.meta.path.join(" → ") : root.meta.path)
                          : "No full route was provided for this message. Hop count and hash size are shown above when available."
                }
                Button {
                    text: root.message.blocked ? "Unblock Sender" : "Block Sender"
                    Layout.fillWidth: true; enabled: !!root.message.can_block
                    onClicked: { root.actionRequested(root.message.blocked ? "unblock" : "block", root.message.id); root.close() }
                }
                Label { visible: !!root.message.can_block; Layout.fillWidth: true; wrapMode: Text.Wrap; color: root.theme.muted; text: root.isChannel ? "Blocks future messages with this display name on this channel, on this computer only. Channel names are not verified identities. Reopen this message to unblock." : "Blocks future messages from this contact on this computer. Reopen this message to unblock." }
                Button { text: "Delete"; Layout.fillWidth: true; onClicked: deleteConfirm.open() }
                Label { text: root.notice; visible: text.length > 0; color: root.theme.muted }
            }
        }
    }
    Dialog {
        id: deleteConfirm
        title: "Delete this local message?"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "This removes it from this computer's chat history."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: { root.actionRequested("delete", root.message.id); root.close() }
    }
}
