import sqlite3
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from meshcore_bridge.channel_settings import notify

class NotificationPrivacy(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute('CREATE TABLE channel_settings (target TEXT, notifications TEXT, days INTEGER)')
        self.bridge = SimpleNamespace(db=self.db, radio=SimpleNamespace(
            node={'identity': {'name': 'SYNTHETIC_NODE'}},
            channels=[{'id':'ch:1','name':'SYNTHETIC_PRIVATE_CHANNEL'}],
            private_channels={'ch:1'}))

    async def asyncTearDown(self):
        self.db.close()

    async def test_default_notification_contains_only_fixed_text(self):
        proc = SimpleNamespace(wait=AsyncMock(return_value=0))
        with patch('asyncio.create_subprocess_exec', AsyncMock(return_value=proc)) as launch:
            await notify(self.bridge, 'ch:1', 'SYNTHETIC_SENDER: SYNTHETIC_CONFIDENTIAL_BODY')
        self.assertEqual(launch.call_args.args, (
            'notify-send', '--app-name=Meshcore Atlas', '--', 'Meshcore Atlas',
            'New message received. Open the app to read it.'))

    async def test_mentions_filter_does_not_disclose_content(self):
        self.db.execute("INSERT INTO channel_settings VALUES ('ch:1','mentions',0)")
        proc = SimpleNamespace(wait=AsyncMock(return_value=0))
        with patch('asyncio.create_subprocess_exec', AsyncMock(return_value=proc)) as launch:
            await notify(self.bridge, 'ch:1', 'No mention here')
            launch.assert_not_called()
            await notify(self.bridge, 'ch:1', '@[SYNTHETIC_NODE] SYNTHETIC_CONFIDENTIAL_BODY')
            self.assertEqual(launch.call_count, 1)
            self.assertNotIn('SYNTHETIC', repr(launch.call_args))

    async def test_muted_channel_remains_silent(self):
        self.db.execute("INSERT INTO channel_settings VALUES ('ch:1','none',0)")
        with patch('asyncio.create_subprocess_exec', AsyncMock()) as launch:
            await notify(self.bridge, 'ch:1', 'SYNTHETIC_CONFIDENTIAL_BODY')
            launch.assert_not_called()
