"""Fixed local setup actions. JSON input over stdin keeps PINs out of argv/logs."""
import asyncio
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
CONFIG = HOME / '.config/meshcore-bridge/config.toml'
PYTHON = HOME / '.local/share/meshcore-bridge/.venv/bin/python'


def command(argv, timeout=180):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise ValueError('The setup action failed. Check internet access and try again.' if 'pip' in argv else 'The system could not complete this action. Try again or check permissions.')
    return result.stdout.decode()


def read_config():
    return tomllib.loads(CONFIG.read_text()) if CONFIG.exists() else tomllib.loads((ROOT/'config.example.toml').read_text())


def save_radio(data):
    transport = data.get('transport')
    device = data.get('device', '')
    if transport == 'ble':
        if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', device):
            raise ValueError('Choose a Bluetooth node first.')
    elif transport == 'serial':
        available = serial_devices()
        if device not in [d['device'] for d in available]:
            raise ValueError('Choose an attached USB serial device.')
    else:
        raise ValueError('Choose Bluetooth or USB.')
    if type(data.get('allow_transmit')) is not bool:
        raise ValueError('Choose whether sending is enabled.')
    text = CONFIG.read_text() if CONFIG.exists() else (ROOT/'config.example.toml').read_text()
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        raise ValueError('Existing configuration is invalid. Use Repair configuration to back it up and restore safe defaults.') from None
    section = re.search(r'(?m)^\[radio\][^\n]*\n(?P<body>.*?)(?=^\[|\Z)', text, re.S | re.M)
    if not section:
        raise ValueError('Missing radio settings. Use Repair configuration.')
    body = section.group('body')
    for key, value in {'transport':transport, 'device':device, 'allow_transmit':data['allow_transmit']}.items():
        line = key + ' = ' + json.dumps(value)
        pattern = r'(?m)^' + key + r'\s*=.*$'
        body = re.sub(pattern, lambda m:line, body) if re.search(pattern, body) else body + '\n' + line + '\n'
    updated = text[:section.start('body')] + body + text[section.end('body'):]
    tomllib.loads(updated)
    write_config(updated)


def write_config(text):
    CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=CONFIG.parent, prefix='.config-')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(name, CONFIG)
    finally:
        Path(name).unlink(missing_ok=True)


def serial_devices():
    paths = list(Path('/dev/serial/by-id').glob('*'))
    if not paths:
        paths = list(Path('/dev').glob('ttyACM*')) + list(Path('/dev').glob('ttyUSB*'))
    return [{'name':p.name, 'device':str(p)} for p in paths]


