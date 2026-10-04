"""Keep the saved radio connected without restarting the app or duplicating listeners."""
import asyncio


async def maintain_connection(radio, *, monitor_seconds=2, retry_seconds=5, timeout=45):
    if radio.config['transport'] == 'demo':
        await radio.connect()
        return
    if not radio.config.get('device'):
        radio.state = 'No node selected · open Connection setup'
        return
    attempts = 0
    while True:
        radio.state = 'connecting' if attempts == 0 else 'reconnecting · waiting for node'
        try:
            await asyncio.wait_for(radio.connect(), timeout)
            while radio.client and radio.client.is_connected:
                await asyncio.sleep(monitor_seconds)
        except Exception:
            pass  # Retry transient Bluetooth/USB failures without losing app history.
        radio.state = 'reconnecting · waiting for node'
        try:
            await asyncio.wait_for(radio.close(), 10)
        except Exception:
            pass
        radio.client = None
        attempts += 1
        await asyncio.sleep(retry_seconds)
