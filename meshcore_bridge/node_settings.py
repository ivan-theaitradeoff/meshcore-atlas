"""Validated local node configuration; no advertisement is sent."""
import math
from .channels import ChannelError, validate_name
from .node_info import sanitize


def validate(data, current):
    result = {'name': validate_name(data.get('name'))}
    for key, lo, hi in [('adv_lat',-90,90),('adv_lon',-180,180),('radio_freq',150,2500),('radio_bw',7.8,500),('radio_sf',5,12),('radio_cr',5,8),('tx_power',0,current.get('max_tx_power',22)),('adv_loc_policy',0,1)]:
        try: value = float(data[key])
        except (KeyError,TypeError,ValueError): raise ChannelError('Enter a valid value for '+key) from None
        if not math.isfinite(value) or not lo <= value <= hi:
            raise ChannelError('Value out of range: '+key)
        if key in ('radio_sf','radio_cr','tx_power','adv_loc_policy'):
            if value != int(value): raise ChannelError('Use a whole number for '+key)
            value = int(value)
        result[key] = value
    if result['radio_bw'] not in (7.8,10.4,15.6,20.8,31.25,41.7,62.5,125,250,500):
        raise ChannelError('Choose a supported bandwidth.')
    return result


async def act(radio, data):
    if not radio.client or not radio.client.is_connected: raise ChannelError('Connect the node first.')
    from meshcore import EventType
    async with radio.channel_lock:
        cmd = radio.client.commands
        event = await cmd.send_appstart()
        if event.type == EventType.ERROR: raise ChannelError('Could not read node settings.')
        current = event.payload
        radio.node['identity'] = sanitize('identity', current)
        if data.get('action') == 'get': return {'identity':radio.node['identity']}
        if data.get('action') != 'save': raise ChannelError('Unknown node action.')
        new = validate(data, current)
        changes = []
        if new['name'] != current.get('name'): changes.append(('name',cmd.set_name,(new['name'],)))
        if any(new[k] != current.get(k) for k in ('adv_lat','adv_lon')): changes.append(('location',cmd.set_coords,(new['adv_lat'],new['adv_lon'])))
        if new['adv_loc_policy'] != current.get('adv_loc_policy'): changes.append(('location sharing',cmd.set_advert_loc_policy,(new['adv_loc_policy'],)))
        if any(new[k] != current.get(k) for k in ('radio_freq','radio_bw','radio_sf','radio_cr')): changes.append(('radio',cmd.set_radio,tuple(new[k] for k in ('radio_freq','radio_bw','radio_sf','radio_cr'))))
        if new['tx_power'] != current.get('tx_power'): changes.append(('transmit power',cmd.set_tx_power,(new['tx_power'],)))
        for label, method, args in changes:
            result = await method(*args)
            if result.type == EventType.ERROR:
                raise ChannelError('Could not save '+label+'. Earlier changes may have applied; reopen settings to check.')
        result = await cmd.send_appstart()
        if result.type == EventType.ERROR: raise ChannelError('Saved commands, but readback failed. Reopen settings to verify.')
        radio.node['identity'] = sanitize('identity', result.payload)
        for key, value in new.items():
            actual = result.payload.get(key)
            if isinstance(value,(int,float)):
                matches = isinstance(actual,(int,float)) and abs(actual-value) < 0.001
            else: matches = actual == value
            if not matches: raise ChannelError('Node readback differs for '+key+'. Reopen settings to check.')
        return {'identity':radio.node['identity'], 'message':'Settings saved and verified.'}
