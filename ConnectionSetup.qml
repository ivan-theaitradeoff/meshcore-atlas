pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Rectangle {
    id: root
    required property var client
    signal done()
    signal initialized(bool configured)
    color: "#171e26"
    property bool busy: false
    property bool installed: false
    property var devices: []
    property string note: ""
    property var pending: ({})
    property bool failed: false
    property int step: 0
    property string action: ""
    property string nextAction: ""
    property bool selectedPaired: false
    property bool connecting: false
    property bool connected: client.connectionState.indexOf("connected") === 0
    function run(operation) {
        if (busy) return
        action = operation
        pending = {action:operation, transport:kind.currentIndex === 0 ? "ble" : "serial", device:address.text, pin:pin.text, allow_transmit:sending.checked}
        busy = true; failed = false
        note = operation === "scan" ? "Looking for nearby MeshCore nodes…" : operation === "install" ? "Preparing Mesh Atlas… Approve the desktop password prompt if shown. This may take a few minutes." : operation === "pair" || operation === "repair_pair" ? "Pairing with your node…" : operation === "connect" ? "Connecting to your node…" : "Checking…"
        worker.running = true
    }
    function connectNode() {
        connecting = true
        if (kind.currentIndex === 0 && pin.text.length === 6 && selectedPaired) run("repair_pair")
        else if (kind.currentIndex === 0 && !selectedPaired) run("pair")
        else run("connect")
    }
    Component.onCompleted: run("status")
    Connections {
        target: root.client
        function onConnectionStateChanged() {
            if (!root.connecting) return
            if (root.connected) { root.connecting = false; root.step = 3; root.note = "Your node is ready. Your connection will be remembered." }
            else if (root.client.connectionState.indexOf("failed") !== -1) { root.connecting = false; root.failed = true; root.note = "Could not connect. Disconnect the node from your phone, keep it nearby, and try again. If it was previously paired, use Repair pairing below." }
        }
    }
    Timer {
        interval: 55000; running: root.connecting; repeat: false
        onTriggered: { root.connecting = false; root.failed = true; root.note = "Connection timed out. Disconnect other apps, restart your node, and try Repair pairing with its current PIN." }
    }
    Process {
        id: worker
        command: ["python3", Qt.resolvedUrl("scripts/connection-setup.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.pending) + "\n"); root.pending = ({}); pin.clear() }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text)
                    root.failed = !r.ok
                    root.note = r.message || r.warning || ""
                    if (r.installed !== undefined) root.installed = r.installed
                    if (r.transport !== undefined) kind.currentIndex = r.transport === "serial" ? 1 : 0
                    if (r.device !== undefined) address.text = r.device
                    if (r.allow_transmit !== undefined) sending.checked = r.allow_transmit
                    if (r.devices !== undefined) root.devices = r.devices
                    if (!r.ok) { root.connecting = false; if (root.note.indexOf("Node not found") === 0) { root.step = 1; root.devices = []; root.selectedPaired = false } }
                    else if (root.action === "status") root.initialized(address.text.length > 0 && !r.warning)
                    else if (root.action === "install") { root.step = 1; root.nextAction = kind.currentIndex === 0 ? "scan" : "usb" }
                    else if (root.action === "pair" || root.action === "repair_pair") { root.selectedPaired = true; root.nextAction = "connect" }
                    else if (root.action === "connect") {
                        root.note = "Waiting for your node…"
                        if (root.connected) { root.step = 3; root.connecting = false; root.note = "Your node is ready. Your connection will be remembered." }
                    } else if ((root.action === "scan" || root.action === "usb") && root.devices.length === 0) root.note = "No nodes found. Check the tips below, then search again."
                } catch (e) { root.failed = true; root.connecting = false; root.note = "Setup did not return a result. Please try again." }
            }
        }
        onExited: { root.busy = false; if (root.nextAction) { const a = root.nextAction; root.nextAction = ""; Qt.callLater(function() { root.run(a) }) } }
    }
    ScrollView {
        anchors.fill: parent; anchors.margins: 20
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width; spacing: 14
            Label { text: root.step === 3 ? "You're connected" : ["1 · Get ready", "2 · Choose your node", "3 · Connect"][root.step]; font.pixelSize: 22; color: "#c7d3df" }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#bdd0e5"
                text: root.step === 0 ? "Connect your MeshCore node to start messaging. Setup takes place here in the app." : root.step === 1 ? "Choose Bluetooth or plug in a USB data cable, then select your node." : root.step === 2 ? "Enter the PIN displayed on your node if it needs pairing. Mesh Atlas remembers the connection, but never saves your PIN." : "You can change or repair your connection anytime from the menu beside your node name."
            }
            Label {
                visible: root.step < 3; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#9db2c6"
                text: "Before connecting\n1. First set up your node on your phone using the MeshCore app.\n2. Disconnect the node in the MeshCore phone app. Then open your phone's Bluetooth settings and forget this node (Forget This Device / Unpair).\n3. Keep the node powered on and close to this computer. Disconnect any other apps using it.\n4. For Bluetooth, have the node's current pairing PIN ready. For USB, use a cable that supports data."
            }
            ComboBox { id: kind; visible: root.step === 1; model: ["Bluetooth", "USB serial"]; enabled: !root.busy; onActivated: { root.devices = []; address.clear(); root.selectedPaired = false; root.run(currentIndex === 0 ? "scan" : "usb") } }
            Button { visible: root.step === 1; text: "Search again"; enabled: !root.busy; onClicked: root.run(kind.currentIndex === 0 ? "scan" : "usb") }
            Repeater {
                model: root.step === 1 ? root.devices : []
                Button {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name + (modelData.paired ? " · paired" : "")
                    enabled: !root.busy
                    onClicked: { address.text = modelData.device; root.selectedPaired = !!modelData.paired; root.step = 2; root.note = "" }
                }
            }
            TextField { id: address; visible: root.step === 2; Layout.fillWidth: true; readOnly: true; Accessible.name: "Selected node" }
            TextField { id: pin; visible: root.step === 2 && kind.currentIndex === 0; Layout.fillWidth: true; placeholderText: root.selectedPaired ? "Current PIN to refresh the saved pairing" : "Six-digit PIN shown on your node"; echoMode: TextInput.Password; maximumLength: 6; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ } }
            CheckBox { id: sending; visible: root.step === 2; text: "Allow sending messages over radio"; contentItem: Text { text: sending.text; font: sending.font; color: "#c7d3df"; opacity: sending.enabled ? 1 : 0.6; leftPadding: sending.indicator.width + sending.spacing; verticalAlignment: Text.AlignVCenter } enabled: !root.busy && !root.connecting }
            Label { visible: root.note.length > 0; Layout.fillWidth: true; text: root.note; wrapMode: Text.WordWrap; color: root.failed ? "#ef9b91" : "#bdd0e5" }
            BusyIndicator { running: root.busy || root.connecting; visible: running; Layout.preferredHeight: 30 }
            RowLayout {
                Button { text: "Back"; visible: root.step > 0 && root.step < 3; enabled: !root.busy && !root.connecting; onClicked: { root.step--; root.note = "" } }
                Button { visible: root.step === 0; text: root.installed ? "Find my node" : "Set up Mesh Atlas"; enabled: !root.busy; onClicked: { if (!root.installed) root.run("install"); else { root.step = 1; root.run(kind.currentIndex === 0 ? "scan" : "usb") } } }
                Button { visible: root.step === 2; text: "Connect"; enabled: !root.busy && !root.connecting && (kind.currentIndex === 1 || root.selectedPaired || pin.acceptableInput && pin.text.length === 6); onClicked: root.connectNode() }
                Button { visible: root.step === 3; text: "Start messaging"; enabled: !root.busy; onClicked: root.done() }
            }
            Label { visible: root.step === 2 && kind.currentIndex === 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#9db2c6"; text: "Already paired but won't connect? Restart the node and enter its current PIN, then repair the pairing. This replaces only this node's saved Bluetooth pairing." }
            Button { visible: root.step === 2 && kind.currentIndex === 0; text: "Repair pairing"; enabled: !root.busy && !root.connecting && pin.text.length === 6; onClicked: { root.connecting = true; root.run("repair_pair") } }
            Button { text: advanced.visible ? "Hide troubleshooting" : "Troubleshooting"; visible: root.step < 3; onClicked: advanced.visible = !advanced.visible }
            ColumnLayout {
                id: advanced; visible: false; Layout.fillWidth: true
                Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#9db2c6"; text: "No node listed? Check its power and Bluetooth, disconnect other apps, and search again.\nPIN rejected? Use the current PIN on the node; it may change after a restart.\nStill stuck? Try USB with a data cable, or check the connection below." }
                Button { text: "Check connection"; enabled: !root.busy; onClicked: root.run("diagnose") }
                Button { text: "Update / repair components"; enabled: !root.busy && !root.connecting; onClicked: root.run("install") }
                Button { text: "Repair configuration"; enabled: !root.busy && !root.connecting; onClicked: repair.open() }
            }
        }
    }
    Dialog {
        id: repair; anchors.centerIn: parent; title: "Restore safe defaults?"; modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Your current configuration will be backed up.\nAI and sending will be disabled in the new configuration." }
        onAccepted: root.run("repair")
    }
}
