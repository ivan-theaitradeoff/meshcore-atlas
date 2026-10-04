# Meshcore Atlas for Omarchy

MeshCore messaging, node maps, and private access to local AI from your desktop bar.

**Early release · 0.2.1** — tested with Bluetooth companion hardware on Omarchy Quattro. USB transport is implemented but has not been hardware-tested. This is an independent project, not an official MeshCore client.

## Features

- Taskbar icon opens or focuses one app window; remembers the last conversation.
- Public/private/hashtag channels, direct messages, favourites, and local message history.
- Channel creation, QR image import and sharing, notification preferences and retention.
- Message copy/reply/block/delete actions and available signal/path metadata.
- Live heard-repeat counts for new outgoing channel messages.
- Node details and editable node/radio settings.
- Online OpenStreetMap with search, repeater filtering, clustering and saved view.
- Optional private-channel local AI, numbered multipart messages, and a settings popup.
- LM Studio model selection and context control from the desktop or another mesh node.

## Requirements

Omarchy Quattro with the Quickshell plugin API, Python 3.11+, Quickshell, Qt Quick Controls, Qt Location and Qt Positioning. On Omarchy, install missing map/QR/notification utilities with:

```sh
omarchy pkg add qt6-location qrencode zbar libnotify
```

Use a node running MeshCore **companion firmware**. Bluetooth requires working BlueZ and a paired node; serial requires permission to access its device. The optional Python radio dependency is pinned to the tested `meshcore==2.3.14` API. The bridge and UI are separate processes.

## Install and connect in the app

Install the plugin through Omarchy's plugin manager and click its taskbar icon.
On first launch, **Connect a node** opens automatically. Existing users can open it through the node-name **⋮ → Connection setup** menu.

1. The first-run popup explains how to prepare the node: first set it up with the MeshCore phone app, disconnect it in that app, then forget/unpair the node in the phone’s Bluetooth settings. Keep it powered on nearby and disconnect any other apps using it. Choose **Set up Mesh Atlas** to install missing components through a desktop authorization prompt; downloads need internet access.
2. Choose **Find my node**, then Bluetooth or USB serial. Select a discovered node. USB requires a data cable and serial permissions for your desktop user.
3. Enter the current six-digit PIN for an unpaired Bluetooth node, choose whether to allow radio sending, and click **Connect**. Pairing and connection run in sequence. The PIN travels through a local process pipe and is never saved in config or command arguments.
4. Click **Start messaging** when connected. The saved connection is used on future launches; setup is also available from **⋮ → Connection setup**.
5. If an old pairing will not connect, disconnect other apps, restart the node, enter its current PIN, and choose **Repair pairing**. This replaces only the selected node's Bluetooth bond and reconnects it.
6. **Troubleshooting** includes connection checks and component repair. Configuration repair backs up existing settings before restoring safe defaults.

The popup loads without Qt Location installed. The messaging/map view loads separately. The setup UI/helper boundary has been checked on ARM64; the guided repair action should also be verified with a node that needs re-pairing before release.

The scripts in `scripts/` remain available for advanced/manual installation. They preserve existing configuration and do not enable AI or transmissions automatically.

### Try without hardware

From a source checkout, use two terminals:

```sh
python3 -m meshcore_bridge.daemon --config config.example.toml --demo
```

```sh
quickshell -p Preview.qml
```

Demo mode uses a separate history database and never transmits RF. Stop any live bridge first because the socket is shared. Close the window and stop the demo daemon when finished.

## Local AI

AI is disabled by default. Run your model server separately and bind it to loopback only. Click **Connect Local AI**, follow the guide, and configure the server in **Local AI Settings**. Supported server settings:

- LM Studio: `provider = "openai"`, `endpoint = "http://127.0.0.1:1234"`.
- Ollama: `provider = "ollama"`, `endpoint = "http://127.0.0.1:11434"`.
- llama.cpp or another compatible server: `provider = "openai"` and its loopback base URL, without `/v1`.
- Set `model` to an installed model, `private_channels = ["your-private-channel"]`, and `enabled = true`. RF sending must also be enabled.

Only explicitly allowed private channels can invoke AI. Public/hashtag channels and direct messages are excluded. **Anyone with the private channel key can invoke AI and its model commands.** Channel display names are not authenticated sender identities; `sender_allowlist` is reserved and is not enforced for channel access.

