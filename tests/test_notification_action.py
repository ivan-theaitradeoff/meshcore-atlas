import unittest
from unittest.mock import patch, MagicMock
from meshcore_bridge.notification import main

class NotificationAction(unittest.TestCase):
    def test_default_action_opens_launcher(self):
        alert=MagicMock(returncode=0)
        alert.communicate.return_value=('default\n',None)
        with patch('subprocess.Popen',side_effect=[alert,MagicMock()]) as start, patch('pathlib.Path.exists',return_value=True), patch('pathlib.Path.is_file',return_value=True), patch('pathlib.Path.read_text',return_value='/example/plugin'):
            main()
        self.assertIn('--action=default=Open app',start.call_args_list[0].args[0])
        self.assertEqual(start.call_args_list[1].args[0],['python3','/example/plugin/launch.py'])

    def test_dismiss_does_not_open(self):
        alert=MagicMock(returncode=0)
        alert.communicate.return_value=('',None)
        with patch('subprocess.Popen',return_value=alert) as start:main()
        self.assertEqual(start.call_count,1)
