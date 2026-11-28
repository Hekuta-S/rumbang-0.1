"""Desdoblador de mallas para papercraft (estilo Pepakura).

Mesh: vértices 3D (mm), caras (polígonos convexos, normales hacia fuera), color por cara,
etiquetas opcionales por cara. unfold() reparte las caras en islas planas que caben en la hoja.
"""
import heapq
import math
import numpy as np


class Mesh:
    def __init__(self, name, verts, faces, colors, labels=None, shade=True):
        self.name = name
        self.v = np.array(verts, dtype=float)
        self.f = [list(f) for f in faces]
        self.col = [tuple(c[:3]) for c in colors]
        self.labels = labels or {}          # cara -> dict(text, color, size, sub)
        self.shade = shade
        self.n = []
        for f in self.f:
            p = self.v[f]
            n = np.zeros(3)
            for i in range(len(p)):
                a, b = p[i], p[(i + 1) % len(p)]
                n += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
            ln = np.linalg.norm(n)
            self.n.append(n / ln if ln > 1e-12 else np.array([0, 0, 1.0]))
        self.edges = {}                      # (a,b) ordenado -> [(cara, i)]
        for fi, f in enumerate(self.f):
            for i in range(len(f)):
                a, b = f[i], f[(i + 1) % len(f)]
                self.edges.setdefault((min(a, b), max(a, b)), []).append((fi, i))
        # quita caras degeneradas del todo
        self.area = []
        for f in self.f:
            p = self.v[f]
            s = 0.0
            for i in range(1, len(p) - 1):
                s += np.linalg.norm(np.cross(p[i] - p[0], p[i + 1] - p[0])) / 2
            self.area.append(s)

    def centroid(self, fi):
        return self.v[self.f[fi]].mean(axis=0)

    def dihedral(self, f1, f2):
        c = max(-1.0, min(1.0, float(np.dot(self.n[f1], self.n[f2]))))
        return math.degrees(math.acos(c))

    def convex(self, f1, f2):
        """True si la arista entre f1 y f2 es convexa (pliegue de monte visto desde la cara impresa)."""
        return float(np.dot(self.centroid(f2) - self.centroid(f1), self.n[f1])) < 1e-6


def rot90(d):
    return np.array([-d[1], d[0]])


def place_face(mesh, fi, a, b, pa, pb):
    """Coloca la cara fi en 2D dado que sus vértices a y b caen en pa y pb."""
    n = mesh.n[fi]
    va, vb = mesh.v[a], mesh.v[b]
    x3 = vb - va
    x3 = x3 / np.linalg.norm(x3)
    y3 = np.cross(n, x3)
    X = (pb - pa) / np.linalg.norm(pb - pa)
    Y = rot90(X)
    out = []
    for vi in mesh.f[fi]:
        d = mesh.v[vi] - va
        out.append(pa + X * float(np.dot(d, x3)) + Y * float(np.dot(d, y3)))
    return np.array(out)


def _axes(p):
    ax = []
    for i in range(len(p)):
        d = p[(i + 1) % len(p)] - p[i]
        ln = np.hypot(*d)
        if ln > 1e-9:
            ax.append(rot90(d) / ln)
    return ax


def overlap(p, q, eps=0.08):
    """SAT entre polígonos convexos; eps tolera contactos en el borde."""
    for ax in _axes(p) + _axes(q):
        a = p @ ax
        b = q @ ax
        if a.max() <= b.min() + eps or b.max() <= a.min() + eps:
            return False
    return True


class Island:
    def __init__(self):
        self.pos = {}            # cara -> np.array 2D
        self.joined = set()      # aristas (a,b) unidas dentro de la isla
        self.lo = np.array([1e9, 1e9])
        self.hi = np.array([-1e9, -1e9])


def unfold(mesh, max_w, max_h, color_penalty=0.6, split_colors=False):
    placed = {}
    islands = []
    order = sorted(range(len(mesh.f)), key=lambda i: -mesh.area[i])
    for seed in order:
        if seed in placed:
            continue
        isl = Island()
        f = mesh.f[seed]
        a, b = f[0], f[1]
        ln = np.linalg.norm(mesh.v[b] - mesh.v[a])
        pts = place_face(mesh, seed, a, b, np.array([0.0, 0.0]), np.array([ln, 0.0]))
        isl.pos[seed] = pts
        isl.lo, isl.hi = pts.min(axis=0), pts.max(axis=0)
        placed[seed] = isl
        heap = []

        def push(fi):
            ff = mesh.f[fi]
            for i in range(len(ff)):
                a, b = ff[i], ff[(i + 1) % len(ff)]
                key = (min(a, b), max(a, b))
                for g, _ in mesh.edges[key]:
                    if g == fi or g in placed or len(mesh.edges[key]) != 2:
                        continue
                    if split_colors and mesh.col[fi] != mesh.col[g]:
                        continue
                    ang = mesh.dihedral(fi, g)
                    score = 0.0 if ang < 0.5 else 1.0 + ang / 90.0
                    if mesh.col[fi] != mesh.col[g]:
                        score += color_penalty
                    heapq.heappush(heap, (score, -mesh.area[g], fi, g, i))

        push(seed)
        while heap:
            _, _, fi, g, i = heapq.heappop(heap)
            if g in placed:
                continue
            ff = mesh.f[fi]
            a, b = ff[i], ff[(i + 1) % len(ff)]
            pa, pb = isl.pos[fi][i], isl.pos[fi][(i + 1) % len(ff)]
            # en g la arista va al revés (b -> a)
            pts = place_face(mesh, g, b, a, pb, pa)
            lo = np.minimum(isl.lo, pts.min(axis=0))
            hi = np.maximum(isl.hi, pts.max(axis=0))
            w, h = hi - lo
            if not ((w <= max_w and h <= max_h) or (w <= max_h and h <= max_w)):
                continue
            plo, phi = pts.min(axis=0), pts.max(axis=0)
            bad = False
            for q in isl.pos.values():
                if q.min(axis=0)[0] > phi[0] or q.max(axis=0)[0] < plo[0] or q.min(axis=0)[1] > phi[1] or q.max(axis=0)[1] < plo[1]:
                    continue
                if overlap(pts, q):
                    bad = True
                    break
            if bad:
                continue
            isl.pos[g] = pts
            isl.lo, isl.hi = lo, hi
            isl.joined.add((min(a, b), max(a, b)))
            placed[g] = isl
            push(g)
        islands.append(isl)
    return islands


def orient(isl, max_w, max_h):
    """Gira la isla para que ocupe la menor caja posible (y quepa en la hoja)."""
    allp = np.vstack(list(isl.pos.values()))
    best = None
    for deg in range(0, 180, 2):
        t = math.radians(deg)
        R = np.array([[math.cos(t), -math.sin(t)], [math.sin(t), math.cos(t)]])
        q = allp @ R.T
        w, h = q.max(axis=0) - q.min(axis=0)
        fits = w <= max_w and h <= max_h
        key = (0 if fits else 1, w * h + h * 0.3)
        if best is None or key < best[0]:
            best = (key, R)
    R = best[1]
    for k in isl.pos:
        isl.pos[k] = isl.pos[k] @ R.T
    allp = np.vstack(list(isl.pos.values()))
    lo = allp.min(axis=0)
    for k in isl.pos:
        isl.pos[k] = isl.pos[k] - lo
    isl.size = allp.max(axis=0) - lo
