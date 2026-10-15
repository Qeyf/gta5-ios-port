"""Loopback HTTP range fixture for the production asset/cache integration test."""
import http.server
import pathlib
import re
import socketserver
import sys
import urllib.parse

root = pathlib.Path(sys.argv[1]).resolve()


class LoopbackServer(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer normally resolves its bound address with getfqdn(). The
        # loopback-only fixture needs no DNS and must not stall on a CI resolver.
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = (root / urllib.parse.unquote(self.path).lstrip("/")).resolve()
        if root not in path.parents or not path.is_file():
            self.send_error(404)
            return
        size = path.stat().st_size
        match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
        if not match:
            self.send_error(400)
            return
        start, end = map(int, match.groups())
        end = min(end, size - 1)
        if start > end:
            self.send_error(416)
            return
        self.send_response(206)
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        with path.open("rb") as file:
            file.seek(start)
            self.wfile.write(file.read(end - start + 1))


if __name__ == "__main__":
    server = LoopbackServer(("127.0.0.1", 0), Handler)
    pathlib.Path(sys.argv[2]).write_text(str(server.server_address[1]))
    server.serve_forever()
