"""Newline JSON over an owner-only Unix socket; persistent local SQLite history."""
import argparse
import asyncio
import fcntl
import json
import os
from pathlib import Path
import signal
import sqlite3
import tomllib
import time

from . import channel_settings, node_settings, ai_settings, heard_contacts
from .map_data import nodes as map_nodes
from .ai_commands import ModelCommands, chunks
from .gateway import Gateway, EmptyModelAnswer
from .multipart import Assembler, split_reply
from .memory import Memory
from .radio import Radio
from .reconnect import maintain_connection
from .channels import ChannelError
from .contact_actions import act as contact_action


class Bridge:
    def __init__(self, config, database):
        self.config = config
        self.db = sqlite3.connect(database)
        self.db.execute('CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, target TEXT, sender TEXT, text TEXT, status TEXT, unread INTEGER)')
        columns = {r[1] for r in self.db.execute('PRAGMA table_info(messages)')}
        for name, definition in [('metadata', "TEXT NOT NULL DEFAULT '{}'"), ('deleted', 'INTEGER NOT NULL DEFAULT 0')]:
            if name not in columns:
                self.db.execute(f'ALTER TABLE messages ADD COLUMN {name} {definition}')
        self.db.execute('CREATE TABLE IF NOT EXISTS blocked (target TEXT, sender TEXT, PRIMARY KEY(target,sender))')
        self.db.execute('CREATE TABLE IF NOT EXISTS favourites (key TEXT PRIMARY KEY)')
        self.db.execute('CREATE TABLE IF NOT EXISTS channel_settings (target TEXT PRIMARY KEY, notifications TEXT, days INTEGER)')
        self.db.commit()
        self.memory = Memory(self.db)
        self.gateway = Gateway(config['llm'])
        self.model_commands = ModelCommands(self.gateway, self.db)
        ai_settings.restore(self)
        self.radio = Radio(config['radio'], self.receive)
        self.radio.repeat_callback = self.update_repeats
        self.ai_seen = set()
        self.assembler = Assembler()
        self.ai_busy = False
        self.ai_tasks = set()
        self.clients = set()

    async def archive_channel(self, target):
        # Slot numbers are reused by the radio; detach the old local conversation.
        tasks = [t for t in self.ai_tasks if getattr(t, 'channel_target', None) == target]
        for task in tasks: task.cancel()
        if tasks: await asyncio.gather(*tasks, return_exceptions=True)
        archived = 'archive:' + str(time.time_ns()) + ':' + target
        for table, column in [('messages','target'), ('ai_memory','channel'), ('blocked','target'), ('channel_settings','target')]:
            self.db.execute(f'UPDATE {table} SET {column}=? WHERE {column}=?', (archived,target))
        self.db.execute('UPDATE messages SET unread=0 WHERE target=?', (archived,))
        self.db.commit()
        self.ai_seen = {item for item in self.ai_seen if item[0] != target}

    @staticmethod
    def display_sender(sender, text):
        if sender == 'channel peer' and ': ' in text:
            return text.split(': ', 1)[0][:128]
        return sender

    def save(self, target, sender, text, status, unread, metadata=None):
        meta = dict(metadata or {})
        meta.setdefault('received_at' if status == 'received' else 'sent_at', int(time.time()))
        self.db.execute('INSERT INTO messages(target,sender,text,status,unread,metadata) VALUES(?,?,?,?,?,?)',
                        (target, sender, text, status, unread, json.dumps(meta)))
        self.db.commit()

    def update_repeats(self, packet):
        rows = self.db.execute("SELECT id,metadata FROM messages WHERE target=? AND sender='me' AND deleted=0 ORDER BY id DESC LIMIT 100", (packet['target'],)).fetchall()
        for mid, raw in rows:
            meta = json.loads(raw)
            if meta.get('sender_timestamp') == packet['sender_timestamp']:
                meta['repeats'] = packet['repeats']
                count = packet['repeats']
                self.db.execute('UPDATE messages SET metadata=?,status=? WHERE id=?', (json.dumps(meta), f"Heard {count} repeat" + ("s" if count != 1 else ""), mid))
                self.db.commit()
                break

    async def receive(self, target, sender, text, private, metadata=None):
        label = self.display_sender(sender, text)
        if self.db.execute('SELECT 1 FROM blocked WHERE target=? AND sender=?', (target, label)).fetchone():
            return
        self.save(target, sender, text[:4096], 'received', 1, metadata)
        if not private:
            await channel_settings.notify(self, target, text)
        # Private-channel access is based on possession of its key, not display-name identity.
        prompt = text.split(': ', 1)[1] if ': ' in text else text
        name = next((c['name'] for c in self.radio.channels if c['id'] == target), '')
        token = (target, (metadata or {}).get('sender_timestamp'), text)
        command = prompt[len(self.config['llm']['prefix']):].strip() if prompt.startswith(self.config['llm']['prefix']) else ''
        if prompt.strip() == '/commands': command = '/commands'
        if (not private and target in self.radio.private_channels and name in self.config['llm'].get('private_channels', [])
                and self.config['llm']['enabled'] and self.config['radio']['allow_transmit'] and token not in self.ai_seen
                and label != self.radio.node.get('identity', {}).get('name')
                and (command in ('models','status','use','context','reset','/commands') or command.startswith(('use ', 'context ')))):
            self.ai_seen.add(token)
            if len(self.ai_seen)>1000: self.ai_seen={token}
            was_busy = self.ai_busy
            if command not in ('status','/commands') and not was_busy: self.ai_busy=True
            task=asyncio.create_task(self.run_model_command(target,command,was_busy,label))
            task.channel_target = target
            self.ai_tasks.add(task);task.add_done_callback(self.ai_tasks.discard)
            return
        if (not private and target in self.radio.private_channels and name in self.config['llm'].get('private_channels', [])
                and self.config['llm']['enabled'] and label != self.radio.node.get('identity', {}).get('name')):
            if token in self.ai_seen: return
            part_text = prompt[len(self.config['llm']['prefix']):] if prompt.startswith(self.config['llm']['prefix']) else prompt
            assembled = self.assembler.accept(target, label, part_text)
            if assembled is None:
                self.ai_seen.add(token)
                return
            if assembled != part_text: prompt = self.config['llm']['prefix'] + assembled
        if self.model_commands.plain_chat and not prompt.startswith(self.config['llm']['prefix']):
            prompt = self.config['llm']['prefix'] + prompt
        admitted = (not private and label != self.radio.node.get('identity', {}).get('name') and target in self.radio.private_channels and token not in self.ai_seen
                    and self.config['radio']['allow_transmit'] and not self.ai_busy
                    and self.gateway.admit_channel(target, name, prompt))
        if admitted:
            if len(self.ai_seen) > 1000: self.ai_seen.clear()
            self.ai_seen.add(token)
            self.ai_busy = True
            task = asyncio.create_task(self.reply(target, self.config['llm']['prefix'] + prompt[len(self.config['llm']['prefix']):], label))
            task.channel_target = target
            self.ai_tasks.add(task)
            task.add_done_callback(self.ai_tasks.discard)

    async def command_send(self, target, lines):
        name = next((c['name'] for c in self.radio.channels if c['id']==target), '')
        if target not in self.radio.private_channels or name not in self.config['llm'].get('private_channels', []) or not self.config['llm']['enabled']:
            return
        for text in chunks(lines, min(150,self.config['radio']['max_message_bytes'])):
            status=await self.radio.send(target,text)
            self.save(target,'local AI',text,status,0)
            await asyncio.sleep(1)

    async def run_model_command(self, target, command, was_busy, sender="channel peer"):
        try:
            if command=='/commands':
                await self.command_send(target,['/commands - show commands', '@ai models - list models', '@ai use N - select/load model N', '@ai status - current model and busy/ready', '@ai context 128k - change context size', '@ai reset - clear your conversation memory', 'After selecting a model, send ordinary messages to chat.'])
            elif command=='status':
                size = await asyncio.to_thread(self.model_commands.context_status)
                await self.command_send(target,['Model: '+self.gateway.config['model'], 'Context: '+(str(size)+' tokens' if size else 'not loaded'), 'Busy' if was_busy else 'Ready'])
            elif was_busy:
                await self.command_send(target,['AI is busy. Try again when the current request finishes.'])
            elif command == 'reset':
                self.memory.reset(target,sender)
                await self.command_send(target,['Your conversation memory has been cleared.'])
            elif command == 'context' or command.startswith('context '):
                await self.command_send(target,['Checking context and reloading if needed…'])
                try:
                    identifier, size = await asyncio.to_thread(self.model_commands.change_context, command[7:].strip())
                    self.model_commands.select(identifier)
                    await self.command_send(target,['Context ready: '+str(size)+' tokens.'])
                except ValueError as exc:
                    await self.command_send(target,[str(exc)])
            elif command=='models':
                models=await asyncio.to_thread(self.model_commands.catalog)
                lines=self.model_commands.register(models)
                await self.command_send(target, (lines or ['No local chat models available.']) + ['Select with @ai use <number>'])
            else:
                number=command[3:].strip()
                key=self.model_commands.chosen(int(number)) if number.isdecimal() else None
                if key is None:
                    await self.command_send(target,['Unknown model number. Send @ai models first.'])
                    return
                await self.command_send(target,['Loading '+key+'…'])
                identifier=await asyncio.to_thread(self.model_commands.load,key)
                self.model_commands.select(identifier)
                await self.command_send(target,['Ready: '+identifier, 'Send ordinary messages here to chat.'])
        except Exception:
            await self.command_send(target,['Model command failed. Previous selection kept; check LM Studio.'])
        finally:
            if command not in ('status','/commands') and not was_busy: self.ai_busy=False

    async def reply(self, target, text, sender="channel peer"):
        try:
            question = text[len(self.config['llm']['prefix']):]
            remembering = self.config['llm'].get('conversation_memory', True)
            # UTF-8 bytes are a conservative size estimate, not a tokenizer count.
            budget = max(0, 4096 - self.config['llm']['max_output_tokens'] - len(question.encode('utf-8')) - 256)
            history = self.memory.read(target, sender, budget) if remembering else []
            answer = await asyncio.to_thread(self.gateway.complete, text, history)
            parts = split_reply(answer, self.config['radio']['max_message_bytes'])
            for index, part in enumerate(parts):
                name = next((c['name'] for c in self.radio.channels if c['id'] == target), '')
                if target not in self.radio.private_channels or name not in self.config['llm'].get('private_channels', []) or not self.config['llm']['enabled']:
                    raise ValueError('AI channel no longer authorized')
                status = await self.radio.send(target, part)
                self.save(target, 'local AI', part, status, 0)
                if index < len(parts)-1: await asyncio.sleep(10)
            if remembering: self.memory.append(target,sender,question,answer)
        except EmptyModelAnswer:
            self.save(target, 'system', 'AI returned no final answer. Try again or switch models with @ai use N.', 'error', 0)
            await self.command_send(target, ['AI returned no final answer. Try again or switch models with @ai use N.'])
        except Exception as exc:
            self.save(target, 'system', 'AI request failed (' + type(exc).__name__ + '); no retry scheduled.', 'error', 0)
        finally:
            self.ai_busy = False

    async def request(self, request):
        op = request.get('op')
        target = request.get('target', 'ch:0')
        if not isinstance(target, str):
            raise ValueError('Invalid target')
        channel_settings.prune(self.db)
        ai_result = None
        node_result = None
        settings_result = None
        added = None
        contact_result = None
        if op == 'ai_settings':
            ai_result = await ai_settings.act(self, request.get('channel', {}))
        elif op == 'node_settings':
            node_result = await node_settings.act(self.radio, request.get('channel', {}))
        elif op == 'channel_settings':
            settings_result = await channel_settings.act(self, request.get('channel', {}))
        elif op == 'contact_action':
            data = request.get('channel', {})
            key = data.get('key')
            if data.get('action') == 'favourite':
                if key not in self.radio.contacts:
                    raise ChannelError('Contact is no longer available.')
                if data.get('enabled'):
                    self.db.execute('INSERT OR IGNORE INTO favourites VALUES(?)', (key,))
                else:
                    self.db.execute('DELETE FROM favourites WHERE key=?', (key,))
                self.db.commit()
                contact_result = {'message': 'Favourite updated on this computer.'}
            else:
                contact_result = await contact_action(self.radio, data)
        elif op == 'channel_add':
            added = await self.radio.add_channel(request.get('channel', {}))
            if not added.get('existing'):
                await self.archive_channel(added['target'])
        elif op == 'send':
            text = request.get('text')
            if not isinstance(text, str):
                raise ValueError('Text must be a string')
            metadata = {}
            status = await self.radio.send(target, text, metadata)
            self.save(target, 'me', text, status, 0, metadata)
            for packet in self.radio.sent_packets:
                if packet['target'] == target and packet['sender_timestamp'] == metadata.get('sender_timestamp') and packet['repeats']:
                    self.update_repeats(packet)
        elif op == 'read':
            self.db.execute('UPDATE messages SET unread=0 WHERE target=?', (target,))
            self.db.commit()
        elif op in ('delete', 'block', 'unblock'):
            message_id = request.get('message_id')
            if type(message_id) is not int:
                raise ValueError('Invalid message id')
            row = self.db.execute('SELECT sender,text,status FROM messages WHERE id=? AND target=? AND deleted=0', (message_id,target)).fetchone()
            if row is None:
                raise ValueError('Message not found')
            sender = self.display_sender(row[0], row[1])
            if op == 'delete':
                self.db.execute('UPDATE messages SET deleted=1,unread=0 WHERE id=?', (message_id,))
            elif row[2] != 'received' or sender in ('unknown', 'channel peer'):
                raise ValueError('No blockable sender')
            elif op == 'block':
                self.db.execute('INSERT OR IGNORE INTO blocked VALUES(?,?)', (target,sender))
            else:
                self.db.execute('DELETE FROM blocked WHERE target=? AND sender=?', (target,sender))
            self.db.commit()
        elif op != 'snapshot':
            raise ValueError('Unknown operation')
        rows = self.db.execute('SELECT id,sender,text,status,metadata FROM messages WHERE target=? AND deleted=0 ORDER BY id DESC LIMIT 100', (target,)).fetchall()
        blocked = {r[0] for r in self.db.execute('SELECT sender FROM blocked WHERE target=?', (target,))}
        messages = []
        for mid, sender, text, status, metadata in reversed(rows):
            label = self.display_sender(sender, text)
            messages.append(dict(id=mid, sender=label, text=text, status=status, metadata=json.loads(metadata),
                                 blocked=label in blocked, can_block=status == 'received' and label not in ('unknown','channel peer')))
        state = self.radio.state
        if self.radio.client and not self.radio.client.is_connected:
            state = 'reconnecting · waiting for node'
        return dict(ok=True, state=state, message_byte_limit=self.config['radio']['max_message_bytes'], channels=[dict(c, favourite=c['id'][3:] in {r[0] for r in self.db.execute('SELECT key FROM favourites')}) for c in self.radio.channels] + heard_contacts.entries(self.db, self.radio.channels, self.display_sender), channel_added=added, contact_result=contact_result, settings_result=settings_result, node_result=node_result, ai_result=ai_result,
                    messages=messages,
                    unread=self.db.execute('SELECT COUNT(*) FROM messages WHERE unread=1 AND deleted=0').fetchone()[0],
                    ai='responding' if self.ai_busy else ('enabled · ' + ', '.join(self.config['llm'].get('private_channels', [])) if self.config['llm']['enabled'] else 'disabled'),
                    can_send=self.config['radio']['transport'] == 'demo' or (self.config['radio']['allow_transmit'] and state.startswith('connected')),
                    node=self.radio.node, map_nodes=map_nodes(self.radio))

    async def client(self, reader, writer):
        self.clients.add(writer)
        try:
            while line := await reader.readline():
                try:
                    req = json.loads(line)
                    if not isinstance(req, dict):
                        raise ValueError('Expected JSON object')
                    result = await self.request(req)
                except ChannelError as exc:
                    result = dict(ok=False, error=str(exc))
                except (ValueError, TypeError, KeyError):
                    result = dict(ok=False, error='Invalid request or send blocked; check target, length and RF lock.')
                except Exception:
                    result = dict(ok=False, error='Operation failed; delivery may be unknown. No automatic retry.')
                writer.write((json.dumps(result) + '\n').encode())
                await asyncio.wait_for(writer.drain(), 5)
        except (ValueError, ConnectionError, TimeoutError):
            pass
        finally:
            self.clients.discard(writer)
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass


