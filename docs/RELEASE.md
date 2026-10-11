# Meshcore Atlas 0.3.0

- Open messages and the map side by side. Toggle each view independently and resize the divider; drafts and the map view remain available when hidden.
- Follow the active Omarchy theme, including buttons, fields, and dialogs.
- Open or focus the app from generic desktop notifications without exposing message text or names.
- Suppress repeat deliveries of the same timestamped radio message in history, unread counts, notifications, and AI processing.
- Allow more time for large node directories to load and preserve the previous directory when a refresh fails.
- Improve map visibility with red, white-bordered markers, reliable two-axis dragging, and stable markers while panning.

## Updating

Update the plugin through Omarchy, then open **Connection setup → Update / repair components** to update the companion bridge. Reconnect and close/reopen the app. Existing settings and history are retained. Models are not changed.

## Packaging and privacy

The attached source-only ZIP is built from an explicit file list. It excludes runtime settings, databases, logs, screenshots, pairing credentials, channel keys, local model files, and development history. The GitHub repository retains the previously approved preview image unchanged; it is excluded from the ZIP.

USB remains implemented but not hardware-tested. Online maps need internet access. Radio delivery is not guaranteed.
