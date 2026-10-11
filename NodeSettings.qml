pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Popup {
    id: root
    property var theme
    required property var client
    property var identity: ({})
    property bool loaded: false
    property string feedback: ""
    function begin() { loaded = false; feedback = ""; open(); client.request("node_settings", "", undefined, {action:"get"}) }
    function fill(info) {
        identity = info
        for (let i=0; i<fields.count; i++) (fields.itemAt(i) as SettingField).value = String(info[(fields.itemAt(i) as SettingField).field.key] === undefined ? "" : info[(fields.itemAt(i) as SettingField).field.key])
        share.checked = info.adv_loc_policy === 1
        loaded = true
    }
    function save() {
        let data = {action:"save", adv_loc_policy: share.checked ? 1 : 0}
        for (let i=0; i<fields.count; i++) data[(fields.itemAt(i) as SettingField).field.key] = (fields.itemAt(i) as SettingField).value
        client.request("node_settings", "", undefined, data)
    }
    anchors.centerIn: parent
    width: Math.min(510, parent.width-24); height: Math.min(680,parent.height-24)
    modal: true; focus: true; padding: 18
    closePolicy: client.nodePending ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: root.theme.surface; border.color: root.theme.border; radius: 8 }
    Connections {
        target: root.client
        function onNodeResult(result) {
            if (!root.visible) return
            if (!result.ok) { root.feedback = result.error; return }
            root.fill(result.node_result.identity)
            root.feedback = result.node_result.message || ""
        }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 10
        Label { text: "Node Settings"; color: root.theme.foreground; font.pixelSize: 20 }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 10
                Label { text: "Public key"; color: root.theme.muted }
                Label { text: root.identity.public_key || "—"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: root.theme.foreground; font.family: "monospace"; Layout.fillWidth: true }
                TextEdit { id: publicKeyCopy; visible: false }
                Button { text: "Copy public key"; enabled: root.loaded; onClicked: { publicKeyCopy.text = root.identity.public_key || ""; publicKeyCopy.selectAll(); publicKeyCopy.copy(); publicKeyCopy.clear() } }
                Button {
                    text: "Use Canada / USA reference preset"
                    enabled: root.loaded && !root.client.nodePending
                    onClicked: {
                        const preset = {radio_freq:"910.525",radio_bw:"62.5",radio_sf:"7",radio_cr:"5"}
                        for (let i=0; i<fields.count; i++) if (preset[(fields.itemAt(i) as SettingField).field.key] !== undefined) (fields.itemAt(i) as SettingField).value = preset[(fields.itemAt(i) as SettingField).field.key]
                    }
                }
                component SettingField: ColumnLayout {
                    required property var modelData
                    readonly property var field: modelData
                    property alias value: input.text
                    Layout.fillWidth: true
                    Label { text: parent.field.label; color: root.theme.muted }
                    TextField { id: input; Layout.fillWidth: true; enabled: root.loaded && !root.client.nodePending; selectByMouse: true }
                }
                Repeater {
                    id: fields
                    model: [{key:"name",label:"Name"},{key:"adv_lat",label:"Latitude"},{key:"adv_lon",label:"Longitude"},{key:"radio_freq",label:"Frequency (MHz)"},{key:"radio_bw",label:"Bandwidth (kHz)"},{key:"radio_sf",label:"Spreading factor (5–12)"},{key:"radio_cr",label:"Coding rate (5–8)"},{key:"tx_power",label:"Transmit power (dBm)"}]
                    delegate: SettingField {}
                }
                CheckBox { id: share; text: "Share position in adverts"; enabled: root.loaded && !root.client.nodePending }
                Label { text: "Radio settings must match the nodes you want to reach. Saving does not send an advert."; color: root.theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        Label { text: root.feedback; visible: text.length>0; color: root.theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
        RowLayout {
            Button { text: "Close"; enabled: !root.client.nodePending; onClicked: root.close() }
            Button { text: root.client.nodePending ? "Working…" : "Save"; enabled: root.loaded && root.client.online && !root.client.nodePending; onClicked: root.save() }
        }
    }
}
