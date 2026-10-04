"""Local UI settings shared with the radio AI gateway."""
import asyncio
import json
from .channels import ChannelError, validate_name
from .gateway import Gateway

LIMITS = {'max_input_chars':(32,2000),'max_output_chars':(32,1600),'max_output_tokens':(64,4096),'per_sender_seconds':(0,3600),'global_seconds':(0,3600),'timeout_seconds':(10,300)}

def validate(data):
    result={}
    if type(data.get('enabled')) is not bool: raise ChannelError('Choose whether AI replies are enabled.')
    result['enabled']=data['enabled']
    if 'conversation_memory' in data:
        if type(data['conversation_memory']) is not bool: raise ChannelError('Choose whether conversation memory is enabled.')
        result['conversation_memory']=data['conversation_memory']
    if 'private_channels' in data:
        names = data['private_channels']
        if not isinstance(names, list) or len(names) > 256:
            raise ChannelError('Enter the private channel names for AI.')
        result['private_channels'] = list(dict.fromkeys(validate_name(name) for name in names))
    for key,(lo,hi) in LIMITS.items():
        try: value=int(str(data.get(key)))
        except (ValueError,TypeError): raise ChannelError('Use a whole number for '+key) from None
        if not lo<=value<=hi: raise ChannelError(key+' must be between '+str(lo)+' and '+str(hi)+'.')
        result[key]=value
    return result

def server_settings(data):
    endpoint = str(data.get('endpoint', '')).strip().rstrip('/')
    provider = data.get('provider')
    try:
        Gateway({'endpoint':endpoint, 'provider':provider})
        from urllib.parse import urlsplit
        url = urlsplit(endpoint)
        if url.path or not url.port:
            raise ValueError()
    except (ValueError, TypeError):
        raise ChannelError('Use a local server address with a port, such as http://127.0.0.1:1234 (without /v1).') from None
    return {'endpoint':endpoint, 'provider':provider}


def restore(bridge):
    server=bridge.db.execute("SELECT value FROM ai_state WHERE key='server'").fetchone()
    if server:
        try: bridge.config['llm'].update(server_settings(json.loads(server[0])))
        except (ValueError, TypeError): pass
    row=bridge.db.execute("SELECT value FROM ai_state WHERE key='preferences'").fetchone()
    if row:
        try: bridge.config['llm'].update(validate(json.loads(row[0])))
        except (ValueError,TypeError): pass

async def act(bridge,data):
    action=data.get('action','get')
    if action != 'get':
        if bridge.ai_busy: raise ChannelError('AI is busy. Wait for the current request to finish.')
        bridge.ai_busy=True
        try:
            if action=='save':
                prefs=validate(data)
                bridge.db.execute("INSERT OR REPLACE INTO ai_state VALUES('preferences',?)",(json.dumps(prefs),));bridge.db.commit()
                bridge.config['llm'].update(prefs)
            elif action=='server':
                prefs=server_settings(data)
                bridge.db.execute("INSERT OR REPLACE INTO ai_state VALUES('server',?)",(json.dumps(prefs),));bridge.db.commit()
                bridge.config['llm'].update(prefs)
            elif action=='model':
                key=data.get('model','')
                identifier=await asyncio.to_thread(bridge.model_commands.load,key)
                bridge.model_commands.select(identifier)
            elif action=='context':
                identifier,_=await asyncio.to_thread(bridge.model_commands.change_context,str(data.get('context','')))
                bridge.model_commands.select(identifier)
            else: raise ChannelError('Unknown AI settings action.')
        except ChannelError: raise
        except Exception: raise ChannelError('Model operation failed. Check LM Studio and refresh settings.') from None
        finally: bridge.ai_busy=False
    c=bridge.config['llm']
    result={k:c[k] for k in ['enabled','model','endpoint','provider',*LIMITS]}
    result['channels']=c.get('private_channels',[])
    result['available_channels']=sorted({channel['name'] for channel in bridge.radio.channels if channel['id'] in bridge.radio.private_channels})
    result['conversation_memory']=c.get('conversation_memory',True)
    result['busy']=bridge.ai_busy
    result['models']=[];result['context']=None
    try:
        models=await asyncio.to_thread(bridge.model_commands.catalog)
        result['models']=[{'key':m['key'],'name':m.get('display_name',m['key'])} for m in models]
        for m in models:
            for i in m.get('loaded_instances',[]):
                if i['id']==c['model']:
                    result['context']=i.get('config',{}).get('context_length')
                    result['model_key']=m['key']
                    result['max_context']=m.get('max_context_length')
    except Exception: result['warning']='Cannot reach the model list at this address. In LM Studio, start the local server, then enter its address above and choose Save server & check. Model selection and context controls require LM Studio.'
    return result