async def bluetooth(action, data):
    from dbus_fast import BusType, Variant
    from dbus_fast.aio import MessageBus
    from dbus_fast.service import ServiceInterface, method
    from dbus_fast.errors import DBusError
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    started = []
    registered = False
    try:
        async def interface(path, name):
            intro = await bus.introspect('org.bluez', path)
            return bus.get_proxy_object('org.bluez', path, intro).get_interface(name)
        manager = await interface('/', 'org.freedesktop.DBus.ObjectManager')
        objects = await manager.call_get_managed_objects()
        async def start_discovery():
            for path, interfaces in objects.items():
                if 'org.bluez.Adapter1' in interfaces:
                    props = await interface(path, 'org.freedesktop.DBus.Properties')
                    await props.call_set('org.bluez.Adapter1', 'Powered', Variant('b', True))
                    adapter = await interface(path, 'org.bluez.Adapter1')
                    await adapter.call_set_discovery_filter({'Transport':Variant('s','le')})
                    await adapter.call_start_discovery()
                    started.append(adapter)
            if not started:
                raise ValueError('No Bluetooth adapter found. Connect an adapter or use USB.')
        if action == 'scan':
            await start_discovery()
            await asyncio.sleep(8)
            objects = await manager.call_get_managed_objects()
            devices = []
            for path, interfaces in objects.items():
                p = interfaces.get('org.bluez.Device1')
                if not p:
                    continue
                get = lambda k,default=None:p[k].value if k in p else default
                name = get('Name', get('Alias', get('Address')))
                uuids = get('UUIDs', [])
                if 'meshcore' in name.lower() or '6e400001-b5a3-f393-e0a9-e50e24dcca9e' in uuids:
                    devices.append({'name':name, 'device':get('Address'), 'paired':get('Paired',False)})
            return {'devices':devices}
        address = data.get('device','').upper()
        if not re.fullmatch(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}', address):
            raise ValueError('Choose a Bluetooth node first.')
        # BlueZ can discard unpaired records when the discovery client exits.
        # Hold our own discovery session throughout pairing, not just the list scan.
        await start_discovery()
        path = None
        for _ in range(30):
            objects = await manager.call_get_managed_objects()
            path = next((p for p,i in objects.items() if 'org.bluez.Device1' in i and i['org.bluez.Device1']['Address'].value.upper()==address), None)
            if path:
                break
            await asyncio.sleep(.5)
        if not path:
            raise ValueError('Node not found after searching again. Disconnect it from your phone, restart it nearby, then choose Search again.')
        if action != 'repair_pair' and objects[path]['org.bluez.Device1'].get('Paired',Variant('b',False)).value:
            return {'message':'Already paired. Connecting next.'}
        pin = data.get('pin','')
        if not re.fullmatch(r'\d{6}', pin):
            raise ValueError('Enter the six-digit PIN shown on the node, then pair.')
        if action == 'repair_pair':
            # Remove only the selected bond, then rediscover its fresh GATT record.
            adapter_path = path.split('/dev_')[0]
            adapter = await interface(adapter_path, 'org.bluez.Adapter1')
            await adapter.call_remove_device(path)
            for _ in range(30):
                await asyncio.sleep(.5)
                objects = await manager.call_get_managed_objects()
                if path in objects:
                    break
            else:
                raise ValueError('Node not found after removing the old pairing. Keep it powered on nearby, then search again.')
        class Agent(ServiceInterface):
            def __init__(self):
                super().__init__('org.bluez.Agent1')
            @method()
            def Release(self): pass
            @method()
            def RequestPinCode(self, device: 'o') -> 's':
                if device != path: raise DBusError('org.bluez.Error.Rejected','Wrong device')
                return pin
            @method()
            def RequestPasskey(self, device: 'o') -> 'u':
                if device != path: raise DBusError('org.bluez.Error.Rejected','Wrong device')
                return int(pin)
            @method()
            def RequestConfirmation(self, device: 'o', passkey: 'u'):
                if device != path or passkey != int(pin): raise DBusError('org.bluez.Error.Rejected','PIN mismatch')
            @method()
            def Cancel(self): pass
        bus.export('/mesh_atlas/agent', Agent())
        agents = await interface('/org/bluez','org.bluez.AgentManager1')
        await agents.call_register_agent('/mesh_atlas/agent','KeyboardDisplay')
        registered = True
        device = await interface(path,'org.bluez.Device1')
        await asyncio.wait_for(device.call_pair(),45)
        props = await interface(path,'org.freedesktop.DBus.Properties')
        await props.call_set('org.bluez.Device1','Trusted',Variant('b',True))
        return {'message':'Paired successfully. Connecting next.'}
    finally:
        for adapter in started:
            try: await adapter.call_stop_discovery()
            except Exception: pass
        if registered:
            try: await agents.call_unregister_agent('/mesh_atlas/agent')
            except Exception: pass
        bus.disconnect()


