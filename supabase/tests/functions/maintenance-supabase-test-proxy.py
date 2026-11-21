#!/usr/bin/env python3
"""Route the real Edge handler's Auth and REST calls to disposable CI services."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TARGETS = {
    "/auth/v1/": "http://127.0.0.1:9999",
    "/rest/v1/": "http://127.0.0.1:3000",
}

class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def do_OPTIONS(self):
        self.forward()

    def forward(self):
        target = next((base for prefix, base in TARGETS.items()
                       if self.path.startswith(prefix)), None)
        if target is None:
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in ("host", "connection", "content-length")}
        request = Request(target + self.path, data=body or None,
                          headers=headers, method=self.command)
        try:
            response = urlopen(request, timeout=20)
            status, payload, response_headers = response.status, response.read(), response.headers
        except HTTPError as error:
            status, payload, response_headers = error.code, error.read(), error.headers
        except URLError:
            self.send_error(502)
            return
        self.send_response(status)
        for key, value in response_headers.items():
            if key.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8001), Proxy).serve_forever()
