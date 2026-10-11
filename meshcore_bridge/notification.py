"""Generic clickable alert, launched in the desktop user session."""
import subprocess
from pathlib import Path


def main():
    proc = subprocess.Popen([
        'notify-send', '--app-name=Meshcore Atlas', '--expire-time=15000',
        '--action=default=Open app', '--', 'Meshcore Atlas',
        'New message received. Open the app to read it.'
    ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        action, _ = proc.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        proc.kill(); proc.communicate(); return
    if proc.returncode == 0 and action.strip() == 'default':
        location = Path.home()/'.local/share/meshcore-bridge/app-path'
        if location.exists():
            launcher = Path(location.read_text().strip())/'launch.py'
            if launcher.is_file():
                subprocess.Popen(['python3', str(launcher)], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)

if __name__ == '__main__':
    main()