def diagnose():
    import socket
    expected = json.loads((ROOT/'manifest.json').read_text())['version']
    try:
        from importlib.metadata import version
        installed = version('omarchy-meshcore')
    except Exception:
        installed = 'not installed'
    result = subprocess.run(['systemctl','--user','show','meshcore-bridge.service',
                             '--property=ActiveState,SubState,Result,ExecMainStatus'],
                            capture_output=True,text=True,timeout=10)
    status = dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    lines = ['Bridge version: ' + installed + ' (app ' + expected + ')',
             'Service: ' + status.get('ActiveState','unknown') + ' / ' + status.get('SubState','unknown'),
             'Startup result: ' + status.get('Result','unknown') + '; exit ' + status.get('ExecMainStatus','unknown')]
    path = Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))/'meshcore-bridge/bridge.sock'
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(3)
            client.connect(str(path))
            client.sendall(b'{"op":"snapshot"}\n')
            response = client.recv(4096)
            if not response: raise ConnectionError()
        lines.append('Local connection: responding')
        responding = True
    except (OSError,TimeoutError):
        lines.append('Local connection: unavailable')
        responding = False
    if installed != expected:
        lines.append('Click Update / repair components, then Save & connect.')
    elif not responding:
        lines.append('The background service has not opened its connection. Share these details so we can fix startup.')
    return {'message':'\n'.join(lines), 'responding':responding}


def main(data):
    action = data.get('action')
    if action == 'diagnose':
        return diagnose()
    if action == 'status':
        result = {'installed':PYTHON.exists(), 'devices':[]}
        try:
            c = read_config()['radio']
            result.update(transport=c['transport'], device=c['device'], allow_transmit=c['allow_transmit'])
        except (ValueError, KeyError):
            result['warning'] = 'Configuration needs repair. Repair saves a backup and restores disabled AI and sending.'
        return result
    if action == 'usb':
        return {'devices':serial_devices()}
    if action == 'install':
        missing = [p for p in ['qt6-location','qrencode','zbar','libnotify'] if subprocess.run(['pacman','-Q',p],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode]
        if missing:
            command(['pkexec','omarchy','pkg','add',*missing],600)
        command(['bash',str(ROOT/'scripts/setup-bridge.sh')],600)
        return {'installed':True,'message':'Ready. Choose Bluetooth or USB and connect your node.'}
    if action == 'repair':
        if CONFIG.exists():
            import time
            backup = CONFIG.with_name('config.toml.backup-'+str(time.time_ns()))
            backup.write_bytes(CONFIG.read_bytes());backup.chmod(0o600)
        write_config((ROOT/'config.example.toml').read_text())
        return {'message':'Configuration repaired. Select your node; sending and AI are disabled.'}
    if action in ('scan','pair','repair_pair'):
        if action == 'repair_pair':
            if not re.fullmatch(r'\d{6}', data.get('pin','')):
                raise ValueError('Enter the current six-digit PIN before repairing pairing.')
            command(['systemctl','--user','stop','meshcore-bridge.service'])
        return asyncio.run(bluetooth(action,data))
    if action == 'connect':
        save_radio(data)
        command(['systemctl','--user','enable','meshcore-bridge.service'])
        command(['systemctl','--user','restart','meshcore-bridge.service'])
        import time
        for _ in range(6):
            report = diagnose()
            if report['responding']: break
            time.sleep(1)
        return report
    if action == 'stop':
        command(['systemctl','--user','stop','meshcore-bridge.service'])
        return {'message':'Bridge stopped.'}
    raise ValueError('Unknown setup action.')


if __name__ == '__main__':
    os.umask(0o077)
    if PYTHON.exists() and Path(sys.prefix) != PYTHON.parent.parent:
        os.execv(str(PYTHON),[str(PYTHON),str(Path(__file__).resolve())])
    try:
        data = json.loads(sys.stdin.readline(8192))
        result = main(data)
        print(json.dumps(dict(ok=True,**result)),flush=True)
    except Exception as exc:
        message = str(exc) if isinstance(exc,ValueError) else ('Bluetooth or setup action failed ('+type(exc).__name__+'). Check the node, PIN, and Bluetooth adapter, then retry.')
        print(json.dumps({'ok':False,'message':message}),flush=True)
