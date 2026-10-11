pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Popup {
    id: root
    property var theme
    required property var client
    property var state: ({})
    property string feedback: ""
    property bool loaded: false
    property var selectedChannels: []
    function begin() { loaded=false; feedback=""; open(); run("get") }
    function run(action, data) { let value=data || {}; value.action=action; feedback=""; client.request("ai_settings","",undefined,value) }
    function save() {
        let values={enabled:enabledCheck.checked,conversation_memory:memoryCheck.checked}
        for(let i=0;i<fields.count;i++) { const field=fields.itemAt(i) as SettingField; values[field.modelData.key]=field.value }
        values.private_channels = selectedChannels
        run("save",values)
    }
    anchors.centerIn: parent
    width: Math.min(550,parent.width-24); height: Math.min(740,parent.height-24)
    modal: true; focus: true; padding: 18
    closePolicy: client.aiPending ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color:root.theme.surface; border.color:root.theme.border; radius:8 }
    Connections {
        target: root.client
        function onAiResult(result) {
            if(!root.visible)return
            if(!result.ok) { root.feedback=result.error; return }
            root.state=result.ai_result; root.loaded=true
            enabledCheck.checked=root.state.enabled
            memoryCheck.checked=root.state.conversation_memory !== false
            root.selectedChannels=(root.state.channels || []).slice()
            serverAddress.text=root.state.endpoint || "http://127.0.0.1:1234"
            provider.currentIndex=root.state.provider === "ollama" ? 1 : 0
            context.text=root.state.context ? String(root.state.context) : ""
            for(let i=0;i<fields.count;i++) { const field=fields.itemAt(i) as SettingField; field.value=String(root.state[field.modelData.key]) }
            models.currentIndex=(root.state.models || []).findIndex(m=>m.key===(root.state.model_key || root.state.model))
            root.feedback=root.state.warning || "Settings loaded."
        }
    }
    ColumnLayout {
        anchors.fill:parent; spacing:10
        Label { text:"Local AI Settings"; color:root.theme.foreground; font.pixelSize:20 }
        ScrollView {
            Layout.fillWidth:true; Layout.fillHeight:true; contentWidth:availableWidth
            ColumnLayout {
                width:parent.width; spacing:10
                CheckBox { id:enabledCheck; text:"Enable private-channel AI replies"; enabled:root.loaded && !root.client.aiPending }
                CheckBox { id:memoryCheck; text:"Remember conversations"; palette.windowText:root.theme.foreground; enabled:root.loaded && !root.client.aiPending }
                Label { text:"Recent exchanges are remembered separately by channel and sender name. Send @ai reset to clear your conversation. Turning memory off skips history; it does not erase it."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                Label { text:"Allowed private AI channels"; color:root.theme.foreground; font.bold:true; Layout.fillWidth:true }
                Label { text:(root.state.channels || []).length ? root.state.channels.join("\n") : "No channels allowed"; textFormat:Text.PlainText; color:(root.state.channels || []).length ? root.theme.foreground : root.theme.warning; wrapMode:Text.Wrap; Layout.fillWidth:true }
                Label { text:"Select private channels below, then Save preferences to allow AI replies there."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                Repeater {
                    model: Array.from(new Set((root.state.available_channels || []).concat(root.state.channels || [])))
                    CheckBox {
                        id: choice
                        required property string modelData
                        text: modelData
                        checked: root.selectedChannels.indexOf(modelData) !== -1
                        enabled:root.loaded && !root.client.aiPending
                        contentItem: Text { text:choice.text; color:root.theme.foreground; font:choice.font; leftPadding:choice.indicator.width + choice.spacing; verticalAlignment:Text.AlignVCenter }
                        onToggled: {
                            const names=root.selectedChannels.filter(n => n !== modelData)
                            if (checked) names.push(modelData)
                            root.selectedChannels=names
                        }
                    }
                }
                Label { visible:!(root.state.available_channels || []).length; text:"No private channels found on this node. Create or join a private channel, then Refresh."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                Label { visible:JSON.stringify(root.selectedChannels) !== JSON.stringify(root.state.channels || []); text:"Unsaved selection — click Save preferences to apply."; color:root.theme.warning; wrapMode:Text.Wrap; Layout.fillWidth:true }
                Label { text:"Model server"; color:root.theme.foreground }
                Label { text:"For model selection and context commands, start LM Studio's local server and enter the address it displays (usually http://127.0.0.1:1234). Use the base address without /v1."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                ComboBox { id:provider; model:["LM Studio / OpenAI-compatible", "Ollama (replies only)"]; Layout.fillWidth:true; enabled:root.loaded && !root.client.aiPending }
                TextField { id:serverAddress; placeholderText:"http://127.0.0.1:1234"; Layout.fillWidth:true; enabled:root.loaded && !root.client.aiPending }
                Button { text:root.client.aiPending ? "Checking…" : "Save server & check"; enabled:root.loaded && !root.client.aiPending; onClicked:root.run("server",{endpoint:serverAddress.text,provider:provider.currentIndex === 0 ? "openai" : "ollama"}) }
                Label { text:"Selected model: "+(root.state.model || "—"); color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                ComboBox { id:models; model:root.state.models || []; textRole:"name"; Layout.fillWidth:true; enabled:!root.client.aiPending }
                Button { text:"Use selected model"; enabled:root.loaded && models.currentIndex>=0 && !root.client.aiPending; onClicked:root.run("model",{model:root.state.models[models.currentIndex].key}) }
                Label { text:"Active context: "+(root.state.context || "not loaded")+" tokens\nModel maximum: "+(root.state.max_context || "unknown"); color:root.theme.muted; Layout.fillWidth:true }
                RowLayout {
                    TextField { id:context; placeholderText:"Context, e.g. 128k"; Layout.fillWidth:true; enabled:!root.client.aiPending }
                    Button { text:"Apply context"; enabled:root.loaded && !!root.state.context && !root.client.aiPending; onClicked:root.run("context",{context:context.text}) }
                }
                Label { text:"Changing context may reload the model. Memory uses a bounded recent history, not the entire context window."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
                component SettingField: ColumnLayout {
                    required property var modelData
                    property alias value:input.text
                    Layout.fillWidth:true
                    Label { text:parent.modelData.label; color:root.theme.muted }
                    TextField { id:input; Layout.fillWidth:true; enabled:root.loaded && !root.client.aiPending; selectByMouse:true }
                }
                Repeater {
                    id:fields
                    model:[{key:"max_input_chars",label:"Maximum question characters (32–2000)"},{key:"max_output_chars",label:"Maximum answer characters (32–1600)"},{key:"max_output_tokens",label:"Generation token limit (64–4096)"},{key:"per_sender_seconds",label:"Channel cooldown in seconds (0 disables)"},{key:"global_seconds",label:"Global cooldown in seconds (0 disables)"},{key:"timeout_seconds",label:"Response timeout in seconds (10–300)"}]
                    delegate:SettingField {}
                }
                Label { text:"Long answers use numbered radio messages. Model and context buttons apply immediately; Save applies the preferences below them."; color:root.theme.muted; wrapMode:Text.Wrap; Layout.fillWidth:true }
            }
        }
        Label { text:root.client.aiPending ? "Working…" : root.feedback; color:root.theme.warning; wrapMode:Text.Wrap; Layout.fillWidth:true }
        RowLayout {
            Button { text:"Close"; enabled:!root.client.aiPending; onClicked:root.close() }
            Button { text:"Refresh"; enabled:!root.client.aiPending; onClicked:root.run("get") }
            Button { text:"Save preferences"; enabled:root.loaded && !root.client.aiPending; onClicked:root.save() }
        }
    }
}
