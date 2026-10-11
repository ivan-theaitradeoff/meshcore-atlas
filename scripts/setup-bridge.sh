#!/usr/bin/env bash
# Explicit companion installation. Never starts the radio or changes RF permission.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${XDG_CONFIG_HOME:-$HOME/.config} != "$HOME/.config" || ${XDG_DATA_HOME:-$HOME/.local/share} != "$HOME/.local/share" || ${XDG_STATE_HOME:-$HOME/.local/state} != "$HOME/.local/state" ]]; then
  echo 'The supplied service uses standard XDG directories; use manual installation for custom directories.' >&2
  exit 1
fi
umask 077
mkdir -p "$HOME/.local/share/meshcore-bridge" "$HOME/.config/meshcore-bridge" "$HOME/.local/state/meshcore-bridge" "$HOME/.config/systemd/user"
python3 -m venv "$HOME/.local/share/meshcore-bridge/.venv"
"$HOME/.local/share/meshcore-bridge/.venv/bin/python" -m pip install "$root[radio]"
if [[ ! -e "$HOME/.config/meshcore-bridge/config.toml" ]]; then
  cp "$root/config.example.toml" "$HOME/.config/meshcore-bridge/config.toml"
fi
chmod 600 "$HOME/.config/meshcore-bridge/config.toml"
unit="$HOME/.config/systemd/user/meshcore-bridge.service"
if [[ -e "$unit" ]]; then cp "$unit" "$unit.bak.$(date +%s)"; fi
cp "$root/systemd/meshcore-bridge.service" "$unit"
printf '%s\n' "$root" > "$HOME/.local/share/meshcore-bridge/app-path"
systemctl --user daemon-reload
printf '%s\n' 'Bridge installed, but not started. Configure ~/.config/meshcore-bridge/config.toml, then run:' 'systemctl --user enable --now meshcore-bridge'
