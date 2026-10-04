#!/usr/bin/env python3
"""Focus Mesh Atlas, or open one window if it is closed."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

project = Path(__file__).resolve().parent
runtime = Path(os.environ['XDG_RUNTIME_DIR'])
with (runtime / 'mesh-atlas-launch.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    def focus():
        clients = json.loads(subprocess.check_output(['hyprctl', '-j', 'clients']))
        for client in clients:
            if client.get('title', '').startswith('Mesh Atlas'):
                subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = ' + json.dumps('address:' + client['address']) + ' })'], check=True)
                return True
        return False
    if not focus():
        with (runtime / 'mesh-atlas-window.log').open('a') as log:
            subprocess.Popen(['quickshell', '-p', str(project / 'Preview.qml')], cwd=project,
                             stdout=log, stderr=log, start_new_session=True)
        for _ in range(50):
            time.sleep(.1)
            if focus():
                break
