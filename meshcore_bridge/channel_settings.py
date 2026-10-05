import asyncio
import base64
import json
import time
from urllib.parse import urlencode
from .channels import ChannelError, validate_name


def settings(db, target):
    row = db.execute('SELECT notifications,days FROM channel_settings WHERE target=?', (target,)).fetchone()
    return {'notifications': row[0] if row else 'all', 'days': row[1] if row else 0}


def prune(db):
    for target, days in db.execute('SELECT target,days FROM channel_settings WHERE days>0').fetchall():
        cutoff = time.time() - days * 86400
        for mid, raw in db.execute('SELECT id,metadata FROM messages WHERE target=? AND deleted=0', (target,)).fetchall():
            meta = json.loads(raw)
            stamp = meta.get('received_at', meta.get('sent_at'))
            if stamp and stamp < cutoff:
                db.execute('DELETE FROM messages WHERE id=?', (mid,))
    db.commit()


async def notify(bridge, target, text):
    policy = settings(bridge.db, target)['notifications']
    name = bridge.radio.node.get('identity', {}).get('name', '')
    if policy == 'none' or (policy == 'mentions' and (not name or not any(t in text for t in ('@['+name+']', '@'+name)))):
        return
    # Never expose received content or node/channel names to argv or the
    # desktop notification service. Mention matching stays inside this process.
    try:
        proc = await asyncio.create_subprocess_exec('notify-send', '--app-name=Meshcore Atlas', '--', 'Meshcore Atlas', 'New message received. Open the app to read it.', stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await asyncio.wait_for(proc.wait(), 5)
    except (OSError, TimeoutError):
        pass


async def act(bridge, data):
    target = data.get('target', '')
    if not target.startswith('ch:') or target not in {c['id'] for c in bridge.radio.channels}:
        raise ChannelError('Channel is no longer available.')
    db = bridge.db
    action = data.get('action', 'settings')
    if action == 'preferences':
        mode, days = data.get('notifications'), data.get('days')
        if mode not in ('all', 'mentions', 'none') or type(days) is not int or days not in (0,1,7,30,90):
            raise ChannelError('Invalid channel preferences.')
        db.execute('INSERT OR REPLACE INTO channel_settings VALUES(?,?,?)', (target,mode,days)); db.commit(); prune(db)
    elif action == 'unblock':
        db.execute('DELETE FROM blocked WHERE target=? AND sender=?', (target,data.get('sender'))); db.commit()
    elif action == 'delete_history':
        db.execute('DELETE FROM messages WHERE target=?', (target,)); db.commit()
    elif action in ('share','rename','remove'):
        radio = bridge.radio
        if not radio.client or not radio.client.is_connected:
            raise ChannelError('Connect the node first.')
        from meshcore import EventType
        async with radio.channel_lock:
            index = int(target[3:])
            event = await radio.client.commands.get_channel(index)
            if event.type == EventType.ERROR or not event.payload.get('channel_name'):
                raise ChannelError('Could not read the channel.')
            name, key = event.payload['channel_name'], event.payload['channel_secret']
            if action == 'share':
                uri = 'meshcore://channel/add?' + urlencode({'name':name,'secret':key.hex()})
                proc = await asyncio.create_subprocess_exec('qrencode','-t','SVG','-o','-',stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL)
                svg, _ = await asyncio.wait_for(proc.communicate(uri.encode()), 5)
                if proc.returncode: raise ChannelError('Could not generate QR code.')
                return {'uri':uri,'secret':key.hex(),'qr':'data:image/svg+xml;base64,'+base64.b64encode(svg).decode()}
            new_name = validate_name(data.get('name')) if action == 'rename' else ''
            if new_name.startswith('#') and new_name != name:
                raise ChannelError('Use a name without # to preserve the existing key.')
            result = await radio.client.commands.set_channel(index,new_name,key if action == 'rename' else bytes(16))
            if result.type == EventType.ERROR: raise ChannelError('The node rejected the change.')
            check = await radio.client.commands.get_channel(index)
            if check.type == EventType.ERROR or check.payload.get('channel_name') != new_name or check.payload.get('channel_secret') != (key if action == 'rename' else bytes(16)):
                raise ChannelError('Could not verify the change. Check the node before retrying.')
            if action == 'remove': await bridge.archive_channel(target)
            await radio.refresh_directory()
            return {'message':'Channel renamed.' if action == 'rename' else 'Channel removed.'}
    elif action != 'settings':
        raise ChannelError('Unknown channel action.')
    participants = sorted({bridge.display_sender(sender,text) for sender,text in db.execute("SELECT sender,text FROM messages WHERE target=? AND status='received' AND deleted=0",(target,))})
    return dict(settings(db,target), participants=participants, blocked=[r[0] for r in db.execute('SELECT sender FROM blocked WHERE target=?',(target,))], count=db.execute('SELECT COUNT(*) FROM messages WHERE target=? AND deleted=0',(target,)).fetchone()[0])
