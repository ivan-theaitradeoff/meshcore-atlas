import re
import time


def split_reply(text, limit=160, max_parts=12):
    text = text.strip()
    if len(text.encode()) <= limit: return [text] if text else []
    budget = limit - len(f'{max_parts}/{max_parts} '.encode())
    pieces=[]
    while text and len(pieces)<max_parts:
        piece=text.encode()[:budget].decode('utf-8',errors='ignore')
        if len(piece)<len(text):
            space=piece.rfind(' ')
            if space>budget//2: piece=piece[:space]
        pieces.append(piece)
        text=text[len(piece):].lstrip()
    if text:
        pieces[-1]=pieces[-1].encode()[:budget-3].decode('utf-8',errors='ignore').rstrip()+'…'
    return [f'{i+1}/{len(pieces)} '+part for i,part in enumerate(pieces)]


class Assembler:
    def __init__(self): self.pending={}
    def accept(self, channel, sender, text):
        now=time.monotonic()
        self.pending={k:v for k,v in self.pending.items() if now-v['time']<300}
        match=re.fullmatch(r'(\d{1,2})/(\d{1,2})\s+(.+)',text,re.S)
        if not match: return text
        index,total=int(match[1]),int(match[2]);body=match[3]
        if not 1<=index<=total<=12: return None
        key=(channel,sender)
        item=self.pending.get(key)
        if item is None or item['total']!=total:
            if len(self.pending)>=64: return None
            item={'total':total,'parts':{},'time':now};self.pending[key]=item
        if index in item['parts'] and item['parts'][index]!=body:
            # A new first part starts a fresh question; other conflicting parts are ignored.
            if index!=1:return None
            item={'total':total,'parts':{},'time':now};self.pending[key]=item
        item['parts'][index]=body
        if len(item['parts'])!=total:return None
        del self.pending[key]
        return ' '.join(item['parts'][i] for i in range(1,total+1))
