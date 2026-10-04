#!/usr/bin/env bash
# Retain user configuration and message history.
set -euo pipefail
systemctl --user disable --now meshcore-bridge.service
rm -f -- "$HOME/.config/systemd/user/meshcore-bridge.service"
systemctl --user daemon-reload
rm -rf -- "$HOME/.local/share/meshcore-bridge/.venv"
printf '%s\n' 'Bridge removed. Your config, history, favourites, and AI preferences have been retained.'