async def serve(args):
    os.umask(0o077)
    config = tomllib.loads(Path(args.config).read_text())
    if args.demo:
        config['radio']['transport'] = 'demo'
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'meshcore-bridge'
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = (runtime / 'bridge.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    path = runtime / 'bridge.sock'
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'meshcore-bridge'
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    bridge = Bridge(config, state / ('demo.sqlite3' if args.demo else 'history.sqlite3'))
    connection_task = asyncio.create_task(maintain_connection(bridge.radio))
    path.unlink(missing_ok=True)
    server = await asyncio.start_unix_server(bridge.client, path=path, limit=16384)
    os.chmod(path, 0o600)
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    print('MeshCore bridge ready; ' + bridge.radio.state, flush=True)
    try:
        async with server:
            await stop.wait()
            for writer in list(bridge.clients):
                writer.close()
    finally:
        connection_task.cancel()
        await asyncio.gather(connection_task, return_exceptions=True)
        for task in bridge.ai_tasks:
            task.cancel()
        await asyncio.gather(*bridge.ai_tasks, return_exceptions=True)
        await bridge.radio.close()
        bridge.db.close()
        path.unlink(missing_ok=True)
        lock.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=str(Path.home() / '.config/meshcore-bridge/config.toml'))
    parser.add_argument('--demo', action='store_true')
    args = parser.parse_args()
    asyncio.run(serve(args))


if __name__ == '__main__':
    main()
