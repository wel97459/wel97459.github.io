#!/usr/bin/env python3
"""
Minimal MeshCore Proxy Server (no external dependencies)
Exposes live data at http://your-server:8765/api/meshcore/...
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import urlopen
import json

INTERNAL_API = "http://192.168.1.27:8088"
PORT = 8787

class ProxyHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if self.path == "/api/meshcore/stats":
            try:
                with urlopen(f"{INTERNAL_API}/api/stats", timeout=6) as resp:
                    data = json.loads(resp.read())
                self._send_json(data)
            except Exception as e:
                self._send_json({"error": str(e)}, 502)

        elif self.path == "/api/meshcore/health":
            try:
                with urlopen(f"{INTERNAL_API}/api/health", timeout=6) as resp:
                    data = json.loads(resp.read())
                self._send_json(data)
            except Exception as e:
                self._send_json({"error": str(e)}, 502)

        elif self.path == "/api/meshcore/clients":
            try:
                with urlopen(f"{INTERNAL_API}/api/connected_clients", timeout=6) as resp:
                    data = json.loads(resp.read())
                self._send_json(data)
            except Exception as e:
                self._send_json({"error": str(e)}, 502)

        elif self.path == "/api/meshcore/status":
            try:
                with urlopen(f"{INTERNAL_API}/api/stats", timeout=6) as r1:
                    stats = json.loads(r1.read())
                with urlopen(f"{INTERNAL_API}/api/health", timeout=6) as r2:
                    health = json.loads(r2.read())
                with urlopen(f"{INTERNAL_API}/api/connected_clients", timeout=6) as r3:
                    clients = json.loads(r3.read())

                self._send_json({
                    "stats": stats,
                    "health": health,
                    "clients": clients,
                    "source": "live"
                })
            except Exception as e:
                self._send_json({"error": str(e)}, 502)
        else:
            self._send_json({"error": "Not found"}, 404)

    def log_message(self, format, *args):
        print(f"[MeshCore Proxy] {args[0]}")

if __name__ == "__main__":
    print(f"🚀 MeshCore Proxy listening on http://0.0.0.0:{PORT}")
    print("   Endpoints:")
    print("     /api/meshcore/stats")
    print("     /api/meshcore/health")
    print("     /api/meshcore/clients")
    print("     /api/meshcore/status   ← best for website")
    server = HTTPServer(("", PORT), ProxyHandler)
    server.serve_forever()