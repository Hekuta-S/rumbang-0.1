"""Sirve la versión web exportada (build/web) con los tipos MIME que necesita Godot (.wasm, .pck).

Uso: python tools/online/serve_web.py build/web 8060
La exportación es sin hilos, así que no hacen falta las cabeceras COOP/COEP.
"""

import functools
import http.server
import sys

TYPES = {".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **TYPES}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
    handler = functools.partial(Handler, directory=root)
    with http.server.ThreadingHTTPServer(("0.0.0.0", port), handler) as httpd:
        print(f"Sirviendo {root} en http://localhost:{port}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
