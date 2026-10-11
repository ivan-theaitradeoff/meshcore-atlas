import copy
from pathlib import Path
import tempfile
import tomllib
import unittest

from meshcore_bridge.daemon import Bridge


CONFIG = tomllib.loads((Path(__file__).parents[1] / 'config.example.toml').read_text())


class ReceiveDedup(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bridge = Bridge(copy.deepcopy(CONFIG), Path(self.temp.name) / 'history.sqlite3')

    async def asyncTearDown(self):
        self.bridge.db.close()
        self.temp.cleanup()

    async def test_same_radio_packet_is_saved_once_but_later_send_is_kept(self):
        metadata = {'sender_timestamp': 1740000000, 'SNR': 7}
        await self.bridge.receive('ch:0', 'channel peer', 'Alice: Hello', True, metadata)
        await self.bridge.receive('ch:0', 'channel peer', 'Alice: Hello', True, metadata)

        messages = (await self.bridge.request({'op': 'snapshot'}))['messages']
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]['text'], 'Alice: Hello')

        await self.bridge.receive('ch:0', 'channel peer', 'Alice: Hello', True,
                                  {'sender_timestamp': 1740000001})
        messages = (await self.bridge.request({'op': 'snapshot'}))['messages']
        self.assertEqual(len(messages), 2)

    async def test_messages_without_packet_timestamp_are_preserved(self):
        await self.bridge.receive('ch:0', 'channel peer', 'Alice: Hello', True)
        await self.bridge.receive('ch:0', 'channel peer', 'Alice: Hello', True)
        messages = (await self.bridge.request({'op': 'snapshot'}))['messages']
        self.assertEqual(len(messages), 2)

    async def test_legacy_duplicate_packets_are_hidden_but_history_is_preserved(self):
        metadata = {'sender_timestamp': 1740000000}
        self.bridge.save('ch:0', 'channel peer', 'Alice: Hello', 'received', 1, metadata)
        self.bridge.save('ch:0', 'channel peer', 'Alice: Hello', 'received', 1, metadata)

        snapshot = await self.bridge.request({'op': 'snapshot'})

        self.assertEqual(len(snapshot['messages']), 1)
        self.assertEqual(snapshot['unread'], 1)
        self.assertEqual(self.bridge.db.execute('SELECT COUNT(*) FROM messages').fetchone()[0], 2)


if __name__ == '__main__':
    unittest.main()
