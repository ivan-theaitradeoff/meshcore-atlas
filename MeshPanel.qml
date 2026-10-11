pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var theme
    signal connectionRequested()
    required property var client
    property bool active: false
    property string sidebarSection: "channels"
    property bool messagesVisible: true
    property bool mapVisible: false
    property bool mapLoaded: false
    function toggleView(section) {
        if (section === "map") {
            mapLoaded = true
            mapVisible = !mapVisible
        } else {
            messagesVisible = sidebarSection === section ? !messagesVisible : true
            sidebarSection = section
        }
    }
    readonly property bool hasPublic: client.channels.some(function(item) { return item.id.indexOf("ch:") === 0 && item.name.toLowerCase().replace(/^#\s*/, "") === "public" })
    readonly property bool publicSetup: client.target === "setup:public"
    readonly property var channelItems: {
        const items = client.channels.filter(function(item) { return item.id.indexOf("ch:") === 0 })
        return hasPublic ? items : [{id:"setup:public", name:"Public"}].concat(items)
    }
    readonly property var contactItems: client.channels.filter(function(item) { return item.id.indexOf("dm:") === 0 || item.heard_only }).sort(function(a, b) {
        return Number(!!b.favourite) - Number(!!a.favourite) || a.name.localeCompare(b.name)
    })
    readonly property string conversationName: {
        const item = client.channels.find(function(item) { return item.id === root.client.target })
        return root.publicSetup ? "Public" : item ? item.name : "Select a channel"
    }
    function sendMessage() {
        if (client.canSend && !client.sendPending && !messageMeter.overLimit && composer.text.trim().length > 0)
            client.request("send", composer.text)
    }
    ListModel { id: messageModel; dynamicRoles: true }
    property string displayedTarget: ""
    property var displayedMessages: []
    function syncMessages() {
        const items = client.messages
        const changedConversation = displayedTarget !== client.target
        const oldLast = displayedMessages.length ? displayedMessages[displayedMessages.length - 1].id : null
        if (changedConversation) messageModel.clear()
        for (let i = 0; i < items.length; i++) {
            if (i < messageModel.count && messageModel.get(i).entry.id !== items[i].id) {
                let found = -1
                for (let j = i + 1; j < messageModel.count; j++) {
                    if (messageModel.get(j).entry.id === items[i].id) { found = j; break }
                }
                if (found >= 0) messageModel.remove(i, found - i)
                else messageModel.insert(i, {entry: items[i]})
            }
            if (i >= messageModel.count) messageModel.append({entry: items[i]})
            else if (changedConversation || JSON.stringify(displayedMessages[i]) !== JSON.stringify(items[i]))
                messageModel.setProperty(i, "entry", items[i])
        }
        if (messageModel.count > items.length) messageModel.remove(items.length, messageModel.count - items.length)
        displayedTarget = client.target
        displayedMessages = items
        const newLast = items.length ? items[items.length - 1].id : null
        if (changedConversation || oldLast !== newLast) history.showNewest()
    }
    function selectPublicSetup() {
        if (client.online && !hasPublic && !client.channels.some(function(item) { return item.id === client.target })) client.target = "setup:public"
        else if (hasPublic && publicSetup) client.target = channelItems.find(function(item) { return item.name.toLowerCase().replace(/^#\s*/, "") === "public" }).id
    }
    Component.onCompleted: { syncMessages(); selectPublicSetup() }
    Connections {
        target: root.client
        function onChannelsChanged() { root.selectPublicSetup() }
        function onMessagesChanged() { root.syncMessages() }
        function onMessageSent(message, destination) {
            if (composer.text === message && root.client.target === destination) composer.clear()
            composer.forceActiveFocus()
        }
    }
    Popup {
        id: nodeDetailsPopup
        parent: root
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 24)
        height: Math.min(680, parent.height - 24)
        modal: true; focus: true; padding: 18
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: root.theme.surface; border.color: root.theme.border; radius: 8 }
        ColumnLayout {
            anchors.fill: parent; spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Label { text: "Node Details"; color: root.theme.foreground; font.pixelSize: 20; Layout.fillWidth: true }
                Button { text: "×"; onClicked: nodeDetailsPopup.close() }
            }
            NodeDetails {
                theme: root.theme
                Layout.fillWidth: true; Layout.fillHeight: true
                node: root.client.node
                connected: root.client.online && root.client.connectionState.indexOf("connected") === 0
            }
        }
    }
    LocalAiGuide { id: aiGuide; theme: root.theme; parent: root; onCreateChannel: addChannel.begin("private_create"); onOpenSettings: aiSettings.begin() }
    AiSettings { id: aiSettings; theme: root.theme; parent: root; client: root.client }
    NodeSettings { id: nodeSettings; theme: root.theme; parent: root; client: root.client }
    ChannelSettings { id: channelSettings; theme: root.theme; parent: root; client: root.client }
    ContactActions { id: contactActions; theme: root.theme; parent: root; client: root.client }
    AddChannel { id: addChannel; theme: root.theme; parent: root; client: root.client }
    MessageActions {
        id: messageActions
        objectName: "messageActions"
        parent: root
        theme: root.theme
        isChannel: root.client.target.indexOf("ch:") === 0
        onReplyRequested: function(sender) {
            if (root.client.target.indexOf("ch:") === 0 && sender !== "me" && sender !== "channel peer")
                composer.text = "@[" + sender + "] " + composer.text
            composer.forceActiveFocus()
            composer.cursorPosition = composer.text.length
        }
        onActionRequested: function(action, messageId) { root.client.request(action, "", messageId) }
    }
    color: root.theme.background
    border.color: root.theme.border
    onActiveChanged: if (active && messagesVisible && client) client.request("read")
    Timer { interval: 1600; running: root.active && root.messagesVisible; repeat: true; onTriggered: root.client.request("read") }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 14; spacing: 12
        Item {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight
            RowLayout {
            id: headerRow
            anchors.fill: parent
            Label { text: root.client.node.identity && root.client.node.identity.name ? root.client.node.identity.name : "MESH ATLAS"; textFormat: Text.PlainText; Layout.maximumWidth: 300; elide: Text.ElideRight; color: root.theme.foreground; font.family: "monospace"; font.bold: true }
            ToolButton {
                text: "⋮"; Accessible.name: "Node menu"
                contentItem: Text { text: "⋮"; color: root.theme.foreground; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: nodeMenu.popup()
                Menu {
                    id: nodeMenu
                    MenuItem { text: "Connection setup"; onTriggered: root.connectionRequested() }
                    MenuItem { text: "Local AI Settings"; enabled: root.client.online; onTriggered: aiSettings.begin() }
                    MenuItem { text: "Node Settings"; enabled: root.client.online; onTriggered: nodeSettings.begin() }
                    MenuItem { text: "Node Details"; onTriggered: nodeDetailsPopup.open() }
                }
            }
            Item { id: headerSpace; Layout.fillWidth: true }
            ActionButton { theme: root.theme; text: "Connect Local AI"; onClicked: aiGuide.open() }
            Label { text: root.client.connectionState; color: root.theme.muted; font.family: "monospace" }
        }
            Label {
                anchors.centerIn: parent
                width: Math.max(0, Math.min(parent.width / 2 - headerSpace.x, headerSpace.x + headerSpace.width - parent.width / 2) * 2 - 16)
                text: "Meshcore Atlas"
                color: root.theme.foreground
                font.family: "monospace"
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.border }
        SplitView {
            id: conversationSplit
            objectName: "conversationSplit"
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: Qt.Horizontal
            handle: Rectangle {
                implicitWidth: 12
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 2; height: parent.height
                    color: parent.SplitHandle.pressed ? root.theme.foreground : parent.SplitHandle.hovered ? root.theme.muted : root.theme.border
                }
            }
            Rectangle {
                objectName: "navigationSidebar"
                color: root.theme.sidebar
                SplitView.preferredWidth: 175
                SplitView.minimumWidth: 150
                SplitView.maximumWidth: Math.max(150, conversationSplit.width - 300)
                RowLayout {
                    id: navigation
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
                    height: 42; spacing: 3
                    Repeater {
                        model: [
                            {section: "contacts", label: "Contacts", path: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8M4 21v-2c0-4 16-4 16 0v2"},
                            {section: "channels", label: "Channels", path: "M9 3 7 21M17 3 15 21M3 9h18M2 15h18"},
                            {section: "map", label: "Map", path: "m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2ZM9 3v16M15 5v16"}
                        ]
                        delegate: ToolButton {
                            id: tabButton
                            required property var modelData
                            objectName: modelData.section + "Tab"
                            Layout.fillWidth: true; Layout.fillHeight: true
                            enabled: true
                            checkable: true
                            checked: modelData.section === "map" ? root.mapVisible : root.messagesVisible && root.sidebarSection === modelData.section
                            Accessible.name: modelData.label
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.label
                            background: Rectangle {
                                radius: 4
                                color: tabButton.checked ? root.theme.selected : tabButton.hovered ? root.theme.hover : "transparent"
                            }
                            contentItem: Image {
                                source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="' + tabButton.modelData.path + '" fill="none" stroke="' + root.theme.foreground + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')
                                sourceSize.width: 24; sourceSize.height: 24
                                fillMode: Image.PreserveAspectFit
                                opacity: tabButton.enabled ? 1 : 0.35
                            }
                            onClicked: root.toggleView(modelData.section)
                        }
                    }
                }
                ListView {
                    objectName: "sidebarList"
                    anchors { top: navigation.bottom; left: parent.left; right: parent.right; bottom: addButton.top; margins: 5 }
                    clip: true
                    ScrollBar.vertical: ScrollBar {}
                    model: !root.messagesVisible ? [] : root.sidebarSection === "contacts" ? root.contactItems : root.channelItems
                    delegate: Rectangle {
                        id: channelRow
                        required property var modelData
                        width: ListView.view.width; height: 48
                        color: root.client.target === channelRow.modelData.id ? root.theme.selected : "transparent"
                        Text { anchors.fill: parent; anchors.margins: 8; anchors.rightMargin: 32; text: (channelRow.modelData.favourite ? "★ " : "") + channelRow.modelData.name.replace(/^DM · /, "") + (channelRow.modelData.heard_only ? " · heard" : ""); textFormat: Text.PlainText; color: root.theme.foreground; font.family: "monospace"; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                        MouseArea { anchors.fill: parent; onClicked: { root.messagesVisible = true; root.client.target = channelRow.modelData.source_target || channelRow.modelData.id; root.client.request("read") } }
                        HoverHandler { id: rowHover }
                        ToolTip.visible: rowHover.hovered && !!channelRow.modelData.heard_only
                        ToolTip.text: "Heard in channel · Open channel. Direct messaging requires a saved node contact."
                        ToolButton {
                            id: moreButton
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 38; text: "⋮"
                            contentItem: Text { text: "⋮"; color: root.theme.foreground; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            visible: !channelRow.modelData.heard_only && channelRow.modelData.id !== "setup:public" && (rowHover.hovered || hovered || contactMenu.visible || channelMenu.visible)
                            Accessible.name: root.sidebarSection === "contacts" ? "Contact actions" : "Channel actions"
                            onClicked: root.sidebarSection === "contacts" ? contactMenu.popup() : channelMenu.popup()
                            Menu {
                                id: channelMenu
                                MenuItem { text: "Share"; onTriggered: channelSettings.begin(channelRow.modelData, "share") }
                                MenuItem { text: "Notifications"; onTriggered: channelSettings.begin(channelRow.modelData, "notifications") }
                                MenuItem { text: "Remove Channel"; onTriggered: channelSettings.begin(channelRow.modelData, "remove") }
                                MenuItem { text: "Channel Settings"; onTriggered: channelSettings.begin(channelRow.modelData, "settings") }
                            }
                            Menu {
                                id: contactMenu
                                MenuItem { text: "Details"; onTriggered: contactActions.begin(channelRow.modelData, "details") }
                                MenuItem { text: "Share"; onTriggered: contactActions.begin(channelRow.modelData, "share") }
                                MenuItem { text: "Set Path"; onTriggered: contactActions.begin(channelRow.modelData, "path") }
                                MenuItem { text: "Reset Path"; onTriggered: contactActions.begin(channelRow.modelData, "reset") }
                                MenuItem { text: "Remove Contact"; onTriggered: contactActions.begin(channelRow.modelData, "remove") }
                                MenuSeparator {}
                                MenuItem { text: channelRow.modelData.favourite ? "Unfavourite" : "Favourite"; enabled: root.client.online && !root.client.contactPending; onTriggered: root.client.request("contact_action", "", undefined, {key: channelRow.modelData.id.slice(3), action: "favourite", enabled: !channelRow.modelData.favourite}) }
                            }
                        }
                    }
                    Label { anchors.centerIn: parent; visible: root.messagesVisible && !parent.count; text: root.sidebarSection === "contacts" ? "No contacts heard yet" : "No channels\nConnect a radio\nor start demo"; color: root.theme.muted; font.family: "monospace" }
                }
                ActionButton {
                    id: addButton
                    theme: root.theme
                    objectName: "addChannelButton"
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 5 }
                    visible: root.messagesVisible && root.sidebarSection === "channels"
                    height: visible ? implicitHeight : 0
                    text: "+ Add channel"
                    onClicked: addMenu.popup()
                    Menu {
                        id: addMenu
                        y: -implicitHeight
                        MenuItem { text: "Create a Private Channel"; onTriggered: addChannel.begin("private_create") }
                        MenuItem { text: "Join a Private Channel"; onTriggered: addChannel.begin("private_join") }
                        MenuItem { text: "Join the Public Channel"; onTriggered: addChannel.begin("public") }
                        MenuItem { text: "Join a Hashtag Channel"; onTriggered: addChannel.begin("hashtag") }
                        MenuSeparator {}
                        MenuItem { text: "Import QR Code…"; onTriggered: addChannel.begin("qr") }
                    }
                }
            }
            ColumnLayout {
                objectName: "messagesPane"
                visible: root.messagesVisible
                SplitView.fillWidth: visible
                SplitView.minimumWidth: 280
                Label { text: root.conversationName; textFormat: Text.PlainText; color: root.theme.foreground; font.family: "monospace"; Layout.fillWidth: true; elide: Text.ElideRight }
                ColumnLayout {
                    visible: root.publicSetup
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Item { Layout.fillHeight: true }
                    Label { text: "Set up Public"; color: root.theme.foreground; font.pixelSize: 22 }
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: root.theme.foreground; text: "On your phone, open the MeshCore app and select Public. Open the three-dot menu and choose Share, then copy the Secret Key. Paste it below to add Public to this node." }
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: root.theme.muted; text: "If you use this same node with your phone to get the key, disconnect it from the phone afterward so Mesh Atlas can reconnect." }
                    Button { text: "Paste Public channel key…"; enabled: root.client.online; onClicked: addChannel.begin("public_import") }
                    Item { Layout.fillHeight: true }
                }
                ListView {
                    visible: !root.publicSetup
                    id: history
                    objectName: "messageHistory"
                    function showNewest() {
                        Qt.callLater(function() { history.positionViewAtEnd() })
                    }
                    onHeightChanged: showNewest()
                    Component.onCompleted: showNewest()
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
                    model: messageModel
                    delegate: Item {
                        id: messageRow
                        objectName: "messageRow"
                        required property var entry
                        readonly property var modelData: entry
                        width: history.width; height: messageContent.implicitHeight
                        Column {
                            id: messageContent
                            width: parent.width; spacing: 4
                        Text { width: parent.width; text: messageRow.modelData.sender + " · " + messageRow.modelData.status; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.theme.muted; font.family: "monospace"; font.pixelSize: 11 }
                        Text { width: parent.width; text: messageRow.modelData.text; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.theme.foreground; font.family: "monospace"; font.pixelSize: 13 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: { messageActions.message = messageRow.modelData; messageActions.open() }
                        }
                    }
                    Label { anchors.centerIn: parent; visible: !root.client.messages.length; text: "No messages on this channel"; color: root.theme.muted; font.family: "monospace" }
                }
                Label { Layout.fillWidth: true; text: root.client.error; visible: text.length > 0; wrapMode: Text.Wrap; color: root.theme.warning }
                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        id: composer
                        enabled: !root.publicSetup
                        objectName: "messageComposer"
                        readOnly: root.client.sendPending
                        onAccepted: root.sendMessage()
                        Layout.fillWidth: true
                        placeholderText: root.client.canSend ? "Message · " + messageMeter.limit + " byte limit" : "RF locked / disconnected"
                        maximumLength: messageMeter.limit
                        color: root.theme.foreground; placeholderTextColor: root.theme.muted; selectionColor: root.theme.selected; selectedTextColor: root.theme.foreground; font.family: "monospace"
                        background: Rectangle { color: root.theme.sidebar; border.color: root.theme.border }
                    }
                    MessageMeter { id: messageMeter; theme: root.theme; objectName: "messageMeter"; message: composer.text; limit: root.client.messageByteLimit || 160; Layout.preferredWidth: 32; Layout.preferredHeight: 32 }
                    ActionButton {
                        theme: root.theme
                        objectName: "sendButton"
                        text: root.client.sendPending ? "Sending…" : "Send"
                        enabled: root.client.canSend && !root.client.sendPending && !messageMeter.overLimit && composer.text.trim().length > 0
                        onClicked: root.sendMessage()
                    }
                }
            }
            Loader {
                objectName: "mapPane"
                active: root.mapLoaded
                visible: root.mapVisible
                SplitView.fillWidth: !root.messagesVisible
                SplitView.minimumWidth: 240
                SplitView.preferredWidth: Math.max(240, (conversationSplit.width - 199) / 2)
                sourceComponent: MapPanel {
                    client: root.client; theme: root.theme
                    onOpenContact: function(target) {
                        root.client.target = target
                        root.sidebarSection = "contacts"
                        root.messagesVisible = true
                        root.client.request("read")
                    }
                }
            }
            Label {
                visible: !root.messagesVisible && !root.mapVisible
                SplitView.fillWidth: true
                text: "Select Channels, Contacts, or Map to open a view."
                color: root.theme.muted
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.border }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "BAT " + (root.client.node.battery && root.client.node.battery.level !== undefined ? (root.client.node.battery.level / 1000).toFixed(2) + " V" : "—")
                  + "   LAST SNR " + (root.client.node.radio && root.client.node.radio.last_snr !== undefined ? root.client.node.radio.last_snr + " dB" : "—")
                  + "   CONTACTS " + (root.client.node.contact_count !== undefined ? root.client.node.contact_count : "—") + "   |   AI " + root.client.ai
            color: root.theme.muted; font.family: "monospace"; font.pixelSize: 11
        }
    }
}
