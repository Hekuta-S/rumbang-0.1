"""Pintor de texturas por WiFi: pinta encima de las armas en 3D desde el celular y hornea la tinta.

    python tools/texture_painter/server.py [--port 8765]

Abre en el navegador del Android la URL que imprime (PC y celular en la misma WiFi). La primera vez Windows
pregunta si deja pasar a Python por el firewall: permitir en redes privadas.

Qué hace:
  - Lista las armas de assets/models/weapons (y katana) y, de cada material, su textura de color.
  - El celular carga el .glb, pone encima la textura toon (assets/textures/toon/weapons/<nombre>.png) y deja
    pintar con el dedo o con lápiz sobre el modelo.
  - Guardar escribe la textura FINAL en assets/textures/toon/weapons/<nombre>.png (la que usa
    ToonWeapon.apply en el juego). Godot la reimporta al volver a enfocar el editor.
  - Lo pintado se guarda también aparte como capa transparente (pintura/capas/<nombre>.png) y la textura de
    antes de pintar se copia una sola vez a pintura/base/<nombre>.png: se puede seguir pintando otro día,
    borrar trazos sin dañar la base o volver atrás borrando la capa. pintura/ tiene .gdignore.

Seguridad: el servidor escucha en la red local y solo atiende con la clave aleatoria que va en la URL. Solo
lee modelos/texturas de armas y solo escribe dentro de assets/textures/toon/weapons/.
"""
import argparse
import glob
import json
import os
import re
import secrets
import shutil
import socket
import struct
import sys
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(ROOT, "assets", "models")
TOON = os.path.join(ROOT, "assets", "textures", "toon", "weapons")
PAINT = os.path.join(TOON, "pintura")
VENDOR = os.path.join(HERE, "vendor")
NAME_RE = re.compile(r"^[A-Za-z0-9_\-]+$")

THREE = "https://unpkg.com/three@0.169.0/"
VENDOR_FILES = {
    "three.module.js": THREE + "build/three.module.js",
    "GLTFLoader.js": THREE + "examples/jsm/loaders/GLTFLoader.js",
    "OrbitControls.js": THREE + "examples/jsm/controls/OrbitControls.js",
    "BufferGeometryUtils.js": THREE + "examples/jsm/utils/BufferGeometryUtils.js",
    "three-mesh-bvh.module.js": "https://unpkg.com/three-mesh-bvh@0.8.3/build/index.module.js",
}


def ensure_vendor():
    os.makedirs(VENDOR, exist_ok=True)
    for name, url in VENDOR_FILES.items():
        dst = os.path.join(VENDOR, name)
        if os.path.exists(dst):
            continue
        print("descargando %s" % url)
        data = urllib.request.urlopen(url, timeout=60).read()
        if name == "GLTFLoader.js":
            data = data.replace(b"'../utils/BufferGeometryUtils.js'", b"'./BufferGeometryUtils.js'")
        with open(dst, "wb") as f:
            f.write(data)


def read_gltf(path):
    b = open(path, "rb").read(20)
    n = struct.unpack("<I", b[12:16])[0]
    with open(path, "rb") as f:
        f.seek(20)
        return json.loads(f.read(n))


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def weapon_list():
    """Por arma: sus materiales con la textura de color que se pinta (mismo criterio que
    tools/toonify_weapon_textures.py: Godot extrae las imágenes al lado del glb como <glb>_<n>.png)."""
    paths = sorted(glob.glob(os.path.join(MODELS, "weapons", "**", "*.glb"), recursive=True)
                   + glob.glob(os.path.join(MODELS, "katana", "*.glb")))
    out = []
    for p in paths:
        try:
            g = read_gltf(p)
        except Exception as e:  # glb roto: se lista sin materiales
            print("no se pudo leer %s: %s" % (p, e))
            continue
        base = os.path.splitext(p)[0]
        imgs, tex = g.get("images", []), g.get("textures", [])

        def find(ref):
            if ref is None or ref.get("index", -1) >= len(tex):
                return None
            i = tex[ref["index"]].get("source")
            if i is None or i >= len(imgs):
                return None
            for ext in (".png", ".jpg", ".jpeg"):
                for key in (str(i), imgs[i].get("name", "?")):
                    c = "%s_%s%s" % (base, key, ext)
                    if os.path.exists(c):
                        return c
            return None

        mats = []
        for mi, m in enumerate(g.get("materials", [])):
            pbr = m.get("pbrMetallicRoughness", {})
            sg = m.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness", {})
            ref = pbr.get("baseColorTexture") or sg.get("diffuseTexture")
            alb = find(ref)
            if alb is None:
                continue
            name = os.path.splitext(os.path.basename(alb))[0]
            toon = os.path.join(TOON, name + ".png")
            mats.append({
                "index": mi,
                "name": m.get("name", "mat%d" % mi),
                "tex": name,
                "uv": (ref or {}).get("texCoord", 0),
                "has_toon": os.path.exists(toon),
                "painted": os.path.exists(os.path.join(PAINT, "capas", name + ".png")),
                "alpha": m.get("alphaMode", "OPAQUE"),
            })
        out.append({
            "name": os.path.splitext(os.path.basename(p))[0],
            "glb": rel(p),
            "kb": os.path.getsize(p) // 1024,
            "materials": mats,
        })
    return out


