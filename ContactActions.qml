import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    required property var client
    property var contact: ({})
    property string action: "details"
    property string info: ""
    property string link: ""
    property bool completed: false
    function begin(item, kind) {
        contact = item; action = kind; info = ""; link = ""; completed = false; path.text = ""; hashSize.currentIndex = 0
        open()
        if (kind === "details" || kind === "share") run()
    }
    function run() {
        client.request("contact_action", "", undefined, {key: contact.id.slice(3), action: action, path: path.text, mode: hashSize.currentIndex, enabled: !contact.favourite})
    }
    anchors.centerIn: parent
    width: Math.min(480, parent.width - 24); height: Math.min(440, parent.height - 24)
    modal: true; focus: true; padding: 20
    closePolicy: client.contactPending ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: "#202a36"; border.color: "#647184"; radius: 8 }
    Connections {
        target: root.client
        function onContactResult(result) {
            if (!root.visible) return
            if (!result.ok) { root.info = result.error; return }
            const value = result.contact_result
            root.completed = true
            root.link = value.uri || ""
            if (value.details) {
                const d = value.details
                root.info = "Name: " + (d.adv_name || "—") + "\nPublic key: " + (d.public_key || root.contact.id.slice(3))
                    + "\nType: " + ({1: "Companion", 2: "Repeater", 3: "Room server"}[d.type] || d.type || "—")
                    + "\nLast advert: " + (d.last_advert ? new Date(d.last_advert * 1000).toLocaleString() : "—")
                    + "\nRoute: " + (d.out_path_len === -1 ? "Flood" : d.out_path_len + " hops")
                    + "\nPath: " + (d.out_path || "—") + "\nHash size: " + (d.out_path_hash_mode !== undefined ? (d.out_path_hash_mode + 1) + " bytes" : "—")
                    + "\nAdvertised location: " + (d.adv_lat || 0) + ", " + (d.adv_lon || 0)
            } else root.info = value.message || "Copy this link to share the contact."
        }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        Label { text: root.contact.name ? root.contact.name.replace(/^DM · /, "") : "Contact"; textFormat: Text.PlainText; color: "#c7d3df"; font.pixelSize: 18; Layout.fillWidth: true; elide: Text.ElideRight }
        Label { text: ({details: "Details", share: "Share Contact", path: "Set Path", reset: "Reset Path", remove: "Remove Contact", favourite: "Favourite"})[root.action]; color: "#a8bfd6" }
        Label {
            visible: !root.completed && root.action !== "details" && root.action !== "share"
            text: root.action === "remove" ? "Remove this contact from your node? Local message history will be kept."
                : root.action === "reset" ? "Reset the stored route to flood routing?"
                : root.action === "favourite" ? (root.contact.favourite ? "Remove from favourites on this computer?" : "Save as a favourite on this computer?")
                : "Enter repeater hashes in route order, without spaces. An empty path means a direct route."
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#c7d3df"
        }
        TextField { id: path; visible: root.action === "path" && !root.completed; Layout.fillWidth: true; placeholderText: "Hex path"; maximumLength: 128 }
        ComboBox { id: hashSize; visible: root.action === "path" && !root.completed; model: ["1-byte hashes", "2-byte hashes", "3-byte hashes"]; Layout.fillWidth: true }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            TextArea { text: root.info; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; color: "#c7d3df" }
        }
        TextField { id: shareLink; visible: root.link.length > 0; text: root.link; readOnly: true; selectByMouse: true; Layout.fillWidth: true }
        Button { visible: root.link.length > 0; text: "Copy contact link"; Layout.fillWidth: true; onClicked: { shareLink.selectAll(); shareLink.copy() } }
        RowLayout {
            Button { text: "Close"; enabled: !root.client.contactPending; onClicked: root.close() }
            Button { visible: !root.completed && root.action !== "details" && root.action !== "share"; text: root.client.contactPending ? "Saving…" : "Confirm"; enabled: root.client.online && !root.client.contactPending; onClicked: root.run() }
        }
    }
}
