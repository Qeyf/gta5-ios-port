"""Loopback asset tests must start without a working DNS resolver."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

FIXTURE = Path(__file__).with_name('asset_range_server.py')


class AssetFixtureStartup(unittest.TestCase):
    def test_loopback_startup_does_not_resolve_a_host_name(self):
        with tempfile.TemporaryDirectory() as directory:
            port = Path(directory) / 'port'
            program = '''import runpy, socket, socketserver, sys
def reject_dns(*args):
    raise AssertionError('Loopback fixture attempted reverse DNS')
socket.getfqdn = reject_dns
socketserver.BaseServer.serve_forever = lambda self: None
fixture, root, port = sys.argv[1:]
sys.argv = [fixture, root, port]
runpy.run_path(fixture, run_name='__main__')
'''
            result = subprocess.run([sys.executable, '-c', program, str(FIXTURE), directory, str(port)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertGreater(int(port.read_text()), 0)


if __name__ == '__main__':
    unittest.main()
