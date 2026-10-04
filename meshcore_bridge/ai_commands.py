"""Fixed local model commands; never executes user-supplied programs."""
import json
import re
import urllib.request
from .gateway import NoRedirect

class ModelCommands:
    def __init__(self, gateway, db):
        self.gateway, self.db = gateway, db
        db.execute('CREATE TABLE IF NOT EXISTS ai_models (number INTEGER PRIMARY KEY AUTOINCREMENT, model TEXT UNIQUE)')
        db.execute('CREATE TABLE IF NOT EXISTS ai_state (key TEXT PRIMARY KEY, value TEXT)')
        row = db.execute("SELECT value FROM ai_state WHERE key='model'").fetchone()
        self.plain_chat = bool(row)
        if row: gateway.config['model'] = row[0]
        db.commit()

    def api(self, path, body=None):
        req=urllib.request.Request(self.gateway.config['endpoint'].rstrip('/')+path,
            data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
        with opener.open(req,timeout=180 if body is not None else 8) as response: raw=response.read(1048577)
        if len(raw)>1048576: raise ValueError('Model response too large')
        return json.loads(raw)

    def catalog(self):
        return sorted((m for m in self.api('/api/v1/models')['models'] if m.get('type')=='llm'),key=lambda m:m['key'])

    def register(self, models):
        for m in models: self.db.execute('INSERT OR IGNORE INTO ai_models(model) VALUES(?)',(m['key'],))
        self.db.commit()
        ids={r[1]:r[0] for r in self.db.execute('SELECT number,model FROM ai_models')}
        return [str(ids[m['key']])+': '+m['key'] for m in models]

    def chosen(self, number):
        row=self.db.execute('SELECT model FROM ai_models WHERE number=?',(number,)).fetchone()
        return row[0] if row else None

    def load(self, key):
        model=next((m for m in self.catalog() if m['key']==key),None)
        if model is None: raise ValueError('Model no longer available')
        loaded=model.get('loaded_instances',[])
        if loaded: return loaded[0]['id']
        response=self.api('/api/v1/models/load',{'model':key,'context_length':4096})
        if response.get('status')!='loaded': raise ValueError('Model not loaded')
        return response['instance_id']

    def active(self):
        identifier = self.gateway.config['model']
        for model in self.catalog():
            for instance in model.get('loaded_instances', []):
                if instance['id'] == identifier:
                    return model, instance
            if model['key'] == identifier:
                return model, next(iter(model.get('loaded_instances', [])), None)
        raise ValueError('Selected model is not available in LM Studio.')

    def context_status(self):
        _, instance = self.active()
        return instance.get('config', {}).get('context_length') if instance else None

    def change_context(self, value):
        match = re.fullmatch(r'([0-9]+)([kK]?)', value.strip())
        if not match: raise ValueError('Use @ai context 128k or @ai context 131072.')
        size = int(match[1]) * (1024 if match[2] else 1)
        model, instance = self.active()
        maximum = model.get('max_context_length', 0)
        if not isinstance(maximum, int) or not 128 <= size <= maximum:
            raise ValueError('Context must be between 128 and '+str(maximum)+' tokens for this model.')
        old = instance.get('config', {}).get('context_length', 4096) if instance else 4096
        if instance and old == size: return instance['id'], size
        if instance: self.api('/api/v1/models/unload', {'instance_id':instance['id']})
        try:
            response = self.api('/api/v1/models/load', {'model':model['key'], 'context_length':size, 'echo_load_config':True})
            if response.get('status') != 'loaded': raise RuntimeError('Load failed')
            identifier = response['instance_id']
            fresh = self.catalog()
            actual = next((i.get('config', {}).get('context_length') for m in fresh for i in m.get('loaded_instances', []) if i['id']==identifier), None)
            if actual != size: raise RuntimeError('Context readback differs')
            return identifier, actual
        except Exception:
            # Best effort recovery; never claim the requested size was applied.
            try:
                restored = self.api('/api/v1/models/load', {'model':model['key'], 'context_length':old})
                if restored.get('status') == 'loaded':
                    self.gateway.config['model'] = restored['instance_id']
                    raise ValueError('Context change failed; previous context restored.')
            except ValueError: raise
            except Exception: pass
            raise ValueError('Context change failed. Check LM Studio before chatting.') from None

    def select(self, identifier):
        self.plain_chat = True
        self.gateway.config['model']=identifier
        self.db.execute("INSERT OR REPLACE INTO ai_state VALUES('model',?)",(identifier,));self.db.commit()


def chunks(lines, limit=150):
    result=[]; current=''
    for line in lines:
        while len(line.encode())>limit:
            part=line.encode()[:limit].decode('utf-8',errors='ignore')
            if current: result.append(current); current=''
            result.append(part);line=line[len(part):]
        candidate=current+'\n'+line if current else line
        if len(candidate.encode())>limit: result.append(current);current=line
        else: current=candidate
    if current:result.append(current)
    return result
