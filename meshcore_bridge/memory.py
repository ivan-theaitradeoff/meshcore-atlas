"""Bounded local conversation history; channel sender names are not authenticated IDs."""
import json

class Memory:
    def __init__(self, db):
        self.db = db
        db.execute('CREATE TABLE IF NOT EXISTS ai_memory (channel TEXT, sender TEXT, turns TEXT, PRIMARY KEY(channel,sender))')

    def read(self, channel, sender, budget):
        row = self.db.execute('SELECT turns FROM ai_memory WHERE channel=? AND sender=?', (channel,sender)).fetchone()
        turns = json.loads(row[0]) if row else []
        while turns and sum(len(t['content'].encode('utf-8')) for t in turns) > budget:
            turns = turns[2:]
        return turns

    def append(self, channel, sender, question, answer):
        turns = self.read(channel,sender,8192) + [{'role':'user','content':question},{'role':'assistant','content':answer}]
        while len(turns)>40 or sum(len(t['content'].encode('utf-8')) for t in turns)>8192:
            turns=turns[2:]
        self.db.execute('INSERT OR REPLACE INTO ai_memory VALUES(?,?,?)',(channel,sender,json.dumps(turns)))
        self.db.commit()

    def reset(self, channel, sender):
        self.db.execute('DELETE FROM ai_memory WHERE channel=? AND sender=?',(channel,sender));self.db.commit()
