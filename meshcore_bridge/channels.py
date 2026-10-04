"""Validated channel creation/import. Channel keys never enter snapshots or logs."""
import asyncio
import hashlib
from pathlib import Path
import re
import secrets
from urllib.parse import urlsplit, parse_qs, unquote

PUBLIC_KEY = bytes.fromhex('8b3387e9c5cdea6ac9e5edbaa115cd72')

class ChannelError(ValueError):
    pass


def validate_name(name):
    if not isinstance(name, str):
        raise ChannelError('Enter a channel name.')
    name = name.strip()
    if not name or len(name.encode('utf-8')) > 31 or any(ord(c) < 32 for c in name):
        raise ChannelError('Use a name of 1–31 UTF-8 bytes without control characters.')
    return name


def key_from_hex(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9a-fA-F]{32}', value.strip()):
        raise ChannelError('The secret key must contain exactly 32 hexadecimal characters.')
    return bytes.fromhex(value.strip())


async def decode_qr(source):
    if not isinstance(source, str) or len(source) > 8192:
        raise ChannelError('Select a QR image or paste a MeshCore channel link.')
    source = source.strip()
    if not source.startswith('meshcore://'):
        url = urlsplit(source)
        if url.scheme == 'file' and url.netloc in ('', 'localhost'):
            source = unquote(url.path)
        elif url.scheme:
            raise ChannelError('Only local QR images or MeshCore channel links are supported.')
        path = Path(source).expanduser()
        if not path.is_absolute() or not path.is_file() or path.stat().st_size > 20_000_000:
            raise ChannelError('Choose a local image smaller than 20 MB.')
        try:
            process = await asyncio.create_subprocess_exec('zbarimg', '--quiet', '--raw', str(path),
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
            try:
                output, _ = await asyncio.wait_for(process.communicate(), 10)
            except TimeoutError:
                process.kill()
                await process.wait()
                raise ChannelError('QR scan timed out.')
        except FileNotFoundError:
            raise ChannelError('QR image scanning requires zbarimg. You can paste a channel link instead.') from None
        codes = output.decode('utf-8', errors='replace').strip().splitlines()
        if process.returncode or len(codes) != 1 or len(output) > 8192:
            raise ChannelError('Choose an image containing exactly one readable channel QR code.')
        source = codes[0]
    url = urlsplit(source)
    if url.scheme != 'meshcore' or url.netloc != 'channel' or url.path != '/add':
        raise ChannelError('This is not a MeshCore channel QR code.')
    query = parse_qs(url.query)
    if query.get('region_scope', [''])[0]:
        raise ChannelError('This QR specifies a region scope, which this version cannot configure yet.')
    if len(query.get('name', [])) != 1 or len(query.get('secret', [])) != 1:
        raise ChannelError('The channel link must include one name and one secret.')
    return validate_name(query['name'][0]), key_from_hex(query['secret'][0])


async def prepare(data):
    mode = data.get('mode')
    if mode == 'qr':
        name, key = await decode_qr(data.get('source', ''))
    else:
        name = validate_name(data.get('name', ''))
        if mode == 'hashtag':
            name = '#' + name.lstrip('#').lower()
            if not re.fullmatch(r'#[a-z0-9-]+', name):
                raise ChannelError('Hashtag names use only a–z, 0–9 and hyphens.')
            name = validate_name(name)
            key = hashlib.sha256(name.encode()).digest()[:16]
        elif mode == 'private_create':
            key = secrets.token_bytes(16)
        elif mode in ('private_join', 'public_import'):
            key = key_from_hex(data.get('secret', ''))
        elif mode == 'public':
            key = PUBLIC_KEY
        else:
            raise ChannelError('Choose a channel type.')
    # meshcore_py overrides supplied keys for hashtag names; never silently import a different key.
    if name.startswith('#') and key != hashlib.sha256(name.encode()).digest()[:16]:
        raise ChannelError('Use a name without # for a channel with a custom secret key.')
    return name, key, mode == 'private_create'
