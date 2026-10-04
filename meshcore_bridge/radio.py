"""USB/BLE companion adapter. No advertisements, discovery, or remote commands."""
import asyncio
import time
import hashlib
from .node_info import sanitize
from .bluetooth import known_device
from .channels import prepare, ChannelError, PUBLIC_KEY


class Radio:
    def __init__(self, config, receive):
        self.config, self.receive = config, receive
        self.client = None
        self.channels = []
        self.contacts = {}
        self.private_channels = set()
        self.state = "disconnected"
        self.node = {}
        self.refresh_task = None
        self.channel_lock = asyncio.Lock()
        self.sent_packets = []
        self.repeat_callback = None

    async def connect(self):
        c = self.config
        if c["transport"] == "demo":
            self.state = "demo · no RF"
            self.channels = [{"id": "ch:0", "name": "# Public · demo"},
                             {"id": "ch:1", "name": "# Private · demo"}]
            return
        if c["transport"] not in ("serial", "ble"):
            raise ValueError("Only serial, ble and demo transports are supported")
        if not c["device"]:
            return
        from meshcore import MeshCore, EventType
        if c["transport"] == "ble":
            device = await known_device(c["device"])
            self.client = await MeshCore.create_ble(c["device"], device=device, auto_reconnect=False) if device else await MeshCore.create_ble(c["device"], auto_reconnect=False)
        else:
            self.client = await MeshCore.create_serial(c["device"], c["baud"])
        if self.client is None:
            raise RuntimeError("Companion handshake failed")
        self.client.set_decrypt_channel_logs(True)
        await self.refresh_info()
        await self.refresh_directory()
        async def incoming(event):
            p = event.payload
            metadata = {key: p[key] for key in ('sender_timestamp', 'SNR', 'RSSI', 'path_len', 'path_hash_mode')
                        if key in p and isinstance(p[key], (int, float))}
            if isinstance(p.get('path'), (str, list)):
                metadata['path'] = p['path'] if isinstance(p['path'], str) else [x.hex() if isinstance(x, bytes) else str(x) for x in p['path']]
            if event.type == EventType.CHANNEL_MSG_RECV:
                await self.receive(f"ch:{p['channel_idx']}", "channel peer", p.get("text", ""), False, metadata)
            else:
                prefix = p.get("pubkey_prefix", "")
                if isinstance(prefix, bytes):
                    prefix = prefix.hex()
                matches = [key for key in self.contacts if key.startswith(prefix)] if prefix else []
                sender = matches[0] if len(matches) == 1 else "unknown"
                await self.receive(f"dm:{sender}", sender, p.get("text", ""), True, metadata)
        async def heard_repeat(event):
            p = event.payload
            for packet in self.sent_packets:
                if (p.get('chan_name') == packet['channel_name'] and p.get('sender_timestamp') == packet['sender_timestamp']
                        and p.get('message') == packet['wire_text']):
                    packet['repeats'] += 1
                    if self.repeat_callback:
                        self.repeat_callback(packet)
                    break
        self.client.subscribe(EventType.RX_LOG_DATA, heard_repeat)
        self.client.subscribe(EventType.CHANNEL_MSG_RECV, incoming)
        self.client.subscribe(EventType.CONTACT_MSG_RECV, incoming)
        await self.client.start_auto_message_fetching()
        self.state = "connected · " + ("Bluetooth" if c["transport"] == "ble" else "USB")
        self.refresh_task = asyncio.create_task(self.refresh_loop())

    async def refresh_directory(self):
        from meshcore import EventType
        slots = self.node.get("device", {}).get("max_channels", self.config["channel_slots"])
        channels = []
        private_channels = set()
        for index in range(max(0, min(int(slots), 256))):
            event = await self.client.commands.get_channel(index)
            if event.type != EventType.ERROR and event.payload.get("channel_name"):
                name = event.payload["channel_name"]
                key = event.payload.get("channel_secret", b"")
                channels.append({"id": f"ch:{index}", "name": name})
                if len(key) == 16 and key not in (PUBLIC_KEY, bytes(16), hashlib.sha256(name.encode()).digest()[:16]) and not name.startswith('#'):
                    private_channels.add(f"ch:{index}")
        result = await self.client.commands.get_contacts()
        if result.type != EventType.ERROR:
            self.contacts = result.payload
        channels.extend({"id": f"dm:{key}", "name": "DM · " + value.get("adv_name", key[:12])}
                        for key, value in self.contacts.items())
        self.private_channels = private_channels
        self.channels = channels
        self.node["channel_count"] = sum(c["id"].startswith("ch:") for c in channels)
        self.node["contact_count"] = len(self.contacts)

    async def refresh_info(self):
        from meshcore import EventType
        self.node['identity'] = sanitize('identity', getattr(self.client, 'self_info', {}))
        unavailable = []
        for section, method in [('device', 'send_device_query'), ('battery', 'get_bat'),
                                ('core', 'get_stats_core'), ('radio', 'get_stats_radio'),
                                ('packets', 'get_stats_packets')]:
            try:
                result = await asyncio.wait_for(getattr(self.client.commands, method)(), 3)
                if result.type == EventType.ERROR:
                    raise ValueError('Unsupported query')
                self.node[section] = sanitize(section, result.payload)
            except (AttributeError, TimeoutError, ValueError, ConnectionError):
                self.node[section] = {}
                unavailable.append(section)
        if self.node.get('packets', {}).get('recv') == 0:
            # Firmware may return placeholder signal numbers before any packet arrives.
            self.node.get('radio', {}).pop('last_rssi', None)
            self.node.get('radio', {}).pop('last_snr', None)
        self.node['unavailable'] = unavailable
        self.node['updated_at'] = int(time.time())
        self.node['transport'] = self.config['transport']
        self.node['device_address'] = self.config['device']

    async def refresh_loop(self):
        while True:
            await asyncio.sleep(60)
            if not self.client.is_connected:
                continue
            try:
                await self.refresh_info()
                await self.refresh_directory()
            except Exception:
                self.node['unavailable'] = ['refresh failed; showing last known data']

    async def add_channel(self, data):
        name, key, created = await prepare(data)
        async with self.channel_lock:
            if self.config['transport'] == 'demo':
                index = len([c for c in self.channels if c['id'].startswith('ch:')])
                target = f'ch:{index}'
                self.channels.append({'id': target, 'name': name})
            else:
                if not self.client or not self.client.is_connected:
                    raise ChannelError('Connect the node before adding a channel.')
                from meshcore import EventType
                slots = self.node.get('device', {}).get('max_channels', self.config['channel_slots'])
                empty = None
                for index in range(min(int(slots), 256)):
                    event = await self.client.commands.get_channel(index)
                    if event.type == EventType.ERROR:
                        raise ChannelError('Could not verify channel slots. No changes made.')
                    payload = event.payload
                    if payload.get('channel_name') and payload.get('channel_secret') == key:
                        return {'target': f'ch:{index}', 'name': payload['channel_name'], 'existing': True}
                    if not payload.get('channel_name') and payload.get('channel_secret') == bytes(16) and empty is None:
                        empty = index
                if empty is None:
                    raise ChannelError('No empty channel slot is available. Existing channels were preserved.')
                result = await self.client.commands.set_channel(empty, name, key)
                if result.type == EventType.ERROR:
                    raise ChannelError('The node rejected the channel settings.')
                check = await self.client.commands.get_channel(empty)
                if check.type == EventType.ERROR or check.payload.get('channel_name') != name or check.payload.get('channel_secret') != key:
                    raise ChannelError('Could not verify the saved channel. Inspect the node before retrying.')
                await self.refresh_directory()
                target = f'ch:{empty}'
            result = {'target': target, 'name': name, 'existing': False}
            if created:
                result['share_key'] = key.hex()
            return result

    async def send(self, target, text, metadata=None):
        if target not in {c["id"] for c in self.channels}:
            raise ValueError("Unknown channel or contact")
        if not text.strip() or len(text.encode()) > self.config["max_message_bytes"]:
            raise ValueError("Message empty or exceeds radio byte limit")
        if self.config["transport"] == "demo":
            return "demo only"
        if not self.config["allow_transmit"]:
            raise ValueError("RF transmission is locked in configuration")
        if not self.client or not self.client.is_connected:
            raise ValueError("Radio disconnected")
        from meshcore import EventType
        if target.startswith("ch:"):
            stamp = int(time.time())
            # Distinguish identical sends made in the same second.
            stamp = max(stamp, max((p['sender_timestamp'] + 1 for p in self.sent_packets if p['target'] == target), default=stamp))
            packet = {'target': target, 'sender_timestamp': stamp, 'channel_name': next(c['name'] for c in self.channels if c['id'] == target),
                      'wire_text': self.node.get('identity', {}).get('name', '') + ': ' + text, 'repeats': 0}
            self.sent_packets.append(packet)
            self.sent_packets = self.sent_packets[-100:]
            if metadata is not None:
                metadata.update(sender_timestamp=stamp, repeats=0)
            try:
                result = await asyncio.wait_for(self.client.commands.send_chan_msg(int(target[3:]), text, timestamp=stamp), 15)
            except Exception:
                self.sent_packets.remove(packet)
                raise
            if result.type == EventType.ERROR:
                self.sent_packets.remove(packet)
        else:
            result = await asyncio.wait_for(self.client.commands.send_msg(self.contacts[target[3:]], text), 15)
        if result.type == EventType.ERROR:
            raise ValueError("Radio rejected message")
        return "sent to node · listening for repeats" if target.startswith("ch:") else "submitted · delivery unconfirmed"

    async def close(self):
        if self.refresh_task:
            self.refresh_task.cancel()
            await asyncio.gather(self.refresh_task, return_exceptions=True)
            self.refresh_task = None
        if self.client:
            await self.client.disconnect()