def texture_source(name):
    """Base sin pintar: la copia de antes de pintar, si no la toon actual, si no la extraída del glb."""
    for c in (os.path.join(PAINT, "base", name + ".png"), os.path.join(TOON, name + ".png")):
        if os.path.exists(c):
            return c
    for c in glob.glob(os.path.join(MODELS, "**", name + ".*"), recursive=True):
        if c.lower().endswith((".png", ".jpg", ".jpeg")):
            return c
    return None


def save_texture(name, final_png, layer_png):
    os.makedirs(os.path.join(PAINT, "base"), exist_ok=True)
    os.makedirs(os.path.join(PAINT, "capas"), exist_ok=True)
    gdignore = os.path.join(PAINT, ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    base_copy = os.path.join(PAINT, "base", name + ".png")
    if not os.path.exists(base_copy):
        src = texture_source(name)
        if src is None:
            raise ValueError("textura desconocida: %s" % name)
        if src.lower().endswith(".png"):
            shutil.copyfile(src, base_copy)
        else:  # jpg extraído: se guarda la base como png para que el navegador la cargue igual
            from PIL import Image
            Image.open(src).save(base_copy)
    dst = os.path.join(TOON, name + ".png")
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(final_png)
    os.replace(tmp, dst)
    with open(os.path.join(PAINT, "capas", name + ".png"), "wb") as f:
        f.write(layer_png)
    return rel(dst)


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # UDP: no envía nada, solo elige la interfaz de la LAN
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Handler(SimpleHTTPRequestHandler):
    key = ""
    # el registro de Windows a veces dice text/plain para .js y los módulos ES no cargan
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".js": "text/javascript", ".css": "text/css",
                      ".html": "text/html"}

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def log_message(self, fmt, *args):
        if "/api/save" in self.path or (args and str(args[1]) not in ("200", "304")):
            sys.stderr.write("%s\n" % (fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _authorized(self, q):
        return secrets.compare_digest(q.get("k", [""])[0], self.key)

    def _json(self, obj, code=200):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _file(self, path, ctype):
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path in ("/", "/index.html", "/app.js", "/style.css") or u.path.startswith("/vendor/"):
            return super().do_GET()  # la página en sí es pública; los datos piden la clave
        if not self._authorized(q):
            return self._json({"error": "clave incorrecta"}, 403)
        if u.path == "/api/weapons":
            return self._json(weapon_list())
        if u.path == "/api/glb":
            p = os.path.normpath(os.path.join(ROOT, q.get("p", [""])[0]))
            if not p.startswith(MODELS + os.sep) or not p.lower().endswith(".glb") or not os.path.exists(p):
                return self._json({"error": "glb no válido"}, 404)
            return self._file(p, "model/gltf-binary")
        if u.path in ("/api/base", "/api/layer"):
            name = q.get("t", [""])[0]
            if not NAME_RE.match(name):
                return self._json({"error": "nombre no válido"}, 400)
            if u.path == "/api/base":
                p = texture_source(name)
            else:
                p = os.path.join(PAINT, "capas", name + ".png")
                p = p if os.path.exists(p) else None
            if p is None:
                return self._json({"error": "no existe"}, 404)
            ctype = "image/png" if p.lower().endswith(".png") else "image/jpeg"
            return self._file(p, ctype)
        return self._json({"error": "no encontrado"}, 404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if not self._authorized(q):
            return self._json({"error": "clave incorrecta"}, 403)
        if u.path != "/api/save":
            return self._json({"error": "no encontrado"}, 404)
        name = q.get("t", [""])[0]
        n_final = int(q.get("nf", ["0"])[0])
        length = int(self.headers.get("Content-Length", "0"))
        if not NAME_RE.match(name) or length <= 0 or length > 64 << 20 or not 0 < n_final < length:
            return self._json({"error": "petición no válida"}, 400)
        body = self.rfile.read(length)
        final_png, layer_png = body[:n_final], body[n_final:]
        if not (final_png.startswith(b"\x89PNG") and layer_png.startswith(b"\x89PNG")):
            return self._json({"error": "no es png"}, 400)
        try:
            dst = save_texture(name, final_png, layer_png)
        except ValueError as e:
            return self._json({"error": str(e)}, 400)
        print("guardado %s (%d KB)" % (dst, len(final_png) // 1024))
        return self._json({"ok": True, "path": dst})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    sys.stdout.reconfigure(line_buffering=True)  # que la URL salga ya aunque la salida sea un pipe
    ensure_vendor()
    Handler.key = secrets.token_urlsafe(9)
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    url = "http://%s:%d/?k=%s" % (lan_ip(), args.port, Handler.key)
    print("\nPintor de texturas listo. Abre en el celular (misma WiFi):\n\n    %s\n" % url)
    try:
        import qrcode  # opcional: pip install qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.print_ascii(invert=True)
    except ImportError:
        pass
    print("Ctrl+C para cerrar.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
