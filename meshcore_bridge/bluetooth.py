"""Use BlueZ's known device record; connected devices may stop advertising."""
async def known_device(address):
    try:
        from dbus_fast import BusType, Message, MessageType
        from dbus_fast.aio import MessageBus
        from bleak.backends.device import BLEDevice
    except ImportError:
        return None
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        reply = await bus.call(Message(destination='org.bluez', path='/',
                                       interface='org.freedesktop.DBus.ObjectManager',
                                       member='GetManagedObjects'))
        if reply.message_type == MessageType.ERROR:
            return None
        for path, interfaces in reply.body[0].items():
            raw = interfaces.get('org.bluez.Device1', {})
            props = {key: value.value for key, value in raw.items()}
            if props.get('Address', '').upper() == address.upper():
                return BLEDevice(address, props.get('Name', address), {'path': path, 'props': props})
        return None
    finally:
        bus.disconnect()