Open the node-name **⋮ → Local AI Settings** to change reply enablement, message limits, cooldowns and timeout. Saved preferences override the corresponding TOML fields after restart. Endpoint and allowed channels can be configured in this settings popup. Model listing/loading and context controls use LM Studio's native API; other providers support inference but not these management controls.

From another node in the allowed private channel:

| Message | Action |
| --- | --- |
| `/commands` | List commands |
| `@ai models` | List available models (LM Studio) |
| `@ai use N` | Select/load numbered model (LM Studio) |
| `@ai status` | Report model, active context when available, and busy state |
| `@ai context 128k` | Request 131,072-token context (LM Studio; model/memory permitting) |
| `@ai reset` | Clear your conversation memory |

After a successful model selection, ordinary messages in the allowed channel become prompts. Remember conversations is enabled by default. Recent exchanges are stored locally per channel and sender display name. Use `@ai reset` to clear your conversation memory; disabling the toggle skips stored memory without erasing it. Display names are not authenticated identities. Context capacity is not a count of conversation tokens used. Model changes may use substantial memory; context changes unload/reload the selected instance and attempt rollback on failure.

Long replies are split into at most 12 numbered, UTF-8-safe packets, ten seconds apart. Longer questions can be sent as `1/2 first part`, then `2/2 second part`. Missing parts expire after five minutes; there is no automatic retransmission. Only one multipart question per channel/display-name pair is supported. Input/output bounds and one active AI operation limit resource use. No model tools or arbitrary shell execution are provided.

## Data, network and limitations

- Bluetooth messaging and LM Studio inference have been exercised with real hardware. Other firmware/server combinations may differ.
- Heard repeats are received copies, **not recipient acknowledgements or unique repeater counts**. Tracking the last 100 sends is held in memory; saved counts survive restart, active tracking does not.
- Signal and path fields appear only when supplied by the node/library. Old messages cannot be backfilled.
- The UI displays the most recent 100 messages per conversation; older records remain subject to retention. History is plaintext, locally stored with owner-only permissions.
- Contacts and locations are advertised data and may be stale. Offline maps are not implemented. Opening Map fetches tiles from OpenStreetMap over HTTPS, exposing your IP and viewed map area to the tile service; node records are not uploaded. No bulk download or prefetch.
- Channel secrets are excluded from normal snapshots/logs, but explicitly shown by Share/Create actions. QR imports use local images or pasted links, not a camera.
- The bridge automatically retries after a radio disconnect. Keep the node powered on nearby; the app shows reconnecting while it waits.
- Node multi-field writes are not atomic: if a save fails, reopen settings to inspect which changes applied.
- Runtime socket: `$XDG_RUNTIME_DIR/meshcore-bridge/bridge.sock`, owner-only. History: `~/.local/state/meshcore-bridge/history.sqlite3`. Map/window preferences: `~/.config/mesh-atlas-*.ini`.
- The AI client accepts literal loopback HTTP endpoints only, refuses redirects and environment proxies, and does not start a network listener. The map is the UI's separate online feature.

Map data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Map usage follows the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/). No map tiles, mobile screenshots, or user conversations are distributed in the release.

## Update and removal

Update with `omarchy plugin update meshcore.atlas`, open Connection setup → Update / repair components, then Connect. Close and reopen the app. Existing config/history are retained.

To remove, close the app and run these **before** removing the plugin folder:

```sh
bash ~/.config/omarchy/plugins/meshcore.atlas/scripts/remove-bridge.sh
omarchy plugin remove meshcore.atlas
```

Removal stops/disables the service and deletes its dedicated Python environment. Configuration, history, favourites and model preferences remain on disk for recovery. Delete those explicitly only if you also want to erase personal data. The plugin does not uninstall system packages or your model server.

## Release contents

The distribution contains only explicitly listed runtime source files, generic defaults, documentation, and license. Development launchers, Git history, tests, credentials, screenshots, local configuration, databases, caches, and model files are excluded. See [release notes](docs/RELEASE.md). Licensed under MIT; dependencies retain their own licenses and are not bundled.

## Fresh-install defaults

AI replies are off until explicitly enabled for selected private channels. Defaults: 1,600 question characters, 1,600 answer characters, 1,024 generation tokens, zero channel/global cooldown, and a 120-second response timeout. No node address, pairing PIN, private channel, conversation, or model file is included.
