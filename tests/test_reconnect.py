import asyncio
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock
from meshcore_bridge.reconnect import maintain_connection

class Reconnect(unittest.IsolatedAsyncioTestCase):
    async def test_retries_startup_failure_and_later_disconnect(self):
        ready = asyncio.Event()
        radio = SimpleNamespace(config={'transport':'ble','device':'test'}, client=None, state='', close=AsyncMock())
        calls = 0
        async def connect():
            nonlocal calls
            calls += 1
            if calls == 1:
                raise TimeoutError()
            radio.client = SimpleNamespace(is_connected=True)
            if calls == 2:
                asyncio.get_running_loop().call_later(.005, setattr, radio.client, 'is_connected', False)
            if calls == 3:
                ready.set()
        radio.connect = connect
        task = asyncio.create_task(maintain_connection(radio, monitor_seconds=.001, retry_seconds=.001))
        try:
            await asyncio.wait_for(ready.wait(), 1)
            self.assertEqual(calls, 3)
            self.assertEqual(radio.close.await_count, 2)
        finally:
            task.cancel()
            with self.assertRaises(asyncio.CancelledError): await task

    async def test_no_device_does_not_retry(self):
        radio = SimpleNamespace(config={'transport':'ble','device':''}, connect=AsyncMock())
        await maintain_connection(radio)
        radio.connect.assert_not_called()
