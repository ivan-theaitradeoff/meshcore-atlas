pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Popup {
    id: root
    property var theme
    required property var client
    property var channel: ({})
    property var state: ({})
    property string page: "settings"
    property string error: ""
    function begin(item, section) { channel = item; page = section; state = {}; error = ""; channelName.text = item.name; open(); run(section === "share" ? "share" : "settings") }
    function run(action, extra) {
        let data = extra || {}
        data.target = channel.id; data.action = action
        error = ""
        client.request("channel_settings", "", undefined, data)
    }
    anchors.centerIn: parent
    width: Math.min(500, parent.width - 24); height: Math.min(610, parent.height - 24)
    modal: true; focus: true; padding: 18
    closePolicy: client.settingsPending ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: state = ({})
    background: Rectangle { color: root.theme.surface; border.color: root.theme.border; radius: 8 }
    Connections {
        target: root.client
        function onSettingsResult(result) {
            if (!root.visible) return
            if (!result.ok) { root.error = result.error; return }
            root.state = result.settings_result
            notifications.currentIndex = ["all", "mentions", "none"].indexOf(root.state.notifications || "all")
            retention.currentIndex = [0,1,7,30,90].indexOf(root.state.days || 0)
            if (root.state.message) root.page = "done"
        }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 10
        RowLayout {
            Label { text: root.channel.name || "Channel"; textFormat: Text.PlainText; color: root.theme.foreground; font.pixelSize: 19; Layout.fillWidth: true; elide: Text.ElideRight }
            Button { text: "×"; enabled: !root.client.settingsPending; onClicked: root.close() }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 10
                Label { visible: root.error.length > 0; text: root.error; color: root.theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Label { visible: root.client.settingsPending; text: "Loading…"; color: root.theme.muted }
                ColumnLayout {
                    visible: root.page === "settings"; Layout.fillWidth: true
                    Label { text: (root.state.count || 0) + " messages · " + (root.state.participants || []).length + " heard senders"; color: root.theme.muted }
                    Repeater {
                        model: [{label:"Notifications",page:"notifications"},{label:"Message Retention",page:"retention"},{label:"Participants",page:"participants"},{label:"Blocked Senders",page:"blocked"},{label:"Rename Channel",page:"rename"},{label:"Delete Message History",page:"delete_history"}]
                        delegate: Button { required property var modelData; text: modelData.label; Layout.fillWidth: true; onClicked: root.page = modelData.page }
                    }
                }
                ColumnLayout {
                    visible: root.page === "share"; Layout.fillWidth: true
                    Image { source: root.state.qr || ""; Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 220; Layout.preferredHeight: 220; cache: false }
                    Label { text: "Anyone with this key can join the channel."; color: root.theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    TextField { id: keyField; text: root.state.secret || ""; readOnly: true; selectByMouse: true; Layout.fillWidth: true }
                    Button { text: "Copy secret key"; onClicked: { keyField.selectAll(); keyField.copy() } }
                    TextField { id: linkField; text: root.state.uri || ""; readOnly: true; selectByMouse: true; Layout.fillWidth: true }
                    Button { text: "Copy channel link"; onClicked: { linkField.selectAll(); linkField.copy() } }
                }
                ComboBox { id: notifications; visible: root.page === "notifications"; model: ["All Messages", "Mentions Only", "None"]; Layout.fillWidth: true }
                ComboBox { id: retention; visible: root.page === "retention"; model: ["Keep All", "1 day", "7 days", "30 days", "90 days"]; Layout.fillWidth: true }
                Label { visible: root.page === "retention"; text: "Saving permanently deletes dated messages older than this limit from local history. Undated legacy messages are kept."; color: root.theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Button { visible: root.page === "notifications" || root.page === "retention"; text: root.page === "retention" ? "Confirm retention" : "Save"; enabled: !root.client.settingsPending; onClicked: root.run("preferences", {notifications: ["all","mentions","none"][notifications.currentIndex], days: [0,1,7,30,90][retention.currentIndex]}) }
                Label { visible: root.page === "participants"; text: "Senders heard in local history. Channel display names are not verified identities."; color: root.theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Repeater { model: root.page === "participants" ? (root.state.participants || []) : []; delegate: Label { required property string modelData; text: modelData; textFormat: Text.PlainText; color: root.theme.foreground } }
                Repeater { model: root.page === "blocked" ? (root.state.blocked || []) : []; delegate: Button { required property string modelData; text: "Unblock · " + modelData; Layout.fillWidth: true; enabled: !root.client.settingsPending; onClicked: root.run("unblock", {sender: modelData}) } }
                Label { visible: root.page === "blocked" && !(root.state.blocked || []).length; text: "No blocked senders"; color: root.theme.muted }
                TextField { id: channelName; visible: root.page === "rename"; Layout.fillWidth: true; maximumLength: 31 }
                Button { visible: root.page === "rename"; text: "Rename"; enabled: !root.client.settingsPending; onClicked: root.run("rename", {name:channelName.text}) }
                Label { visible: root.page === "remove" || root.page === "delete_history"; text: root.page === "remove" ? "Remove this channel from the node? Local history will be retained." : "Permanently delete this channel’s local message history?"; color: root.theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Button { visible: root.page === "remove" || root.page === "delete_history"; text: "Confirm"; enabled: !root.client.settingsPending; onClicked: { const action = root.page; root.run(action); if (action === "delete_history") root.page = "settings" } }
                Label { visible: root.page === "done"; text: root.state.message || "Saved"; color: root.theme.muted }
            }
        }
        Button { visible: root.page !== "settings" && root.page !== "share"; text: "Back to settings"; enabled: !root.client.settingsPending; onClicked: { root.page = "settings"; root.run("settings") } }
    }
}
