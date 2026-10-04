"""Channel sender names are labels, not verified direct-message identities."""
import hashlib


def entries(db, channels, display_sender):
    saved = {c['name'].removeprefix('DM · ') for c in channels if c['id'].startswith('dm:')}
    active = {c['id'] for c in channels if c['id'].startswith('ch:')}
    heard = {}
    for target, sender, text in db.execute("SELECT target,sender,text FROM messages WHERE status='received' AND deleted=0 ORDER BY id DESC"):
        if target not in active: continue
        name = display_sender(sender, text)
        if not name or name in saved or name in ('unknown', 'channel peer', 'me', 'local AI'): continue
        if name not in heard:
            heard[name] = dict(id='heard:'+hashlib.sha256(name.encode()).hexdigest(), name=name,
                               source_target=target, heard_only=True)
    return sorted(heard.values(), key=lambda item: item['name'].casefold())
