import QtQuick
import QtQuick.Controls
import Quickshell
import QtCore
ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 900; implicitHeight: 680
        title: "Mesh Atlas"
        Settings {
            id: savedState
            property bool setupCompleted: false
            location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/mesh-atlas-window.ini"
            category: "Conversation"
            property alias lastTarget: client.target
        }
        MeshClient { id: client }
        Rectangle {
            anchors.fill: parent; color: "#171e26"
            Label { anchors.centerIn: parent; text: "Mesh Atlas"; color: "#c7d3df"; font.pixelSize: 28 }
        }
        Loader {
            id: chat; anchors.fill: parent
            function openChat() {
                if (!item) setSource("MeshPanel.qml", {client:client, active:true, sidebarSection:client.target.indexOf("dm:") === 0 ? "contacts" : "channels"})
            }
        }
        Connections {
            target: chat.item; ignoreUnknownSignals: true
            function onConnectionRequested() { setup.step = 0; setup.note = ""; connectionDialog.open() }
        }
        Popup {
            id: connectionDialog
            anchors.centerIn: parent
            width: Math.min(620, window.width - 32)
            height: Math.min(620, window.height - 32)
            modal: true; focus: true; padding: 0
            closePolicy: Popup.NoAutoClose
            background: Rectangle { color: "#171e26"; border.color: "#586b80"; radius: 12 }
            contentItem: ConnectionSetup {
                id: setup; client: client
                onInitialized: function(configured) {
                    if (configured) savedState.setupCompleted = true
                    if (!configured && !savedState.setupCompleted) connectionDialog.open()
                    else { connectionDialog.close(); chat.openChat() }
                }
                onDone: { savedState.setupCompleted = true; chat.openChat(); connectionDialog.close() }
            }
            Button { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6; visible: !!chat.item; text: "×"; Accessible.name: "Close setup"; enabled: !setup.busy && !setup.connecting; onClicked: { connectionDialog.close(); if (setup.installed) chat.openChat() } }
        }
        Connections {
            target: client
            function onConnectionStateChanged() {
                if (client.connectionState.indexOf("connected") === 0 || client.connectionState.indexOf("demo") === 0) chat.openChat()
            }
        }
    }
}
