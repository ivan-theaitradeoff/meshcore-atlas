"""Explicit allowlist: device responses can contain PINs and channel secrets."""
FIELDS = {
    'identity': ('name', 'public_key', 'adv_type', 'adv_lat', 'adv_lon', 'tx_power', 'max_tx_power',
                 'radio_freq', 'radio_bw', 'radio_sf', 'radio_cr', 'manual_add_contacts', 'adv_loc_policy'),
    'device': ('model', 'ver', 'fw_build', 'fw ver', 'max_contacts', 'max_channels'),
    'battery': ('level', 'used_kb', 'total_kb'),
    'core': ('uptime_secs', 'battery_mv', 'errors', 'queue_len'),
    'radio': ('noise_floor', 'last_rssi', 'last_snr', 'tx_air_secs', 'rx_air_secs'),
    'packets': ('recv', 'sent', 'flood_tx', 'direct_tx', 'flood_rx', 'direct_rx', 'recv_errors'),
}


def sanitize(section, payload):
    return {key: value for key in FIELDS[section]
            if isinstance((value := payload.get(key)), (str, int, float, bool))}
