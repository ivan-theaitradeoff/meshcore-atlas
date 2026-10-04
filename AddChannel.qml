import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Popup {
    id: root
    objectName: "addChannelPopup"
    required property var client
    property string mode: "public"
    property string errorText: ""
    property string shareKey: ""
    property string savedTarget: ""
    property string savedName: ""
    property bool finished: false
    readonly property bool busy: !!client.channelPending
    readonly property string heading: mode === "private_create" ? "Create a Private Channel" : mode === "private_join" ? "Join a Private Channel" : mode === "hashtag" ? "Join a Hashtag Channel" : mode === "qr" ? "Import Channel QR" : "Join the Public Channel"
    function begin(kind) {
        mode = kind; errorText = ""; shareKey = ""; savedTarget = ""; finished = false
        channelName.text = (kind === "public" || kind === "public_import") ? "Public" : kind === "hashtag" ? "#" : ""
        secret.text = ""; qrSource.text = ""
        open()
    }
    function submit() {
        if (busy) return
        errorText = ""
        client.request("channel_add", "", undefined, {mode: mode, name: channelName.text, secret: secret.text, source: qrSource.text})
    }
    modal: true; focus: true
    anchors.centerIn: parent
    width: Math.min(470, parent.width - 24)
    height: Math.min(460, parent.height - 24)
    padding: 20
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: "#202a36"; border.color: "#647184"; radius: 8 }
    onClosed: { secret.text = ""; qrSource.text = ""; shareKey = "" }
    Connections {
        target: root.client
        function onChannelResult(result) {
            if (!root.opened) return
            if (!result.ok) { root.errorText = result.error; return }
            const channel = result.channel_added
            root.savedTarget = channel.target
            root.savedName = channel.name
            root.shareKey = channel.share_key || ""
            root.finished = true
            secret.text = ""; qrSource.text = ""
            root.client.target = channel.target
            root.client.request("snapshot")
        }
    }
    FileDialog {
        id: imagePicker
        title: "Choose a channel QR image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: qrSource.text = selectedFile.toString()
    }
    TextEdit { id: copyBuffer; visible: false }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Label { text: root.finished ? "Channel ready" : root.heading; color: "#c7d3df"; font.pixelSize: 18; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Button { text: "×"; enabled: !root.busy; onClicked: root.close() }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 12
                Label {
                    visible: !root.finished; Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a8bfd6"
                    text: root.mode === "private_create" ? "Create a channel with a new random secret key. Share the key with people you want to invite."
                        : root.mode === "private_join" ? "Enter the channel name and its 32-character hexadecimal secret key."
                        : root.mode === "hashtag" ? "Anyone can join using the same hashtag. Use a–z, 0–9 and hyphens."
                        : root.mode === "qr" ? "Choose a QR image from your computer, or paste a MeshCore channel link."
                        : root.mode === "public_import" ? "On your phone, open MeshCore → Public → ⋮ → Share. Copy the Secret Key and paste it below. If you reconnect this same node to your phone to get the key, disconnect it from the phone again before connecting here."
                        : "Anyone can join Public. Choose the name to display on your node."
                }
                TextField { id: channelName; objectName: "channelName"; visible: !root.finished && root.mode !== "qr"; Layout.fillWidth: true; placeholderText: "Channel name"; maximumLength: 31; enabled: !root.busy && root.mode !== "public_import" }
                TextField { id: secret; visible: !root.finished && (root.mode === "private_join" || root.mode === "public_import"); Layout.fillWidth: true; placeholderText: "Secret key (32 hex characters)"; echoMode: TextInput.Password; maximumLength: 32; enabled: !root.busy }
                Button { visible: !root.finished && root.mode === "qr"; text: "Choose QR image…"; Layout.fillWidth: true; enabled: !root.busy; onClicked: imagePicker.open() }
                TextField { id: qrSource; visible: !root.finished && root.mode === "qr"; Layout.fillWidth: true; placeholderText: "QR image path or meshcore:// channel link"; echoMode: TextInput.Password; enabled: !root.busy }
                Label { visible: root.errorText.length > 0; text: root.errorText; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#e3b98f" }
                Label { visible: root.finished; text: root.savedName + " is ready in your channel list."; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#c7d3df" }
                Label { visible: root.shareKey.length > 0; text: "Save this key to invite others. It will be hidden when you close this popup."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a8bfd6" }
                TextField { visible: root.shareKey.length > 0; text: root.shareKey; readOnly: true; Layout.fillWidth: true; selectByMouse: true }
                Button { visible: root.shareKey.length > 0; text: "Copy channel key"; Layout.fillWidth: true; onClicked: { copyBuffer.text = root.shareKey; copyBuffer.selectAll(); copyBuffer.copy(); copyBuffer.text = "" } }
            }
        }
        Button {
            Layout.fillWidth: true
            text: root.finished ? "Done" : root.busy ? "Saving…" : root.mode === "private_create" ? "Create Channel" : "Join Channel"
            enabled: !root.busy && (root.finished || root.client.online)
            onClicked: root.finished ? root.close() : root.submit()
        }
    }
}
