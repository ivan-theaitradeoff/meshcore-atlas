import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from meshcore_bridge.radio import Radio
from meshcore_bridge.map_data import nodes


class DirectorySync(unittest.IsolatedAsyncioTestCase):
    async def test_full_directory_failed_refresh_and_confirmed_empty(self):
        radio = Radio({'channel_slots': 0}, AsyncMock())
        contacts = {str(i): {'adv_name': 'Test node', 'adv_lat': 47.0, 'adv_lon': -122.0} for i in range(350)}
        fetch = AsyncMock(side_effect=[
            SimpleNamespace(type='contacts', payload=contacts),
            SimpleNamespace(type='error', payload={}),
            SimpleNamespace(type='contacts', payload={}),
        ])
        radio.client = SimpleNamespace(commands=SimpleNamespace(get_contacts=fetch))
        with patch.dict('sys.modules', meshcore=SimpleNamespace(EventType=SimpleNamespace(ERROR='error'))):
            await radio.refresh_directory()
            self.assertEqual(radio.node['contact_count'], 350)
            self.assertEqual(len(nodes(radio)), 350)
            self.assertTrue(all(n['latitude'] is not None for n in nodes(radio)))
            await radio.refresh_directory()
            self.assertEqual(len(nodes(radio)), 350)
            self.assertIn('contact_sync_error', radio.node)
            await radio.refresh_directory()
            self.assertEqual(nodes(radio), [])
            self.assertNotIn('contact_sync_error', radio.node)
