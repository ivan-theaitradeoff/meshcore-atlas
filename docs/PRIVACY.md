# Privacy and permissions

Meshcore Atlas connects a local MeshCore radio to a desktop interface and, optionally, a local language-model server. It does not include a cloud AI service, analytics, or an account system.

## Installation and permissions

Setup runs only when requested in the app. It can:

- Install missing `qt6-location`, `qrencode`, `zbar`, and `libnotify` system packages through a desktop authorization prompt.
- Create a dedicated Python environment under `~/.local/share/meshcore-bridge/` and install the bridge plus its radio dependencies from Python package sources. The direct radio dependency is pinned to `meshcore==2.3.14`; transitive dependencies are not all pinned.
- Create and manage the **user** service `meshcore-bridge.service`. Connecting enables it for subsequent user sessions; Disconnect stops it.
- Discover and pair Bluetooth devices through BlueZ. Repair pairing replaces only the selected device's saved bond. The entered PIN is passed through a local process pipe, not stored in configuration or command arguments. BlueZ manages its own pairing credentials.
- Read/write the selected node's channels and settings when the user invokes those actions. Radio sending is off in the distributed defaults and can be enabled during setup.

The service uses an owner-only Unix socket and restrictive file creation permissions. Service sandboxing adds restrictions where supported by the host; it is not a guarantee against all vulnerabilities. Setup and the desktop interface run with the user's privileges.

## Stored data

| Location | Contents |
| --- | --- |
| `~/.config/meshcore-bridge/` | Connection/AI configuration and any configuration-repair backups |
| `~/.local/state/meshcore-bridge/` | Message history, conversation memory, preferences, and local model-selection records |
| `~/.local/share/meshcore-bridge/` | Installed Python environment |
| `~/.config/mesh-atlas-window.ini` | First-run and last-conversation preferences |
| `~/.config/mesh-atlas-map.ini` | Last map position and zoom |
| `$XDG_RUNTIME_DIR/meshcore-bridge/` | Local socket and process lock |
| `$XDG_RUNTIME_DIR/mesh-atlas-window.log` | Desktop runtime diagnostics |

History and AI memory are plaintext, not an encrypted vault. Qt may cache map tiles. BlueZ and system logs are managed by the operating system separately. Uninstall retains configuration/history unless explicitly erased. Models are managed by your model server and are never bundled with this plugin.

## Network activity

- Radio communication uses the chosen Bluetooth or USB companion connection.
- AI HTTP requests are restricted to literal loopback IP addresses. The gateway disables environment proxies and HTTP redirects. Prompts and recent remembered exchanges are passed to your local model server; its own privacy settings are outside this plugin's control.
- Online maps request OpenStreetMap tiles. The tile provider can see your IP and requested area; the app does not upload its contact directory to that provider.
- Installing components downloads system/Python packages from their configured repositories.

## Private channels and memory

Anyone with a private channel key can read that channel and invoke AI if it is allowed. Sender display names are not authenticated identities. Two senders using the same name in one channel may share the same memory context. Model commands can load/unload models and change context size; allow only channels whose members you trust.

AI has no plugin-provided shell tools or filesystem-reading tools. Responses may be wrong. Public/hashtag channels and direct messages are excluded from AI replies.

## Reporting issues safely

Do not post channel keys, pairing PINs, model-server secrets, real message history, node addresses, or personal location data in public issues. Use fictional examples and redact screenshots before uploading. This repository has no private vulnerability-reporting address configured; do not attach sensitive details to public reports.

The public GitHub repository and release identify their GitHub owner. The plugin's author/namespace metadata uses the project identity, and the published source does not include the development machine's private runtime data.
