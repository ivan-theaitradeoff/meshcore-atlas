"""Bounded text-only localhost gateway. No tools, commands or redirects."""
import ipaddress
import json
import time
import urllib.request
from urllib.parse import urlsplit


class EmptyModelAnswer(ValueError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("LLM redirects are disabled")


class Gateway:
    def __init__(self, config):
        self.config = config
        url = urlsplit(config["endpoint"])
        try:
            local = ipaddress.ip_address(url.hostname).is_loopback
        except ValueError:
            local = False
        if not local or url.scheme != "http" or url.username or url.password or url.query or url.fragment:
            raise ValueError("LLM endpoint must be an HTTP loopback IP without credentials/query")
        if config["provider"] not in ("ollama", "openai"):
            raise ValueError("Unknown LLM provider")
        self.last = {}
        self.global_last = float('-inf')

    def admit(self, sender, text):
        c = self.config
        if not c["enabled"] or sender not in c["sender_allowlist"] or len(sender) != 64:
            return False
        if not text.startswith(c["prefix"]) or len(text) > c["max_input_chars"]:
            return False
        now = time.monotonic()
        if now - self.last.get(sender, float('-inf')) < c["per_sender_seconds"]:
            return False
        if now - self.global_last < c["global_seconds"]:
            return False
        self.last[sender] = self.global_last = now
        return True

    def admit_channel(self, target, name, text):
        c = self.config
        if not c['enabled'] or name not in c.get('private_channels', []): return False
        if not text.startswith(c['prefix']) or not text[len(c['prefix']):].strip() or len(text) > c['max_input_chars']: return False
        now = time.monotonic()
        if now - self.last.get(target, float('-inf')) < c['per_sender_seconds'] or now - self.global_last < c['global_seconds']: return False
        self.last[target] = self.global_last = now
        return True

    def complete(self, text, history=None):
        c = self.config
        prompt = text[len(c["prefix"]):]
        messages = [{"role": "system", "content": "Answer concisely in plain text, at most 1200 characters. Your answer may be split across short radio messages. You have no tools or access to this computer."}] + (history or []) + [{"role": "user", "content": prompt}]
        if c["provider"] == "ollama":
            path = "/api/chat"
            body = dict(model=c["model"], messages=messages, stream=False,
                        options={"num_predict": c["max_output_tokens"]})
        else:
            path = "/v1/chat/completions"
            body = dict(model=c["model"], messages=messages, stream=False,
                        max_tokens=c["max_output_tokens"], reasoning_effort="none", chat_template_kwargs={"enable_thinking": False})
        req = urllib.request.Request(c["endpoint"].rstrip('/') + path,
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(req, timeout=c["timeout_seconds"]) as response:
            data = response.read(65537)
        if len(data) > 65536:
            raise ValueError("LLM response too large")
        result = json.loads(data)
        answer = result["message"]["content"] if c["provider"] == "ollama" else result["choices"][0]["message"]["content"]
        answer = answer[:c["max_output_chars"]].strip()
        if not answer: raise EmptyModelAnswer("Model returned no final answer")
        return answer
