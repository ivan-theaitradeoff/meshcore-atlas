"""Local contact management. Sharing exports a link, never broadcasts."""
import re
from .channels import ChannelError

async def act(radio, data):
    key = data.get('key', '')
    if key not in radio.contacts:
        raise ChannelError('Contact is no longer available.')
    contact = radio.contacts[key].copy()
    action = data.get('action')
    if action == 'details':
        fields = ('adv_name', 'public_key', 'type', 'last_advert', 'adv_lat', 'adv_lon', 'out_path', 'out_path_len', 'out_path_hash_mode')
        return {'details': {k: contact[k] for k in fields if k in contact}}
    if not radio.client or not radio.client.is_connected:
        raise ChannelError('Connect the node first.')
    from meshcore import EventType
    commands = radio.client.commands
    if action == 'share':
        result = await commands.export_contact(key)
    elif action == 'reset':
        result = await commands.reset_path(key)
    elif action == 'remove':
        result = await commands.remove_contact(key)
    elif action == 'path':
        path = data.get('path', '').strip().lower()
        mode = data.get('mode', 0)
        if type(mode) is not int or mode not in (0, 1, 2) or not re.fullmatch('[0-9a-f]*', path) or len(path) % (2*(mode+1)) or len(path)//2 > 64 or len(path)//(2*(mode+1)) > 63:
            raise ChannelError('Enter whole hexadecimal hop hashes, up to 64 bytes and 63 hops.')
        result = await commands.change_contact_path(contact, path, path_hash_mode=mode)
    else:
        raise ChannelError('Unknown contact action.')
    if result.type == EventType.ERROR:
        raise ChannelError('The node rejected this contact action.')
    if action == 'share':
        return {'uri': result.payload['uri']}
    await radio.refresh_directory()
    return {'message': 'Contact removed. Local message history is retained.' if action == 'remove' else 'Path saved.'}
