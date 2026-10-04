import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    signal createChannel()
    signal openSettings()
    anchors.centerIn: parent
    width: Math.min(620, parent.width - 24)
    height: Math.min(700, parent.height - 24)
    modal: true; focus: true; padding: 20
    background: Rectangle { color: "#202a36"; border.color: "#647184"; radius: 10 }
    ColumnLayout {
        anchors.fill: parent; spacing: 14
        RowLayout {
            Label { text: "Connect Local AI"; font.pixelSize: 22; color: "#c7d3df"; Layout.fillWidth: true }
            Button { text: "×"; Accessible.name: "Close Local AI guide"; onClicked: root.close() }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
            ColumnLayout {
                width: parent.width; spacing: 16
                Repeater {
                    model: [
                        {heading:"1 · Prepare your nodes", body:"Keep one MeshCore node connected to the computer running Mesh Atlas and your local model. Use a separate personal node with the MeshCore app on your phone. Keep the computer awake and its model server running."},
                        {heading:"2 · Plan your radio connection", body:"For longer range, use a compatible MeshCore repeater with you or at a high, open location with good visibility. A repeater is optional when the two nodes can communicate directly. Check that the nodes and repeater use compatible radio settings."},
                        {heading:"3 · Prepare your local model", body:"The model listing, selection and context commands use LM Studio. Download a model in LM Studio, then start its local server. Keep LM Studio running.\n\nIn Mesh Atlas, open Local AI Settings below:\n1. Select LM Studio / OpenAI-compatible.\n2. Enter the server address displayed by LM Studio (usually http://127.0.0.1:1234), without /v1.\n3. Click Save server & check. If the model list stays empty, check the address and that the server is running.\n4. Choose a model and click Use selected model. Wait for it to load.\n5. If desired, enter a context size such as 128k and click Apply context. The model must support that size.\n6. Set your reply preferences and click Save preferences.\n\nOther compatible servers may support replies without supporting model selection or context commands."},
                        {heading:"4 · Create a private channel", body:"On this computer, choose Create private channel below. Pick any name, such as localai. Save the generated private key. On your phone, choose Add Channel → Join a Private Channel and enter exactly the same name and key. Anyone with that key can join, so share it only with intended users."},
                        {heading:"5 · Enable AI for that channel", body:"Open Local AI Settings. Select your channel under Allowed private AI channels, check Enable private-channel AI replies, and click Save preferences. The saved channel will appear in the Allowed section; an empty section means no channels can receive AI replies. Radio message sending must also be enabled in Connection setup. AI replies are restricted to allowed private channels; Public and direct messages do not activate AI."},
                        {heading:"6 · Test from your phone", body:"In the matching private channel, send /commands, then @ai models. Choose a listed model with @ai use N, replacing N with its number. Wait for Ready, then send a short ordinary message, such as Say hello. The reply should arrive on your phone; longer replies can arrive in multiple messages."},
                        {heading:"Available commands", body:"/commands — list commands\n@ai models — list local models\n@ai use N — select/load model N\n@ai status — selected model, configured context size, and busy/ready\n@ai context 128k — request 131,072 tokens of context, if the model supports it\n\nAfter selecting a model, ordinary messages go to it automatically. Status reports context capacity, not tokens currently used. When Remember conversations is enabled, recent exchanges are included separately for each channel and sender name. Send @ai reset to clear your conversation. Sender names are not authenticated; people using the same name share that memory."},
                        {heading:"No reply?", body:"Check that both nodes use the same private channel name and key, the host computer is awake, the model server is running, and AI and radio sending are enabled. Try the nodes close together first before testing through a repeater. Each node should stay connected to its own computer or phone, not both."}
                    ]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 6
                        Label { text: parent.modelData.heading; color: "#c7d3df"; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        Label { text: parent.modelData.body; color: "#c7d3df"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
        RowLayout {
            Button { text: "Create private channel"; onClicked: { root.close(); root.createChannel() } }
            Button { text: "Local AI Settings"; onClicked: { root.close(); root.openSettings() } }
        }
    }
}
