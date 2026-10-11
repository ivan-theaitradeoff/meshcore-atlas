pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

ListView {
    id: root
    property var theme
    required property var node
    property bool connected: false
    clip: true
    spacing: 1
    function value(section, key, unit) {
        const data = root.node[section] || {}
        return data[key] === undefined || data[key] === null ? "Unavailable" : String(data[key]) + (unit || "")
    }
    model: [
        ["Status", root.connected ? "Connected · local node reads" : "Disconnected · last known values"],
        ["Updated", root.node.updated_at ? new Date(root.node.updated_at * 1000).toLocaleTimeString() + " · refresh every 60 seconds" : "Waiting for node"],
        ["Name", value("identity", "name")],
        ["Hardware", value("device", "model")],
        ["Firmware", value("device", "ver") + " · " + value("device", "fw_build")],
        ["Transport", (root.node.transport || "—") + " · " + (root.node.device_address || "—")],
        ["Public identity key", value("identity", "public_key")],
        ["Frequency", value("identity", "radio_freq", " MHz")],
        ["Bandwidth", value("identity", "radio_bw", " kHz")],
        ["Spreading factor", value("identity", "radio_sf")],
        ["Coding rate setting", value("identity", "radio_cr")],
        ["Transmit power", value("identity", "tx_power", " dBm") + " / max " + value("identity", "max_tx_power", " dBm")],
        ["Battery voltage", value("battery", "level", " mV")],
        ["Storage", value("battery", "used_kb", " KB used") + " / " + value("battery", "total_kb", " KB")],
        ["Configured channels", String(root.node.channel_count ?? "—") + " / " + value("device", "max_channels")],
        ["Saved contacts", String(root.node.contact_count ?? "—") + " / " + value("device", "max_contacts")],
        ["Manual contact adding", value("identity", "manual_add_contacts")],
        ["Uptime", value("core", "uptime_secs", " seconds")],
        ["Transmit queue", value("core", "queue_len")],
        ["Core errors", value("core", "errors")],
        ["Last LoRa packet RSSI", root.node.packets && root.node.packets.recv === 0 ? "No packets received yet" : value("radio", "last_rssi", " dBm")],
        ["Last LoRa packet SNR", root.node.packets && root.node.packets.recv === 0 ? "No packets received yet" : value("radio", "last_snr", " dB")],
        ["Noise floor", value("radio", "noise_floor", " dBm")],
        ["Airtime TX / RX", value("radio", "tx_air_secs", " s") + " / " + value("radio", "rx_air_secs", " s")],
        ["Packets RX / TX", value("packets", "recv") + " / " + value("packets", "sent")],
        ["Flood RX / TX", value("packets", "flood_rx") + " / " + value("packets", "flood_tx")],
        ["Direct RX / TX", value("packets", "direct_rx") + " / " + value("packets", "direct_tx")],
        ["Receive errors", value("packets", "recv_errors")],
        ["Configured location", value("identity", "adv_lat") + ", " + value("identity", "adv_lon") + " (0,0 may be unset)"],
        ["Unavailable queries", (root.node.unavailable || []).join(", ") || "None"]
    ]
    delegate: Rectangle {
        id: row
        required property var modelData
        width: ListView.view.width
        height: Math.max(38, detail.implicitHeight + 16)
        color: root.theme.sidebar
        Text { x: 10; y: 8; width: 180; text: row.modelData[0]; color: root.theme.muted; font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Text { id: detail; x: 200; y: 8; width: Math.max(20, parent.width - 212); text: row.modelData[1]; color: root.theme.foreground; font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText }
    }
    ScrollBar.vertical: ScrollBar {}
}
