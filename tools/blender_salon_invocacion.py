"""Salón de invocación del modo mazmorras (Rumbang): salón del trono hecho PIEZA A PIEZA, aspecto PS3.

Uso (Blender 5.2, sin abrir nada):
  blender.exe -b --factory-startup --python tools/blender_salon_invocacion.py -- salon
  blender.exe -b --factory-startup --python tools/blender_salon_invocacion.py -- npcs
  blender.exe -b --factory-startup --python tools/blender_salon_invocacion.py -- all
Guarda blender_sources/salon_invocacion.blend (con este script como texto) y exporta a
assets/models/salon/:
  salon_trono.glb  — salón: losas, alfombra, estrado, trono, columnas, vigas, ventanas, estandartes,
                     antorchas y el círculo de invocación. AO horneada en el color de vértice 'Col'.
                     Objetos: salon_estructura (estático), salon_runas (líneas del círculo, brillan),
                     salon_llamas (llamas de velas/antorchas), salon_vidrieras (luz de luna).
  rey.glb / mago.glb — el rey y el mago sobre el cuerpo de Riva (riva-base.fbx): misma malla RivaBase y
                     esqueleto mixamo (el juego les pone la piel con CharacterLookApplier), con la ropa
                     modelada y pesada al esqueleto, y sus clips (idle, invocar, sorpresa...).
El NOMBRE del material decide la textura en Godot (DungeonHub._salon_material): salon_floor/stone ->
piedra, salon_brick -> ladrillo, salon_wood* -> madera, salon_carpet/velvet/banner -> tela, salon_gold
-> metal dorado, salon_glow* -> emisivo. Frente del salón (hacia la cámara) en -Y; el trono en +Y.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, Matrix, Quaternion, Euler
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = r"C:/Users/cabeu/Downloads/rumbang-0.1-main/rumbang-0.1-main"
OUT = os.path.join(ROOT, "assets", "models", "salon")
BLEND = os.path.join(ROOT, "blender_sources", "salon_invocacion.blend")
RIVA_FBX = os.path.join(ROOT, "assets", "models", "riva", "riva-base.fbx")
TAU = math.tau

# Colores lineales base (la textura de detalle y la AO los oscurecen en el juego)
PALETTE = {
    "salon_floor": (0.30, 0.28, 0.26), "salon_floor_dark": (0.19, 0.18, 0.17),
    "salon_stone": (0.34, 0.32, 0.30), "salon_stone_dark": (0.16, 0.15, 0.15),
    "salon_stone_circle": (0.13, 0.12, 0.15),
    "salon_brick": (0.36, 0.30, 0.26),
    "salon_wood": (0.20, 0.11, 0.06), "salon_wood_dark": (0.09, 0.05, 0.03),
    "salon_carpet": (0.40, 0.04, 0.05), "salon_velvet": (0.30, 0.03, 0.08),
    "salon_banner_red": (0.38, 0.03, 0.04), "salon_banner_blue": (0.03, 0.07, 0.26),
    "salon_gold": (0.85, 0.58, 0.20), "salon_iron": (0.08, 0.08, 0.09),
    "salon_wax": (0.80, 0.74, 0.58), "salon_paper": (0.66, 0.58, 0.42),
    "salon_glow_rune": (0.35, 0.75, 1.0), "salon_glow_flame": (1.0, 0.55, 0.16),
    "salon_glow_window": (0.35, 0.48, 0.85), "salon_glow_gem": (0.9, 0.12, 0.25),
    "salon_glow_ember": (1.0, 0.25, 0.05), "salon_glow_crystal": (0.75, 0.35, 1.0),
    "salon_glow_arena": (1.0, 0.22, 0.08), "salon_glow_night": (0.12, 0.2, 0.45),
    "salon_leather": (0.16, 0.08, 0.04), "salon_coal": (0.03, 0.03, 0.03), "salon_steel": (0.5, 0.52, 0.55),
}
GLOW = {k for k in PALETTE if "glow" in k}
## Tamaño de la proyección de UV (metros por repetición de textura) por familia de material
UV_TILE = {"salon_brick": 2.4, "salon_floor": 1.0, "salon_stone": 1.6, "salon_wood": 1.2, "default": 1.0}


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Base Color"].default_value = (*PALETTE[name], 1.0)
        b.inputs["Roughness"].default_value = 0.35 if name == "salon_gold" else 0.85
        if name in ("salon_gold", "salon_iron", "salon_steel"):
            b.inputs["Metallic"].default_value = 0.85
        if name in GLOW:
            b.inputs["Emission Color"].default_value = (*PALETTE[name], 1.0)
            b.inputs["Emission Strength"].default_value = 3.0
    return m


# ───────────────────────────── constructor de mallas ─────────────────────────────

class Builder:
    """Acumula primitivas en un bmesh con su lista de materiales; make() crea el objeto."""
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def add(self, bm2, m, smooth=False, mat_xform=None):
        """Pega bm2 (ya en su sitio) con el material m. bm2 se libera."""
        if mat_xform is not None:
            bmesh.ops.transform(bm2, matrix=mat_xform, verts=bm2.verts)
        idx = self.mi(m)
        for f in bm2.faces:
            f.material_index = idx
            f.smooth = smooth
        me = bpy.data.meshes.new("_tmp")
        bm2.to_mesh(me)
        bm2.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def make(self, col):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        _box_uv(self.bm, self.mats)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        ob = bpy.data.objects.new(self.name, me)
        col.objects.link(ob)
        return ob


def _box_uv(bm, mats):
    """UV por proyección de caja en coordenadas del mundo (metros / UV_TILE del material)."""
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        mname = mats[f.material_index] if f.material_index < len(mats) else ""
        tile = next((t for k, t in UV_TILE.items() if mname.startswith(k)), UV_TILE["default"])
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            if ax == 0:
                u, v = c.y, c.z
            elif ax == 1:
                u, v = c.x, c.z
            else:
                u, v = c.x, c.y
            l[uv].uv = (u / tile, v / tile)


def _bevel(bm, w, segs=1):
    if w > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=w, segments=segs, affect="EDGES", profile=0.5,
                        clamp_overlap=True)


def box(b, center, size, m, bevel=0.0, rot=(0, 0, 0), jitter=0.0, rnd=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if jitter and rnd:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * jitter
    _bevel(bm, bevel)
    M = Matrix.Translation(Vector(center)) @ Euler(rot).to_matrix().to_4x4()
    b.add(bm, m, mat_xform=M)


def cyl(b, base, radius, height, m, segs=12, r_top=None, smooth=True, caps=True, rot=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=radius,
                          radius2=radius if r_top is None else r_top, depth=height)
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((0, 0, height / 2)))
    _bevel(bm, bevel)
    M = Matrix.Translation(Vector(base))
    if rot is not None:
        M = M @ Euler(rot).to_matrix().to_4x4()
    b.add(bm, m, smooth=smooth, mat_xform=M)


def sphere(b, center, radius, m, sub=2, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    b.add(bm, m, smooth=True, mat_xform=Matrix.Translation(Vector(center)))


def prism(b, poly, z0, z1, m, M=None, bevel=0.0):
    """Polígono 2D (x, y) extruido de z0 a z1; M lo coloca."""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in poly]
    hi = [bm.verts.new((x, y, z1)) for x, y in poly]
    n = len(poly)
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel(bm, bevel)
    b.add(bm, m, mat_xform=M if M is not None else Matrix.Identity(4))


def annulus(b, center, r0, r1, z0, z1, m, segs=64, a0=0.0, a1=TAU):
    """Anillo (o arco de anillo) plano con grosor: líneas del círculo de invocación."""
    full = abs((a1 - a0) - TAU) < 1e-6
    bm = bmesh.new()
    rings = []
    cnt = segs if full else segs + 1
    for i in range(cnt):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((center[0] + r * c, center[1] + r * s, z)) for r, z in
                      ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
    last = cnt if full else cnt - 1
    for i in range(last):
        A, B = rings[i], rings[(i + 1) % cnt]
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((A[k], B[k], B[k2], A[k2]))
    if not full:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    b.add(bm, m)


def strip(b, p0, p1, width, z0, z1, m):
    """Línea recta con grosor sobre el suelo (para la estrella del círculo)."""
    p0, p1 = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = (p1 - p0)
    L = d.length
    ang = math.atan2(d.y, d.x)
    mid = (p0 + p1) / 2
    box(b, (mid.x, mid.y, (z0 + z1) / 2), (L, width, z1 - z0), m, rot=(0, 0, ang))


def cloth(b, x0, x1, ztop, zbot, y, m, seed, nx=8, nz=10, th=0.02, wave=0.05, notch=0.35, axis="x", sag=0.0):
    """Paño colgante con grosor (estandarte): ondea un poco, la punta inferior en V (notch)."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    ph = rnd.uniform(0, TAU)
    grid_f, grid_b = [], []
    for j in range(nz + 1):
        rf, rb = [], []
        t = j / nz
        for i in range(nx + 1):
            s = i / nx
            x = x0 + (x1 - x0) * s
            z = ztop + (zbot - ztop) * t
            z -= notch * t * (1.0 - abs(s - 0.5) * 2.0)   # punta en V abajo
            off = wave * math.sin(s * 3.1 + ph + t * 2.0) * (0.3 + t) + sag * math.sin(s * math.pi)
            if axis == "x":
                rf.append(bm.verts.new((x, y + off, z)))
                rb.append(bm.verts.new((x, y + off + th, z)))
            else:
                rf.append(bm.verts.new((y + off, x, z)))
                rb.append(bm.verts.new((y + off + th, x, z)))
        grid_f.append(rf)
        grid_b.append(rb)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((grid_f[j][i], grid_f[j + 1][i], grid_f[j + 1][i + 1], grid_f[j][i + 1]))
            bm.faces.new((grid_b[j][i], grid_b[j][i + 1], grid_b[j + 1][i + 1], grid_b[j + 1][i]))
    for j in range(nz):   # cantos
        for g0, g1, i in ((grid_f, grid_b, 0), (grid_f, grid_b, nx)):
            bm.faces.new((g0[j][i], g1[j][i], g1[j + 1][i], g0[j + 1][i]))
    for i in range(nx):
        for j in (0, nz):
            bm.faces.new((grid_f[j][i], grid_f[j][i + 1], grid_b[j][i + 1], grid_b[j][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    b.add(bm, m, smooth=True)


def arch_poly(w, h_side, h_top, segs=8):
    """Contorno de ventana ojival (x, z) centrada en x=0, base en z=0."""
    pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h_side)]
    for i in range(1, segs):
        t = i / segs
        a = t * math.pi / 2
        pts.append((w / 2 * math.cos(a) ** 0.8, h_side + (h_top - h_side) * math.sin(a)))
    pts.append((0.0, h_top))
    for i in range(segs - 1, 0, -1):
        t = i / segs
        a = t * math.pi / 2
        pts.append((-w / 2 * math.cos(a) ** 0.8, h_side + (h_top - h_side) * math.sin(a)))
    pts.append((-w / 2, h_side))
    return pts


def wall_panel(b, axis, fixed, a0, a1, z0, z1, m, step=0.5, inward=1.0):
    """Muro plano subdividido (para que la AO tenga resolución). axis 'x': muro a x = fixed."""
    bm = bmesh.new()
    na = max(1, int((a1 - a0) / step))
    nz = max(1, int((z1 - z0) / step))
    vs = []
    for j in range(nz + 1):
        row = []
        for i in range(na + 1):
            a = a0 + (a1 - a0) * i / na
            z = z0 + (z1 - z0) * j / nz
            row.append(bm.verts.new((fixed, a, z) if axis == "x" else (a, fixed, z)))
        vs.append(row)
    for j in range(nz):
        for i in range(na):
            f = bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # que la cara mire hacia dentro del salón
    for f in bm.faces:
        c = f.calc_center_median()
        inside = Vector((0, 3, 4)) - c
        if f.normal.dot(inside) < 0:
            f.normal_flip()
    b.add(bm, m)


# ───────────────────────────── salón ─────────────────────────────

HALL_X = 8.0          ## media anchura
HALL_Y0 = -8.0        ## muro de entrada
HALL_Y1 = 14.0        ## muro del trono
HALL_H = 9.0
CIRCLE = (0.0, 1.5)   ## centro del círculo de invocación (y en Blender)
CIRCLE_R = 2.7
DAIS_Y = 8.0          ## primer escalón del estrado
FLOOR_Z = 0.08        ## altura de la cara de las losas


def build_floor(b, rnd):
    tile = 1.0
    for ix in range(int(-HALL_X / tile), int(HALL_X / tile)):
        for iy in range(int(HALL_Y0 / tile), int(DAIS_Y / tile)):
            cx, cy = (ix + 0.5) * tile, (iy + 0.5) * tile
            if math.hypot(cx - CIRCLE[0], cy - CIRCLE[1]) < CIRCLE_R + 0.15:
                continue      # el círculo lleva su propio disco
            h = FLOOR_Z + rnd.uniform(-0.012, 0.012)
            m = "salon_floor_dark" if rnd.random() < 0.22 else "salon_floor"
            box(b, (cx + rnd.uniform(-0.01, 0.01), cy + rnd.uniform(-0.01, 0.01), h / 2),
                (tile - 0.035, tile - 0.035, h), m, bevel=0.018,
                rot=(rnd.uniform(-0.008, 0.008), rnd.uniform(-0.008, 0.008), rnd.uniform(-0.01, 0.01)))
    # anillo de losas curvas alrededor del círculo (rellena el hueco entre la cuadrícula y el disco)
    segs = 28
    for i in range(segs):
        a0, a1 = TAU * i / segs + 0.004, TAU * (i + 1) / segs - 0.004
        annulus(b, CIRCLE, CIRCLE_R + 0.06, CIRCLE_R + 1.2, 0.0, FLOOR_Z - 0.005, "salon_floor_dark", segs=3, a0=a0, a1=a1)
    # base oscura bajo todo (las juntas no dejan ver el vacío)
    box(b, (0, (HALL_Y0 + HALL_Y1) / 2, -0.05), (HALL_X * 2, HALL_Y1 - HALL_Y0, 0.1), "salon_stone_dark")


def build_carpet(b):
    z = FLOOR_Z + 0.012
    w = 1.1
    for y0, y1 in ((HALL_Y0 + 0.3, CIRCLE[1] - CIRCLE_R - 1.35), (CIRCLE[1] + CIRCLE_R + 1.35, DAIS_Y)):
        box(b, (0, (y0 + y1) / 2, z), (w * 2, y1 - y0, 0.022), "salon_carpet", bevel=0.006)
        for sx in (-1, 1):
            box(b, (sx * (w - 0.08), (y0 + y1) / 2, z + 0.006), (0.07, y1 - y0, 0.024), "salon_gold")
    # alfombra subiendo el estrado hasta el trono
    for k in range(3):
        y = DAIS_Y + k * 0.6
        zt = 0.25 * (k + 1)
        box(b, (0, y + 0.3, zt + 0.01), (w * 1.6, 0.62, 0.02), "salon_carpet")
        box(b, (0, y + 0.012, zt - 0.115), (w * 1.6, 0.02, 0.25), "salon_carpet")
    box(b, (0, DAIS_Y + 1.8 + 0.8, 0.76), (w * 1.6, 1.6, 0.02), "salon_carpet")


def build_circle(b_struct, b_runes, rnd):
    cx, cy = CIRCLE
    # disco de piedra oscura, un pelo hundido respecto a las losas
    cyl(b_struct, (cx, cy, 0.0), CIRCLE_R + 0.05, FLOOR_Z - 0.01, "salon_stone_circle", segs=64, smooth=False)
    # canto de piedra labrada
    annulus(b_struct, CIRCLE, CIRCLE_R - 0.02, CIRCLE_R + 0.1, 0.0, FLOOR_Z + 0.02, "salon_stone", segs=64)
    z0, z1 = FLOOR_Z - 0.01, FLOOR_Z + 0.004
    for r0, r1 in ((2.48, 2.56), (2.28, 2.32), (1.30, 1.36), (0.42, 0.47)):
        annulus(b_runes, CIRCLE, r0, r1, z0, z1, "salon_glow_rune", segs=72)
    # estrella de seis puntas (dos triángulos) inscrita en r = 2.28
    for k in range(2):
        pts = [(cx + 2.28 * math.cos(TAU * i / 3 + k * math.pi / 3 + math.pi / 2),
                cy + 2.28 * math.sin(TAU * i / 3 + k * math.pi / 3 + math.pi / 2)) for i in range(3)]
        for i in range(3):
            strip(b_runes, pts[i], pts[(i + 1) % 3], 0.05, z0, z1, "salon_glow_rune")
    # runas entre los dos anillos exteriores: trazos cortos con formas distintas
    n = 24
    for i in range(n):
        a = TAU * i / n
        r = 2.41
        c, s = math.cos(a), math.sin(a)
        t = Vector((-s, c))
        base = Vector((cx + r * c, cy + r * s))
        rad = Vector((c, s))
        shape = i % 4
        strokes = {
            0: [(-0.05, -0.05, 0.05, 0.05), (-0.05, 0.05, 0.05, -0.05)],
            1: [(0.0, -0.06, 0.0, 0.06), (-0.04, 0.02, 0.04, 0.02)],
            2: [(-0.05, -0.06, -0.05, 0.06), (-0.05, 0.06, 0.05, 0.0), (0.05, 0.0, -0.05, -0.06)],
            3: [(-0.05, 0.05, 0.05, 0.05), (0.0, 0.05, 0.0, -0.06)],
        }[shape]
        for tx0, rr0, tx1, rr1 in strokes:
            p0 = base + t * tx0 + rad * rr0
            p1 = base + t * tx1 + rad * rr1
            strip(b_runes, p0, p1, 0.018, z0, z1 + 0.001, "salon_glow_rune")
    # glifos sueltos en el anillo medio (entre la estrella y el anillo de 1.33)
    for i in range(6):
        a = TAU * i / 6 + math.pi / 6 + math.pi / 2
        p = Vector((cx + 1.75 * math.cos(a), cy + 1.75 * math.sin(a)))
        annulus(b_runes, (p.x, p.y), 0.13, 0.16, z0, z1, "salon_glow_rune", segs=20)
        sphere(b_runes, (p.x, p.y, z0), 0.05, "salon_glow_rune", sub=1, scale=(1, 1, 0.15))


def build_candles(b_struct, b_flames, rnd):
    cx, cy = CIRCLE
    for i in range(8):
        a = TAU * i / 8 + TAU / 16
        r = CIRCLE_R + 0.55
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        # candelabro de hierro bajo con tres velas
        cyl(b_struct, (x, y, FLOOR_Z), 0.16, 0.04, "salon_iron", segs=10)
        cyl(b_struct, (x, y, FLOOR_Z + 0.04), 0.025, 0.5, "salon_iron", segs=6)
        cyl(b_struct, (x, y, FLOOR_Z + 0.54), 0.13, 0.03, "salon_iron", segs=10, r_top=0.15)
        for k in range(3):
            aa = TAU * k / 3 + a
            px, py = x + 0.07 * math.cos(aa), y + 0.07 * math.sin(aa)
            h = rnd.uniform(0.12, 0.26)
            cyl(b_struct, (px, py, FLOOR_Z + 0.57), 0.028, h, "salon_wax", segs=8)
            sphere(b_flames, (px, py, FLOOR_Z + 0.57 + h + 0.035), 0.022, "salon_glow_flame", sub=1, scale=(1, 1, 2.0))


def build_dais_and_throne(b, b_flames, b_gems):
    # tres escalones de piedra, bloques sueltos
    rnd = random.Random(3)
    for k in range(3):
        y0 = DAIS_Y + k * 0.6
        z = 0.25 * (k + 1)
        w = 9.0 - k * 0.8
        nblk = int(w / 1.2)
        for i in range(nblk):
            x0 = -w / 2 + i * w / nblk
            box(b, (x0 + w / nblk / 2, (y0 + HALL_Y1) / 2, z - 0.125 + 0.0),
                (w / nblk - 0.02, HALL_Y1 - y0, 0.25), "salon_stone", bevel=0.02,
                rot=(0, 0, rnd.uniform(-0.003, 0.003)))
    # trono (madera oscura, oro y terciopelo); centro del asiento en (0, 11.0)
    tz = 0.75
    ty = 11.0
    box(b, (0, ty, tz + 0.12), (1.5, 1.2, 0.24), "salon_stone_dark", bevel=0.03)                 # peana
    box(b, (0, ty, tz + 0.5), (1.15, 0.95, 0.5), "salon_wood_dark", bevel=0.02)                   # caja del asiento
    box(b, (0, ty - 0.05, tz + 0.8), (1.05, 0.85, 0.12), "salon_velvet", bevel=0.05)              # cojín
    box(b, (0, ty - 0.49, tz + 0.5), (1.18, 0.04, 0.42), "salon_gold", bevel=0.008)               # frontal dorado
    # respaldo alto con remate en punta
    back = [(-0.6, 0.0), (0.6, 0.0), (0.6, 2.1), (0.3, 2.45), (0.0, 2.9), (-0.3, 2.45), (-0.6, 2.1)]
    M = Matrix.Translation((0, ty + 0.42, tz + 0.75)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    prism(b, back, -0.08, 0.08, "salon_wood_dark", M=M, bevel=0.015)
    inner = [(-0.42, 0.15), (0.42, 0.15), (0.42, 1.85), (0.0, 2.35), (-0.42, 1.85)]
    M2 = Matrix.Translation((0, ty + 0.33, tz + 0.75)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    prism(b, inner, -0.02, 0.02, "salon_velvet", M=M2, bevel=0.006)
    # marco dorado del respaldo
    for i in range(len(back)):
        p0, p1 = back[i], back[(i + 1) % len(back)]
        if i == 0:
            continue
        a = Vector((p0[0], ty + 0.33, tz + 0.75 + p0[1]))
        c = Vector((p1[0], ty + 0.33, tz + 0.75 + p1[1]))
        mid = (a + c) / 2
        d = c - a
        ang = math.atan2(d.z, d.x)
        box(b, mid, (d.length + 0.05, 0.05, 0.06), "salon_gold", rot=(0, -ang, 0))
    # brazos con pomos
    for sx in (-1, 1):
        box(b, (sx * 0.62, ty, tz + 1.05), (0.14, 0.95, 0.1), "salon_wood_dark", bevel=0.02)
        box(b, (sx * 0.62, ty - 0.38, tz + 0.78), (0.12, 0.12, 0.5), "salon_wood_dark", bevel=0.015)
        sphere(b, (sx * 0.62, ty - 0.47, tz + 1.13), 0.085, "salon_gold", sub=2)
        sphere(b, (sx * 0.6, ty + 0.42, tz + 2.95), 0.07, "salon_gold", sub=2)
        cyl(b, (sx * 0.6, ty + 0.42, tz + 0.75), 0.07, 2.15, "salon_wood_dark", segs=8)
    sphere(b, (0, ty + 0.42, tz + 3.72), 0.11, "salon_gold", sub=2)
    sphere(b_gems, (0, ty + 0.33, tz + 3.05), 0.09, "salon_glow_gem", sub=2, scale=(1, 0.5, 1.3))


def build_pillar(b, x, y, rnd):
    box(b, (x, y, 0.3), (1.1, 1.1, 0.6), "salon_stone", bevel=0.03)
    box(b, (x, y, 0.68), (0.92, 0.92, 0.16), "salon_stone", bevel=0.03)
    cyl(b, (x, y, 0.76), 0.40, 6.4, "salon_stone", segs=8, r_top=0.36, smooth=False, bevel=0.02)
    # anillos tallados
    for z in (1.6, 5.9):
        cyl(b, (x, y, z), 0.43, 0.14, "salon_stone_dark", segs=8, smooth=False)
    box(b, (x, y, 7.25), (0.95, 0.95, 0.18), "salon_stone", bevel=0.03)
    box(b, (x, y, 7.5), (1.15, 1.15, 0.32), "salon_stone", bevel=0.04)


def build_torch(b, b_flames, pos, facing):
    """Antorcha en soporte de hierro sobre una columna. facing: dirección (x, y) hacia el salón."""
    x, y, z = pos
    fx, fy = facing
    box(b, (x, y, z), (0.16, 0.16, 0.3), "salon_iron", bevel=0.01)
    px, py = x + fx * 0.25, y + fy * 0.25
    box(b, ((x + px) / 2, (y + py) / 2, z + 0.05), (0.3 if fx else 0.05, 0.3 if fy else 0.05, 0.05), "salon_iron")
    cyl(b, (px, py, z - 0.1), 0.04, 0.55, "salon_wood", segs=6, rot=(fy * -0.25, fx * 0.25, 0))
    cyl(b, (px + fx * 0.06, py + fy * 0.06, z + 0.38), 0.075, 0.1, "salon_iron", segs=8, r_top=0.09)
    sphere(b_flames, (px + fx * 0.07, py + fy * 0.07, z + 0.58), 0.1, "salon_glow_flame", sub=2, scale=(1, 1, 1.9))


def build_walls(b, b_glass, b_flames, rnd):
    # muros de ladrillo (subdivididos) y zócalo de bloques grandes
    for sx in (-1, 1):
        wall_panel(b, "x", sx * HALL_X, HALL_Y0, HALL_Y1, 0.0, HALL_H, "salon_brick")
    wall_panel(b, "y", HALL_Y1, -HALL_X, HALL_X, 0.0, HALL_H, "salon_brick")
    wall_panel(b, "y", HALL_Y0, -HALL_X, HALL_X, 0.0, HALL_H, "salon_brick")
    # techo de madera con vigas
    box(b, (0, (HALL_Y0 + HALL_Y1) / 2, HALL_H + 0.05), (HALL_X * 2, HALL_Y1 - HALL_Y0, 0.1), "salon_wood_dark")
    for y in range(int(HALL_Y0) + 2, int(HALL_Y1), 4):
        box(b, (0, y, HALL_H - 0.3), (HALL_X * 2, 0.45, 0.6), "salon_wood", bevel=0.03)
    for x in (-6.2, 0.0, 6.2):
        box(b, (x, (HALL_Y0 + HALL_Y1) / 2, HALL_H - 0.75), (0.35, HALL_Y1 - HALL_Y0, 0.3), "salon_wood", bevel=0.03)
    # zócalo
    for sx in (-1, 1):
        y = HALL_Y0
        while y < HALL_Y1 - 0.01:
            L = min(rnd.uniform(0.9, 1.5), HALL_Y1 - y)
            box(b, (sx * (HALL_X - 0.12), y + L / 2, 0.4), (0.26, L - 0.02, 0.8), "salon_stone", bevel=0.025)
            y += L
    for yy, sgn in ((HALL_Y1, -1), (HALL_Y0, 1)):
        x = -HALL_X
        while x < HALL_X - 0.01:
            L = min(rnd.uniform(0.9, 1.5), HALL_X - x)
            box(b, (x + L / 2, yy + sgn * 0.12, 0.4), (L - 0.02, 0.26, 0.8), "salon_stone", bevel=0.025)
            x += L
    # columnas a los lados, con antorchas mirando al centro
    for y in (-5.0, -1.0, 3.0, 7.0, 11.0):
        for sx in (-1, 1):
            x = sx * 6.2
            build_pillar(b, x, y, rnd)
            if y in (-1.0, 3.0, 7.0):
                build_torch(b, b_flames, (x - sx * 0.42, y, 2.6), (-sx, 0))
            # arco de piedra entre la columna y el muro
            box(b, ((x + sx * HALL_X) / 2, y, 7.6), (abs(HALL_X - 6.2) + 0.2, 0.7, 0.5), "salon_stone", bevel=0.03)
    # ventanas ojivales en los muros laterales (entre columnas) y rosetón tras el trono
    for y in (-3.0, 1.0, 5.0, 9.0):
        for sx in (-1, 1):
            x = sx * (HALL_X - 0.02)
            poly = arch_poly(1.3, 2.4, 3.4)
            M = Matrix.Translation((x, y, 3.0)) @ Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
            prism(b_glass, [(px, pz) for px, pz in poly], -0.03, 0.03, "salon_glow_window", M=M)
            # marco y parteluz de piedra
            for i in range(len(poly)):
                p0, p1 = poly[i], poly[(i + 1) % len(poly)]
                a = Vector((p0[0], p0[1]))
                c = Vector((p1[0], p1[1]))
                mid = (a + c) / 2
                d = c - a
                ang = math.atan2(d.y, d.x)
                M3 = M @ Matrix.Translation((mid.x, mid.y, 0)) @ Matrix.Rotation(ang, 4, "Z")
                box(b, (0, 0, 0), (d.length + 0.12, 0.14, 0.24), "salon_stone", bevel=0.01)
                _move_last(b, M3)
            M4 = M @ Matrix.Translation((0, 1.6, 0))
            box(b, (0, 0, 0), (0.08, 3.2, 0.2), "salon_stone")
            _move_last(b, M4)
            M5 = M @ Matrix.Translation((0, 1.2, 0))
            box(b, (0, 0, 0), (1.3, 0.07, 0.2), "salon_stone")
            _move_last(b, M5)
    # rosetón
    rc = (0.0, HALL_Y1 - 0.03, 6.6)
    cyl(b_glass, rc, 1.4, 0.04, "salon_glow_window", segs=32, rot=(math.pi / 2, 0, 0), smooth=False)
    for r0, r1 in ((1.35, 1.6), (0.35, 0.5)):
        bm_ring = Builder("_r")
        annulus(bm_ring, (0, 0), r0, r1, -0.12, 0.12, "salon_stone", segs=32)
        _merge_builder(b, bm_ring, Matrix.Translation(rc) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    for k in range(8):
        a = TAU * k / 8
        M6 = Matrix.Translation(rc) @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Rotation(a, 4, "Z") @ Matrix.Translation((0.92, 0, 0))
        box(b, (0, 0, 0), (0.9, 0.08, 0.2), "salon_stone")
        _move_last(b, M6)


_last_verts = {}


def _move_last(b, M):
    """Mueve la última primitiva añadida a b (las caras nuevas están al final del bmesh)."""
    b.bm.verts.ensure_lookup_table()
    n0 = _last_verts.get(id(b), 0)
    new = b.bm.verts[n0:] if n0 < len(b.bm.verts) else []
    bmesh.ops.transform(b.bm, matrix=M, verts=list(new))


def _merge_builder(b, b2, M):
    bmesh.ops.transform(b2.bm, matrix=M, verts=b2.bm.verts)
    for f in b2.bm.faces:
        f.material_index = b.mi(b2.mats[f.material_index])
    me = bpy.data.meshes.new("_tmp")
    b2.bm.to_mesh(me)
    b2.bm.free()
    b.bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def build_banners(b, rnd):
    # tras el trono: dos estandartes rojos grandes y uno azul en el centro
    for x, m, h in ((-2.6, "salon_banner_red", 5.2), (2.6, "salon_banner_red", 5.2)):
        box(b, (x, HALL_Y1 - 0.25, 7.4), (1.8, 0.08, 0.08), "salon_gold")
        cloth(b, x - 0.8, x + 0.8, 7.35, 7.35 - h, HALL_Y1 - 0.32, m, seed=int(x * 10) + 5, wave=0.04)
        _emblem(b, (x, HALL_Y1 - 0.36, 7.35 - h * 0.35))
    # laterales entre columnas, colgando del muro
    for y in (-3.0, 1.0, 5.0):
        for sx in (-1, 1):
            if (y, sx) in ((1.0, 1), (5.0, -1)):
                continue
            x = sx * (HALL_X - 0.3)
            box(b, (x, y + 2.0, 6.9), (0.08, 1.4, 0.07), "salon_gold")
            cloth(b, y + 1.35, y + 2.65, 6.85, 3.3, x, "salon_banner_blue" if sx < 0 else "salon_banner_red",
                  seed=int(y * 7 + sx * 3 + 50), wave=0.03, axis="y", th=0.02 * -sx)


def _emblem(b, c):
    """Corona estilizada dorada en relieve sobre el estandarte."""
    x, y, z = c
    pts = [(-0.4, 0.0), (0.4, 0.0), (0.45, 0.45), (0.22, 0.22), (0.0, 0.55), (-0.22, 0.22), (-0.45, 0.45)]
    M = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    prism(b, pts, -0.015, 0.015, "salon_gold", M=M)


def build_props(b, b_flames, b_gems, rnd):
    # atril del mago con libro abierto, a la izquierda del círculo (x < 0 = izquierda de la cámara)
    lx, ly = -3.6, 0.6
    cyl(b, (lx, ly, FLOOR_Z), 0.28, 0.08, "salon_wood_dark", segs=8)
    cyl(b, (lx, ly, FLOOR_Z + 0.08), 0.06, 1.0, "salon_wood", segs=8)
    box(b, (lx, ly, FLOOR_Z + 1.12), (0.6, 0.45, 0.05), "salon_wood_dark", bevel=0.01, rot=(0.45, 0, 0.4))
    for sx in (-1, 1):
        box(b, (lx + sx * 0.13 * math.cos(0.4), ly + sx * 0.13 * math.sin(0.4), FLOOR_Z + 1.16), (0.26, 0.36, 0.025),
            "salon_paper", bevel=0.004, rot=(0.45, sx * -0.06, 0.4))
    # tinajas
    for (x, y, r) in ((-5.4, -6.9, 0.32), (-5.0, -7.3, 0.25), (5.0, 9.2, 0.3)):
        cyl(b, (x, y, FLOOR_Z), r, r * 2.2, "salon_stone_dark", segs=10, r_top=r * 0.55)
    # braseros a ambos lados del estrado
    for sx in (-1, 1):
        x, y = sx * 3.2, DAIS_Y - 0.6
        cyl(b, (x, y, FLOOR_Z), 0.3, 0.08, "salon_iron", segs=10)
        cyl(b, (x, y, FLOOR_Z + 0.08), 0.06, 0.9, "salon_iron", segs=6)
        cyl(b, (x, y, FLOOR_Z + 0.95), 0.18, 0.28, "salon_iron", segs=10, r_top=0.42)
        for k in range(5):
            a = TAU * k / 5
            sphere(b_flames, (x + 0.14 * math.cos(a), y + 0.14 * math.sin(a), FLOOR_Z + 1.32), 0.13,
                   "salon_glow_flame", sub=1, scale=(1, 1, 2.2))
        sphere(b_flames, (x, y, FLOOR_Z + 1.45), 0.19, "salon_glow_flame", sub=2, scale=(1, 1, 2.4))


def bake_ao(objs, dist=1.2, rays=25, strength=0.95, gamma=1.3, grime=(0.7, 0.9)):
    """AO por vértice contra todas las piezas (atributo 'Col', FLOAT_COLOR, POINT)."""
    verts, polys = [], []
    for ob in objs:
        mw = ob.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in ob.data.vertices]
        polys += [[base + i for i in p.vertices] for p in ob.data.polygons]
    tree = BVHTree.FromPolygons(verts, polys, all_triangles=False)
    rnd = random.Random(1)
    side = max(2, int(round(math.sqrt(rays))))
    dirs = []
    for i in range(side):
        for j in range(side):
            u1, u2 = (i + rnd.random()) / side, (j + rnd.random()) / side
            r = math.sqrt(u1)
            dirs.append(Vector((r * math.cos(TAU * u2), r * math.sin(TAU * u2), math.sqrt(max(0.0, 1.0 - u1)))))
    for ob in objs:
        me = ob.data
        mw = ob.matrix_world
        nm = mw.to_3x3().inverted().transposed()
        attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        me.color_attributes.active_color = attr
        emissive = {i for i, m in enumerate(me.materials) if m and "glow" in m.name}
        for i, v in enumerate(me.vertices):
            p = mw @ v.co
            n = (nm @ v.normal).normalized()
            t = n.orthogonal().normalized()
            b2 = n.cross(t)
            o = p + n * 0.004
            occ = 0.0
            for d in dirs:
                hit, _, _, dd = tree.ray_cast(o, t * d.x + b2 * d.y + n * d.z, dist)
                if hit is not None:
                    occ += 1.0 - dd / dist
            ao = max(0.0, 1.0 - strength * occ / len(dirs)) ** gamma
            g = min(1.0, max(0.0, p.z / grime[1]))
            ao *= grime[0] + (1.0 - grime[0]) * g * g * (3.0 - 2.0 * g)
            attr.data[i].color = (ao, ao, ao, 1.0)
        if emissive:
            for poly in me.polygons:
                if poly.material_index in emissive:
                    for vi in poly.vertices:
                        attr.data[vi].color = (1.0, 1.0, 1.0, 1.0)


class _VcMap(dict):
    """Arreglo del exportador glTF de Blender 5.2: con varios materiales, solo el primero exporta el color
    de vértice (los demás salen en blanco). Todo material usa COLOR_0 (ver dungeon_structures.py)."""
    def __setitem__(self, k, v):
        super().__setitem__(k, v if str(v).startswith("COLOR_") else "COLOR_0")


def _gltf(path, **kw):
    from io_scene_gltf2.blender.exp import primitive_extract as pe
    orig = pe.PrimitiveCreator.__init__

    def init(self, *a, **k):
        orig(self, *a, **k)
        self.material_idxs_using_vc = _VcMap()
    pe.PrimitiveCreator.__init__ = init
    try:
        bpy.ops.export_scene.gltf(filepath=path, **kw)
    finally:
        pe.PrimitiveCreator.__init__ = orig


def _collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    return col


class _Tracked(Builder):
    """Builder que recuerda dónde empieza cada primitiva (para _move_last)."""
    def add(self, bm2, m, smooth=False, mat_xform=None):
        _last_verts[id(self)] = len(self.bm.verts)
        super().add(bm2, m, smooth, mat_xform)


# ───────────────────────────── estaciones del salón (menú caminable) ─────────────────────────────
# Cada estación es un objeto del salón que el jugador visita andando (DungeonHub.STATIONS):
#   portón de entrada (salir), puerta de la arena (supervivencia), fragua con yunque y armero (armas de
#   la mazmorra), cofre (mejoras), atril con el libro de logros, mesa del escriba (ajustes) y bola de
#   cristal (multijugador LAN). Las hojas de las puertas y la tapa del cofre son objetos aparte con el
#   origen en la bisagra (el juego las gira).

def _pivoted(b, col, pivot):
    """Crea el objeto de b con el origen en `pivot` (bisagra)."""
    ob = b.make(col)
    pv = Vector(pivot)
    for v in ob.data.vertices:
        v.co -= pv
    ob.location = pv
    return ob


def _arch_frame(b, M, poly, depth, thick, m):
    for i in range(len(poly)):
        if i == 0:
            continue    # sin umbral abajo
        a = Vector(poly[i])
        c = Vector(poly[(i + 1) % len(poly)])
        mid = (a + c) / 2
        d = c - a
        ang = math.atan2(d.y, d.x)
        box(b, (0, 0, 0), (d.length + thick * 0.9, thick, depth), m, bevel=0.012)
        _move_last(b, M @ Matrix.Translation((mid.x, mid.y, 0)) @ Matrix.Rotation(ang, 4, "Z"))


def _door_leaf(col, name, hinge, width, height, top_curve, normal_axis, open_sign, rnd, arena=False):
    """Hoja de puerta de tablones con herrajes. hinge = bisagra (abajo); la hoja crece hacia `open_sign`
    a lo largo del muro. normal_axis 'x': muro en x = cte (la hoja va a lo largo de y)."""
    b = _Tracked(name)
    hx, hy, hz = hinge
    nplank = 5
    for i in range(nplank):
        um = (i + 0.5) / nplank * width
        # el arco de arriba: la hoja es más alta junto al centro de la puerta (lejos de la bisagra)
        t = um / width
        h = height - top_curve * (1.0 - t) ** 2
        if normal_axis == "x":
            c = (hx, hy + open_sign * um, hz + h / 2)
            sz = (0.09, width / nplank - 0.01, h)
        else:
            c = (hx + open_sign * um, hy, hz + h / 2)
            sz = (width / nplank - 0.01, 0.09, h)
        box(b, c, sz, "salon_wood_dark" if i % 2 else "salon_wood", bevel=0.01, jitter=0.004, rnd=rnd)
    for zz in (0.5, height * 0.5, height - top_curve - 0.3):
        if normal_axis == "x":
            box(b, (hx - 0.06, hy + open_sign * width / 2, hz + zz), (0.03, width - 0.06, 0.1), "salon_iron")
        else:
            box(b, (hx + open_sign * width / 2, hy + 0.06, hz + zz), (width - 0.06, 0.03, 0.1), "salon_iron")
    if normal_axis == "x":
        annulus(b, (0, 0), 0.07, 0.09, -0.012, 0.012, "salon_iron", segs=16)
        _move_last(b, Matrix.Translation((hx - 0.09, hy + open_sign * (width - 0.22), hz + height * 0.45)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    else:
        annulus(b, (0, 0), 0.08, 0.1, -0.012, 0.012, "salon_iron", segs=16)
        _move_last(b, Matrix.Translation((hx + open_sign * (width - 0.25), hy + 0.09, hz + height * 0.42)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    if arena:   # calavera de hierro en la hoja
        sphere(b, (hx - 0.07, hy + open_sign * width * 0.55, hz + height * 0.68) if normal_axis == "x" else
               (hx + open_sign * width * 0.55, hy + 0.07, hz + height * 0.68), 0.09, "salon_iron", sub=1, scale=(0.6, 1, 1))
    return _pivoted(b, col, hinge)


def build_exit_gate(st, glass, flames, col, rnd):
    """Portón de entrada (Salir) en el muro de la entrada (y = HALL_Y0), con arco de piedra."""
    w, h = 3.4, 4.6
    y = HALL_Y0 + 0.05
    poly = arch_poly(w + 0.3, h - 1.0, h + 0.35)
    M = Matrix.Translation((0, y + 0.14, FLOOR_Z)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    _arch_frame(st, M, poly, 0.5, 0.32, "salon_stone")
    # noche detrás de las hojas (se ve al abrir)
    prism(glass, arch_poly(w, h - 1.0, h + 0.2), -0.01, 0.01, "salon_glow_night",
          M=Matrix.Translation((0, y + 0.01, FLOOR_Z)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    leaves = [_door_leaf(col, "porton_izq", (-w / 2, y + 0.12, FLOOR_Z), w / 2, h, 0.9, "y", 1, rnd),
              _door_leaf(col, "porton_der", (w / 2, y + 0.12, FLOOR_Z), w / 2, h, 0.9, "y", -1, rnd)]
    for sx in (-1, 1):
        build_torch(st, flames, (sx * 2.5, y + 0.15, 2.9), (0, 1))
    return leaves


def build_arena_door(st, glass, flames, col, rnd):
    """Puerta de la arena (Supervivencia) en el muro derecho, entre columnas, con rótulo de espadas."""
    x = HALL_X - 0.05
    yc = 5.0
    w, h = 2.0, 3.4
    R = Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
    poly = arch_poly(w + 0.3, h - 0.7, h + 0.3)
    _arch_frame(st, Matrix.Translation((x - 0.14, yc, FLOOR_Z)) @ R, poly, 0.5, 0.3, "salon_stone_dark")
    prism(glass, arch_poly(w, h - 0.7, h + 0.15), -0.01, 0.01, "salon_glow_arena", M=Matrix.Translation((x - 0.01, yc, FLOOR_Z)) @ R)
    leaves = [_door_leaf(col, "puerta_arena_izq", (x - 0.12, yc - w / 2, FLOOR_Z), w / 2, h, 0.55, "x", 1, rnd, arena=True),
              _door_leaf(col, "puerta_arena_der", (x - 0.12, yc + w / 2, FLOOR_Z), w / 2, h, 0.55, "x", -1, rnd, arena=True)]
    # rótulo: escudo de hierro con dos espadas cruzadas
    zc = FLOOR_Z + h + 0.85
    cyl(st, (x - 0.2, yc, zc), 0.42, 0.06, "salon_iron", segs=16, rot=(0, -math.pi / 2, 0), smooth=False)
    cyl(st, (x - 0.24, yc, zc), 0.34, 0.03, "salon_banner_red", segs=16, rot=(0, -math.pi / 2, 0), smooth=False)
    for sgn in (-1, 1):
        box(st, (0, 0, 0), (0.05, 0.08, 1.15), "salon_steel", bevel=0.005)
        _move_last(st, Matrix.Translation((x - 0.3, yc, zc)) @ Matrix.Rotation(sgn * 0.75, 4, "X"))
        box(st, (0, 0, 0), (0.07, 0.36, 0.06), "salon_gold")
        _move_last(st, Matrix.Translation((x - 0.32, yc, zc)) @ Matrix.Rotation(sgn * 0.75, 4, "X") @ Matrix.Translation((0, 0, -0.33)))
    for sy in (-1, 1):
        build_torch(st, flames, (x - 0.15, yc + sy * 1.55, 2.4), (-1, 0))
    return leaves


def build_forge(st, flames, rnd):
    """Fragua con yunque, martillo y armero (estación de armas de la mazmorra)."""
    fx, fy = 6.0, 1.0
    box(st, (fx, fy, FLOOR_Z + 0.45), (1.3, 1.6, 0.9), "salon_stone", bevel=0.03)
    box(st, (fx - 0.05, fy, FLOOR_Z + 0.92), (1.0, 1.3, 0.06), "salon_coal", bevel=0.01)
    for i in range(14):
        sphere(flames, (fx - 0.05 + rnd.uniform(-0.4, 0.4), fy + rnd.uniform(-0.55, 0.55), FLOOR_Z + 0.97), rnd.uniform(0.05, 0.09),
               "salon_glow_ember", sub=1, scale=(1, 1, 0.55))
    sphere(flames, (fx - 0.05, fy, FLOOR_Z + 1.1), 0.22, "salon_glow_flame", sub=2, scale=(1.4, 2.0, 1.2))
    # campana y chimenea
    bm = bmesh.new()
    lo = [(-0.75, -0.95), (0.75, -0.95), (0.75, 0.95), (-0.75, 0.95)]
    hi = [(-0.3, -0.35), (0.3, -0.35), (0.3, 0.35), (-0.3, 0.35)]
    vl = [bm.verts.new((fx + x, fy + y, 2.3)) for x, y in lo]
    vh = [bm.verts.new((fx + x, fy + y, 3.5)) for x, y in hi]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vl[i], vl[j], vh[j], vh[i]))
    bm.faces.new(list(reversed(vl)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    st.add(bm, "salon_stone_dark")
    box(st, (fx, fy, (3.5 + HALL_H) / 2), (0.6, 0.7, HALL_H - 3.5), "salon_brick", bevel=0.02)
    for sy in (-1, 1):
        box(st, (fx - 0.55, fy + sy * 0.85, FLOOR_Z + 1.6), (0.18, 0.18, 1.5), "salon_stone", bevel=0.02)
    # fuelle
    box(st, (fx - 0.2, fy + 1.15, FLOOR_Z + 0.6), (0.5, 0.35, 0.12), "salon_leather", bevel=0.03, rot=(0, 0.2, 0))
    box(st, (fx - 0.45, fy + 1.15, FLOOR_Z + 0.62), (0.4, 0.06, 0.04), "salon_wood")
    # yunque sobre un tocón: perfil con cuerno, extruido
    ax, ay = 4.5, 1.0
    cyl(st, (ax, ay, FLOOR_Z), 0.32, 0.5, "salon_wood", segs=10, r_top=0.29)
    for k in range(6):
        a = TAU * k / 6
        box(st, (ax + 0.31 * math.cos(a), ay + 0.31 * math.sin(a), FLOOR_Z + 0.25), (0.03, 0.08, 0.5), "salon_wood_dark", rot=(0, 0, a))
    prof = [(-0.2, 0.0), (0.2, 0.0), (0.16, 0.09), (0.12, 0.17), (0.3, 0.23), (0.34, 0.31), (0.24, 0.33),
            (-0.26, 0.33), (-0.36, 0.3), (-0.6, 0.27), (-0.32, 0.22), (-0.14, 0.17), (-0.16, 0.09)]
    M = Matrix.Translation((ax, ay, FLOOR_Z + 0.5)) @ Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
    prism(st, prof, -0.12, 0.12, "salon_iron", M=M, bevel=0.012)
    box(st, (ax, ay + 0.02, FLOOR_Z + 0.84), (0.2, 0.5, 0.012), "salon_steel")
    # martillo y tenazas sobre el yunque
    cyl(st, (ax + 0.05, ay - 0.15, FLOOR_Z + 0.85), 0.018, 0.4, "salon_wood", segs=6, rot=(math.pi / 2, 0, 0.3))
    box(st, (ax + 0.03, ay - 0.16, FLOOR_Z + 0.88), (0.1, 0.07, 0.07), "salon_iron", rot=(0, 0, 0.3))
    for sgn in (-1, 1):
        box(st, (0, 0, 0), (0.02, 0.5, 0.02), "salon_iron")
        _move_last(st, Matrix.Translation((ax - 0.1, ay + 0.2, FLOOR_Z + 0.86)) @ Matrix.Rotation(0.6 + sgn * 0.05, 4, "Z"))
    # armero: bastidor de madera con tres soportes (el juego cuelga ahí la espalanza, las dagas y la maza)
    rx, ry = 4.9, 2.55
    for dy in (-0.75, 0.75):
        box(st, (rx, ry + dy, FLOOR_Z + 0.95), (0.12, 0.12, 1.9), "salon_wood", bevel=0.01)
    for z in (0.35, 1.0, 1.65):
        box(st, (rx, ry, FLOOR_Z + z), (0.1, 1.6, 0.08), "salon_wood_dark", bevel=0.01)
        for dy in (-0.45, 0.0, 0.45):
            cyl(st, (rx - 0.05, ry + dy, FLOOR_Z + z + 0.02), 0.015, 0.12, "salon_iron", segs=5, rot=(0, -math.pi / 2, 0))
    box(st, (rx, ry, FLOOR_Z + 1.95), (0.18, 1.8, 0.1), "salon_wood", bevel=0.015)


def build_chest(st, col, rnd):
    """Cofre del tesoro (Mejoras) con monedas; la tapa es aparte (cofre_tapa, bisagra atrás, hacia el muro)."""
    cx, cy = 5.0, -4.4
    w, d, h = 1.1, 0.65, 0.55
    box(st, (cx, cy, FLOOR_Z + h / 2), (d, w, h), "salon_wood", bevel=0.02)
    for yy in (-w / 2 + 0.12, 0.0, w / 2 - 0.12):
        box(st, (cx, cy + yy, FLOOR_Z + h / 2), (d + 0.02, 0.06, h + 0.01), "salon_iron")
    box(st, (cx - d / 2 - 0.01, cy, FLOOR_Z + h - 0.08), (0.03, 0.14, 0.16), "salon_gold")
    lid = _Tracked("cofre_tapa")
    hinge = (cx + d / 2, cy, FLOOR_Z + h)
    # medio cilindro a lo largo de y
    bm = bmesh.new()
    segs = 10
    ring_a, ring_b = [], []
    for i in range(segs + 1):
        a = math.pi * i / segs
        x, z = -math.cos(a) * d / 2, math.sin(a) * d / 2 * 0.7
        ring_a.append(bm.verts.new((cx + x, cy - w / 2, FLOOR_Z + h + z)))
        ring_b.append(bm.verts.new((cx + x, cy + w / 2, FLOOR_Z + h + z)))
    for i in range(segs):
        bm.faces.new((ring_a[i], ring_a[i + 1], ring_b[i + 1], ring_b[i]))
    bm.faces.new(ring_a)
    bm.faces.new(list(reversed(ring_b)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    lid.add(bm, "salon_wood", smooth=True)
    for yy in (-w / 2 + 0.12, 0.0, w / 2 - 0.12):
        bm = bmesh.new()
        ra, rb = [], []
        for i in range(segs + 1):
            a = math.pi * i / segs
            for lst, dy in ((ra, -0.03), (rb, 0.03)):
                x, z = -math.cos(a) * (d / 2 + 0.012), math.sin(a) * (d / 2 * 0.7 + 0.012)
                lst.append(bm.verts.new((cx + x, cy + yy + dy, FLOOR_Z + h + z)))
        for i in range(segs):
            bm.faces.new((ra[i], ra[i + 1], rb[i + 1], rb[i]))
        lid.add(bm, "salon_iron")
    lid_ob = _pivoted(lid, col, hinge)
    # monedas y un saco
    for i in range(26):
        a = rnd.uniform(0, TAU)
        r = rnd.uniform(0.0, 0.45)
        cyl(st, (cx - 0.75 + r * math.cos(a) * 0.6, cy + 0.2 + r * math.sin(a), FLOOR_Z + rnd.uniform(0, 0.06)), 0.045, 0.012,
            "salon_gold", segs=8, rot=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), 0), smooth=False)
    sphere(st, (cx - 0.3, cy - 0.85, FLOOR_Z + 0.22), 0.25, "salon_leather", sub=2, scale=(1, 1, 0.95))
    return lid_ob


def build_codex(st, flames):
    """Atril de piedra con el gran libro de logros, entre velas."""
    bx, by = -4.8, -5.2
    box(st, (bx, by, FLOOR_Z + 0.06), (0.7, 0.7, 0.12), "salon_stone", bevel=0.02)
    cyl(st, (bx, by, FLOOR_Z + 0.12), 0.16, 0.8, "salon_stone", segs=8, r_top=0.13, smooth=False)
    box(st, (bx, by, FLOOR_Z + 0.97), (0.62, 0.48, 0.08), "salon_stone", bevel=0.02, rot=(0.0, -0.35, 0))
    for sgn in (-1, 1):   # tapas y páginas abiertas
        box(st, (bx + 0.01, by + sgn * 0.17, FLOOR_Z + 1.04), (0.46, 0.33, 0.03), "salon_leather", bevel=0.006, rot=(sgn * 0.1, -0.35, 0))
        box(st, (bx + 0.01, by + sgn * 0.16, FLOOR_Z + 1.07), (0.42, 0.3, 0.04), "salon_paper", bevel=0.01, rot=(sgn * 0.14, -0.35, 0))
    box(st, (bx + 0.25, by + 0.05, FLOOR_Z + 1.0), (0.02, 0.025, 0.25), "salon_banner_red")
    for dy in (-0.55, 0.55):
        hh = 0.7 + dy * 0.2
        cyl(st, (bx + 0.15, by + dy, FLOOR_Z), 0.07, hh, "salon_iron", segs=6)
        cyl(st, (bx + 0.15, by + dy, FLOOR_Z + hh), 0.035, 0.16, "salon_wax", segs=8)
        sphere(flames, (bx + 0.15, by + dy, FLOOR_Z + hh + 0.2), 0.025, "salon_glow_flame", sub=1, scale=(1, 1, 2.0))


def build_desk(st, flames):
    """Mesa del escriba (Ajustes): pergaminos, tintero, pluma y una vela."""
    dx, dy = 4.4, 6.4
    box(st, (dx, dy, FLOOR_Z + 0.78), (0.9, 1.5, 0.07), "salon_wood", bevel=0.015)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(st, (dx + sx * 0.38, dy + sy * 0.66, FLOOR_Z + 0.38), (0.08, 0.08, 0.76), "salon_wood_dark", bevel=0.01)
    box(st, (dx - 0.05, dy - 0.1, FLOOR_Z + 0.82), (0.5, 0.65, 0.008), "salon_paper", rot=(0, 0, 0.12))
    for i, (yy, rr) in enumerate(((0.45, 0.05), (0.55, 0.04), (0.38, 0.035))):
        cyl(st, (dx + 0.15 - i * 0.12, dy + yy, FLOOR_Z + 0.81 + rr), rr, 0.45, "salon_paper", segs=10, rot=(0, math.pi / 2, 0.2 * i))
    cyl(st, (dx - 0.2, dy - 0.55, FLOOR_Z + 0.815), 0.05, 0.07, "salon_iron", segs=8, r_top=0.035)
    box(st, (0, 0, 0), (0.012, 0.03, 0.32), "salon_paper")
    _move_last(st, Matrix.Translation((dx - 0.17, dy - 0.53, FLOOR_Z + 0.98)) @ Matrix.Rotation(0.4, 4, "X"))
    cyl(st, (dx + 0.25, dy - 0.45, FLOOR_Z + 0.815), 0.06, 0.02, "salon_iron", segs=8)
    cyl(st, (dx + 0.25, dy - 0.45, FLOOR_Z + 0.835), 0.03, 0.18, "salon_wax", segs=8)
    sphere(flames, (dx + 0.25, dy - 0.45, FLOOR_Z + 1.05), 0.022, "salon_glow_flame", sub=1, scale=(1, 1, 2.0))
    box(st, (dx + 0.6, dy, FLOOR_Z + 0.45), (0.4, 0.45, 0.06), "salon_wood_dark", bevel=0.01)   # taburete
    for sx in (-1, 1):
        box(st, (dx + 0.6 + sx * 0.15, dy, FLOOR_Z + 0.21), (0.05, 0.4, 0.42), "salon_wood", bevel=0.005)


def build_crystal_ball(st, gems):
    """Pedestal con bola de cristal (Multijugador LAN)."""
    cx, cy = -4.4, 6.6
    box(st, (cx, cy, FLOOR_Z + 0.08), (0.8, 0.8, 0.16), "salon_stone", bevel=0.02)
    cyl(st, (cx, cy, FLOOR_Z + 0.16), 0.2, 0.75, "salon_stone_dark", segs=8, r_top=0.12, smooth=False)
    cyl(st, (cx, cy, FLOOR_Z + 0.91), 0.18, 0.08, "salon_gold", segs=12)
    for k in range(4):
        a = TAU * k / 4 + 0.4
        box(st, (0, 0, 0), (0.03, 0.03, 0.3), "salon_gold")
        _move_last(st, Matrix.Translation((cx + 0.17 * math.cos(a), cy + 0.17 * math.sin(a), FLOOR_Z + 1.07)) @
                   Matrix.Rotation(0.5, 4, Vector((-math.sin(a), math.cos(a), 0))))
    sphere(gems, (cx, cy, FLOOR_Z + 1.2), 0.24, "salon_glow_crystal", sub=3)


def build_portal_marks(runes):
    """Círculos de runas en el suelo donde el mago abre los portales (izquierda del salón)."""
    for y in (4.4, -2.6):
        c = (-4.7, y)
        z0, z1 = FLOOR_Z - 0.005, FLOOR_Z + 0.006
        for r0, r1 in ((0.95, 1.0), (0.7, 0.73)):
            annulus(runes, c, r0, r1, z0, z1, "salon_glow_rune", segs=40)
        for i in range(8):
            a = TAU * i / 8
            strip(runes, (c[0] + 0.75 * math.cos(a), c[1] + 0.75 * math.sin(a)),
                  (c[0] + 0.92 * math.cos(a + 0.2), c[1] + 0.92 * math.sin(a + 0.2)), 0.025, z0, z1, "salon_glow_rune")


def build_stations(st, runes, flames, glass, col, rnd):
    movers = []
    movers += build_exit_gate(st, glass, flames, col, rnd)
    movers += build_arena_door(st, glass, flames, col, rnd)
    build_forge(st, flames, rnd)
    movers.append(build_chest(st, col, rnd))
    build_codex(st, flames)
    build_desk(st, flames)
    build_crystal_ball(st, glass)
    build_portal_marks(runes)
    return movers


def build_salon():
    rnd = random.Random(7)
    col = _collection("Salon")
    st = _Tracked("salon_estructura")
    runes = _Tracked("salon_runas")
    flames = _Tracked("salon_llamas")
    glass = _Tracked("salon_vidrieras")
    build_floor(st, rnd)
    build_carpet(st)
    build_circle(st, runes, rnd)
    build_candles(st, flames, rnd)
    build_dais_and_throne(st, flames, glass)
    build_walls(st, glass, flames, rnd)
    build_banners(st, rnd)
    build_props(st, flames, glass, rnd)
    movers = build_stations(st, runes, flames, glass, col, rnd)
    objs = [bb.make(col) for bb in (st, runes, flames, glass)] + movers
    print("salon:", [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in objs])
    bake_ao(objs)
    return col, objs


def export_salon(objs):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    _gltf(os.path.join(OUT, "salon_trono.glb"), use_selection=True, export_format="GLB",
          export_materials="EXPORT", export_normals=True, export_texcoords=True, export_apply=True,
          export_yup=True, export_vertex_color="ACTIVE", export_animations=False)
    print("exportado", os.path.join(OUT, "salon_trono.glb"))


# ───────────────────────────── principal ─────────────────────────────

def _args():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def main():
    args = _args() or ["all"]
    if os.path.exists(BLEND):
        bpy.ops.wm.open_mainfile(filepath=BLEND)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    txt = bpy.data.texts.get("blender_salon_invocacion.py") or bpy.data.texts.new("blender_salon_invocacion.py")
    txt.from_string(open(__file__, encoding="utf-8").read())
    if "salon" in args or "all" in args:
        col, objs = build_salon()
        export_salon(objs)
    if "npcs" in args or "all" in args:
        import importlib
        build_npcs()
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("guardado", BLEND)


# ───────────────────────────── el rey y el mago ─────────────────────────────
# Cuerpo y esqueleto de Riva (riva-base.fbx). La ropa son mallas nuevas: la túnica de arriba sale de la
# piel del torso y los brazos (misma topología, empujada hacia fuera y con los pesos de la piel), la falda
# es un tubo con pliegues pesado a cadera y muslos, y el resto (capa, cuello de piel, corona, barbas,
# sombrero, bastón) se modela aparte y se pesa a un hueso. La piel tapada se BORRA del cuerpo.
# Las mallas RivaBase_<npc> conservan los materiales rb_* para que el juego les ponga la piel de Riva
# (CharacterLookApplier). El personaje mira a -Y; su izquierda es +X.

NPC_PALETTE = {
    "npc_robe_king": (0.30, 0.03, 0.05), "npc_robe_king_dark": (0.12, 0.015, 0.03),
    "npc_cape_king": (0.07, 0.03, 0.16), "npc_fur": (0.78, 0.74, 0.66), "npc_fur_spot": (0.03, 0.03, 0.03),
    "npc_gold": (0.85, 0.58, 0.2), "npc_beard_king": (0.34, 0.22, 0.13),
    "npc_robe_mage": (0.04, 0.08, 0.30), "npc_robe_mage_dark": (0.02, 0.03, 0.11), "npc_trim_mage": (0.66, 0.48, 0.16),
    "npc_beard_mage": (0.80, 0.78, 0.74), "npc_rope": (0.42, 0.32, 0.18), "npc_wood": (0.18, 0.1, 0.05),
    "npc_glow_crystal": (0.35, 0.75, 1.0), "npc_glow_gem": (0.9, 0.12, 0.25), "npc_leather": (0.12, 0.07, 0.04),
}
PALETTE.update(NPC_PALETTE)
GLOW.update({"npc_glow_crystal", "npc_glow_gem"})

B = "mixamorig:"
TORSO = {B + n for n in ("Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder")}
ARMS = {B + s + n for s in ("Left", "Right") for n in ("Arm", "ForeArm")}
HANDS = {g for g in ("mixamorig:LeftHand", "mixamorig:RightHand")}
LOWER = {B + n for n in ("Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg",
                         "RightFoot", "RightToeBase")}


def _import_riva(tag, height):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=RIVA_FBX)
    new = set(bpy.data.objects) - before
    arm = next(o for o in new if o.type == "ARMATURE")
    body = next(o for o in new if o.type == "MESH" and o.name.startswith("RivaBase"))
    for o in list(new):
        if o is not arm and o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    for i, m in enumerate(body.data.materials):     # el importador duplica rb_Piel -> rb_Piel.001
        base = bpy.data.materials.get(m.name.split(".")[0]) if m else None
        if base is not None and base is not m:
            body.data.materials[i] = base
    arm.name = tag.capitalize() + "Armature"
    arm.data.name = arm.name
    body.name = "RivaBase_" + tag
    col = _collection("NPC_" + tag)
    for o in (arm, body):
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    bpy.context.view_layer.update()
    h0 = max((body.matrix_world @ v.co).z for v in body.data.vertices)
    arm.scale = arm.scale * (height / h0)
    bpy.context.view_layer.update()
    return arm, body, col


def _weights(ob):
    names = {g.index: g.name for g in ob.vertex_groups}
    out = []
    for v in ob.data.vertices:
        out.append({names[g.group]: g.weight for g in v.groups if g.weight > 0.001})
    return out


def _dominant(w):
    return max(w.items(), key=lambda kv: kv[1])[0] if w else ""


def _make_skinned(name, bm, mats, weights, arm, col, smooth=True, solidify=0.0):
    """Objeto con armature, a partir de un bmesh en coordenadas del mundo y pesos por vértice (lista de
    dicts en el orden de bm.verts)."""
    b = Builder(name)
    b.bm.free()
    b.bm = bm
    b.mats = list(mats)
    for f in bm.faces:
        f.smooth = smooth
    ob = b.make(col)
    for vi, w in enumerate(weights):
        for g, x in w.items():
            vg = ob.vertex_groups.get(g) or ob.vertex_groups.new(name=g)
            vg.add([vi], x, "REPLACE")
    if solidify > 0.0:
        md = ob.modifiers.new("solid", "SOLIDIFY")
        md.thickness = solidify
        md.offset = -1.0
        md.use_rim = True
        with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
            bpy.ops.object.modifier_apply(modifier=md.name)
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()
    ob.matrix_world = mw
    md = ob.modifiers.new("Armature", "ARMATURE")
    md.object = arm
    return ob


def _single(bm2_fn, m, weight, store):
    """Primitiva (función que llena un Builder) pesada entera a un hueso; la añade a store (Builder, pesos)."""
    b, ws = store
    n0 = len(b.bm.verts)
    bm2_fn(b, m)
    ws.extend([{weight: 1.0}] * (len(b.bm.verts) - n0))


def build_robe(arm, body, col, cfg):
    """Túnica superior (de la piel) + falda + cinturón. Borra la piel tapada. Devuelve datos útiles."""
    mw = body.matrix_world
    W = _weights(body)
    me = body.data
    me.calc_loop_triangles()
    P = [mw @ v.co for v in me.vertices]
    nm = mw.to_3x3().inverted().transposed()
    N = [(nm @ v.normal).normalized() for v in me.vertices]
    dom = [_dominant(w) for w in W]
    hips_z = (arm.matrix_world @ arm.data.bones[B + "Hips"].head_local).z
    waist_z = hips_z + cfg["waist"]
    neck_z = (arm.matrix_world @ arm.data.bones[B + "Neck"].head_local).z
    head = {i for i, d in enumerate(dom) if d in (B + "Head", B + "Neck") and P[i].z > neck_z + 0.02}
    hand = {i for i, d in enumerate(dom) if d not in TORSO | ARMS | LOWER and i not in head}
    shell = {i for i, d in enumerate(dom) if (d in TORSO | ARMS or (d == B + "Neck" and P[i].z < neck_z + 0.03)
                                               or (d == B + "Hips" and P[i].z > waist_z - 0.04)) and i not in hand}
    lower = {i for i, d in enumerate(dom) if d in LOWER and i not in shell}

    # 1) túnica superior: caras de la piel con todos sus vértices en `shell`
    bm = bmesh.new()
    vmap = {}
    ws = []
    wrist = {s: (arm.matrix_world @ arm.data.bones[B + s + "Hand"].head_local) for s in ("Left", "Right")}
    elbow = {s: (arm.matrix_world @ arm.data.bones[B + s + "ForeArm"].head_local) for s in ("Left", "Right")}
    for i in sorted(shell):
        off = cfg["off_torso"]
        d = dom[i]
        if "ForeArm" in d:
            s = "Left" if "Left" in d else "Right"
            t = (P[i] - elbow[s]).length / max(1e-4, (wrist[s] - elbow[s]).length)
            off = cfg["off_arm"] + cfg["sleeve_flare"] * min(1.0, t) ** 2
        elif d.endswith("Arm"):
            off = cfg["off_arm"]
        p = P[i] + N[i] * off
        if cfg.get("belly", 0.0) and d in (B + "Spine", B + "Spine1", B + "Hips") and N[i].y < -0.2:
            k = math.exp(-((P[i].z - (hips_z + 0.16)) / 0.12) ** 2)
            p += Vector((0, -1, 0)) * cfg["belly"] * k * (-N[i].y)
        vmap[i] = bm.verts.new(p)
        ws.append(W[i])
    for tri in me.polygons:
        vs = tri.vertices
        if all(v in vmap for v in vs):
            try:
                bm.faces.new([vmap[v] for v in vs])
            except ValueError:
                pass
    loose = [v for v in bm.verts if not v.link_faces]
    keep = [i for i, v in zip(sorted(shell), bm.verts) if v.link_faces]
    ws = [W[i] for i in keep]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.verts.ensure_lookup_table()
    # tela, no piel: alisa los relieves del cuerpo (pecho, abdominales) sin mover los bordes
    inner = [v for v in bm.verts if not v.is_boundary]
    for _ in range(cfg.get("smooth", 10)):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    top = _make_skinned("Tunica_" + cfg["tag"], bm, [cfg["robe"]], ws, arm, col, solidify=0.012)

    # 2) falda: tubo con pliegues de la cintura al suelo
    band = [P[i] for i in range(len(P)) if abs(P[i].z - waist_z) < 0.05 and dom[i] in LOWER | TORSO]
    cx = sum(p.x for p in band) / len(band)
    cy = sum(p.y for p in band) / len(band)
    rx0 = max(abs(p.x - cx) for p in band) + cfg["off_torso"] + 0.03
    ry0 = max(abs(p.y - cy) for p in band) + cfg["off_torso"] + 0.03 + cfg.get("belly", 0.0) * 0.5
    rx1, ry1 = cfg["hem"]
    z0, z1 = 0.025, waist_z + 0.05
    segs, rows = 40, 14
    bm = bmesh.new()
    ws = []
    grid = []
    for j in range(rows + 1):
        t = j / rows                                # 0 arriba, 1 abajo
        z = z1 + (z0 - z1) * t
        e = t ** 0.75
        row = []
        for i in range(segs):
            a = TAU * i / segs
            fold = 1.0 + 0.045 * e * math.sin(a * 9 + 0.6) + 0.02 * e * math.sin(a * 23)
            rx = (rx0 + (rx1 - rx0) * e) * fold
            ry = (ry0 + (ry1 - ry0) * e) * fold
            x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
            if cfg.get("belly", 0.0) and math.sin(a) < 0 and t < 0.35:
                y -= cfg["belly"] * 0.6 * (1 - t / 0.35) * -math.sin(a)
            row.append(bm.verts.new((x, y, z)))
            side = max(-1.0, min(1.0, (x - cx) / max(rx, 1e-3)))
            wl = 0.55 * e * max(0.0, side) ** 1.5
            wr = 0.55 * e * max(0.0, -side) ** 1.5
            ws.append({B + "Hips": 1.0 - wl - wr, B + "LeftUpLeg": wl, B + "RightUpLeg": wr})
        grid.append(row)
    for j in range(rows):
        for i in range(segs):
            i2 = (i + 1) % segs
            bm.faces.new((grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]))
    skirt = _make_skinned("Falda_" + cfg["tag"], bm, [cfg["robe"]], ws, arm, col, solidify=0.014)
    # ribete del bajo (otro color)
    bm = bmesh.new()
    ws = []
    g2 = []
    for j, (tz, sc) in enumerate(((0.12, 1.005), (0.025, 1.0))):
        row = []
        for i in range(segs):
            a = TAU * i / segs
            fold = 1.0 + 0.045 * math.sin(a * 9 + 0.6) + 0.02 * math.sin(a * 23)
            rx, ry = rx1 * fold * sc + 0.006, ry1 * fold * sc + 0.006
            row.append(bm.verts.new((cx + rx * math.cos(a), cy + ry * math.sin(a), tz)))
            side = max(-1.0, min(1.0, math.cos(a)))
            wl, wr = 0.55 * max(0.0, side) ** 1.5, 0.55 * max(0.0, -side) ** 1.5
            ws.append({B + "Hips": 1.0 - wl - wr, B + "LeftUpLeg": wl, B + "RightUpLeg": wr})
        g2.append(row)
    for i in range(segs):
        i2 = (i + 1) % segs
        bm.faces.new((g2[0][i], g2[0][i2], g2[1][i2], g2[1][i]))
    _make_skinned("Ribete_" + cfg["tag"], bm, [cfg["trim"]], ws, arm, col, solidify=0.008)
    # cinturón
    bm = bmesh.new()
    ws = []
    rings = []
    for k, (dz, dr) in enumerate(((0.035, 0.0), (0.035, 0.022), (-0.035, 0.022), (-0.035, 0.0))):
        row = []
        for i in range(segs):
            a = TAU * i / segs
            row.append(bm.verts.new((cx + (rx0 + 0.005 + dr) * math.cos(a), cy + (ry0 + 0.005 + dr) * math.sin(a), z1 - 0.02 + dz)))
            ws.append({B + "Hips": 0.6, B + "Spine": 0.4})
        rings.append(row)
    for k in range(4):
        for i in range(segs):
            i2 = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][i2], rings[(k + 1) % 4][i2], rings[(k + 1) % 4][i]))
    _make_skinned("Cinto_" + cfg["tag"], bm, [cfg["belt"]], ws, arm, col)

    # 3) borra la piel que queda bajo la ropa (torso, brazos hasta la muñeca, piernas y pies)
    bmb = bmesh.new()
    bmb.from_mesh(me)
    bmb.verts.ensure_lookup_table()
    covered = shell | lower
    dead = [f for f in bmb.faces if all(v.index in covered for v in f.verts)]
    bmesh.ops.delete(bmb, geom=dead, context="FACES_ONLY")
    loose = [v for v in bmb.verts if not v.link_faces]
    bmesh.ops.delete(bmb, geom=loose, context="VERTS")
    bmb.to_mesh(me)
    bmb.free()
    # quita los materiales que ya no usa ninguna cara (calzones, elástico)
    used = sorted({p.material_index for p in me.polygons})
    keep_mats = [me.materials[i] for i in used]
    remap = {old: k for k, old in enumerate(used)}
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in keep_mats:
        me.materials.append(m)
    for p, k in zip(me.polygons, idx):
        p.material_index = k
    # cabeza: datos para los accesorios
    hp = [P[i] for i in head]
    info = {
        "head_top": max(p.z for p in hp), "head_bot": min(p.z for p in hp),
        "head_c": Vector((sum(p.x for p in hp) / len(hp), sum(p.y for p in hp) / len(hp), 0)),
        "head_front": min(p.y for p in hp), "head_back": max(p.y for p in hp),
        "head_rx": (max(p.x for p in hp) - min(p.x for p in hp)) / 2,
        "neck_z": neck_z, "waist_z": waist_z, "hips_z": hips_z, "skirt": (cx, cy, rx0, ry0, rx1, ry1, z1),
        "P": P, "dom": dom,
    }
    # barbilla: el punto más adelantado del tercio inferior de la cabeza
    low = [p for p in hp if p.z < info["head_bot"] + (info["head_top"] - info["head_bot"]) * 0.33]
    info["chin"] = min(low, key=lambda p: p.y) if low else Vector((0, info["head_front"], info["head_bot"]))
    return info


def _head_ring(b, info, z, r_scale, m, height, segs=32, points=0, point_h=0.0, flare=0.0):
    """Anillo alrededor de la cabeza a la altura z (corona / cinta del sombrero)."""
    c = info["head_c"]
    P = info["P"]
    band = [p for p, d in zip(P, info["dom"]) if d == B + "Head" and abs(p.z - z) < 0.015]
    rx = (max(p.x for p in band) - min(p.x for p in band)) / 2 * r_scale
    ry = (max(p.y for p in band) - min(p.y for p in band)) / 2 * r_scale
    cy = (max(p.y for p in band) + min(p.y for p in band)) / 2
    cx = (max(p.x for p in band) + min(p.x for p in band)) / 2
    bm = bmesh.new()
    rows = []
    for k, (dz, dr) in enumerate(((0, 0), (height, flare), (height, flare + 0.012), (0, 0.012))):
        row = []
        for i in range(segs):
            a = TAU * i / segs
            zz = z + dz
            if points and dz > 0:
                ph = (i % (segs // points)) / (segs // points)
                zz += point_h * max(0.0, 1.0 - abs(ph - 0.5) * 4.0)
            row.append(bm.verts.new((cx + (rx + dr) * math.cos(a), cy + (ry + dr) * math.sin(a), zz)))
        rows.append(row)
    for k in range(4):
        for i in range(segs):
            i2 = (i + 1) % segs
            bm.faces.new((rows[k][i], rows[k][i2], rows[(k + 1) % 4][i2], rows[(k + 1) % 4][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    b.add(bm, m, smooth=True)
    return cx, cy, rx, ry


def _beard(b, info, m, length, width, depth, seed, curl=0.0):
    """Barba: elipsoide deformado y con mechones, colgando de la barbilla hacia el pecho."""
    rnd = random.Random(seed)
    ch = info["chin"]
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        t = (1.0 - z) / 2.0             # 0 arriba, 1 punta
        w = width * (1.0 - 0.75 * t ** 1.6) * (1.0 + 0.08 * math.sin(math.atan2(y, x) * 7 + seed))
        dd = depth * (1.0 - 0.5 * t)
        zz = -length * t
        yy = y * dd - curl * t * t     # la punta se adelanta un poco
        if y > 0:                       # la parte de atrás se pega a la cara/cuello
            yy = y * dd * 0.35
        v.co = Vector((x * w, yy, zz + 0.03))
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 0.003
    b.add(bm, m, smooth=True, mat_xform=Matrix.Translation(ch + Vector((0, 0.012, 0.0))))
    # bigote
    for sx in (-1, 1):
        sphere(b, ch + Vector((sx * width * 0.45, -0.005, 0.045)), 0.022, m, sub=2, scale=(1.6, 0.6, 0.5))


def build_king(arm, body, col):
    cfg = dict(tag="rey", waist=0.1, off_torso=0.03, off_arm=0.026, sleeve_flare=0.02, belly=0.07,
               hem=(0.4, 0.36), robe="npc_robe_king", trim="npc_gold", belt="npc_gold")
    info = build_robe(arm, body, col, cfg)
    acc = Builder("Accesorios_rey")
    ws = []
    # corona: aro de oro con puntas, piedras y forro de terciopelo
    zc = info["head_top"] - (info["head_top"] - info["head_bot"]) * 0.2
    n0 = len(acc.bm.verts)
    cx, cy, rx, ry = _head_ring(acc, info, zc, 1.08, "npc_gold", 0.075, segs=40, points=8, point_h=0.06, flare=0.012)
    for k in range(8):
        a = TAU * k / 8 + TAU / 16
        sphere(acc, (cx + (rx + 0.016) * math.cos(a), cy + (ry + 0.016) * math.sin(a), zc + 0.035), 0.011,
               "npc_glow_gem" if k % 2 == 0 else "npc_gold", sub=1)
        a2 = TAU * k / 8
        sphere(acc, (cx + (rx + 0.01) * math.cos(a2), cy + (ry + 0.01) * math.sin(a2), zc + 0.142), 0.012, "npc_gold", sub=1)
    sphere(acc, (cx, cy, zc + 0.03), 1.0, "npc_robe_king", sub=2, scale=(rx * 0.98, ry * 0.98, 0.07))
    # barba castaña, poblada
    _beard(acc, info, "npc_beard_king", 0.17, 0.075, 0.05, seed=3, curl=0.03)
    ws = [{B + "Head": 1.0}] * (len(acc.bm.verts) - n0)
    # cuello de armiño sobre los hombros
    n1 = len(acc.bm.verts)
    nz = info["neck_z"]
    P, dom = info["P"], info["dom"]
    sh = [p for p, d in zip(P, dom) if d in (B + "LeftShoulder", B + "RightShoulder", B + "Spine2", B + "Neck")
          and abs(p.z - (nz - 0.02)) < 0.03]
    scx = sum(p.x for p in sh) / len(sh)
    scy = sum(p.y for p in sh) / len(sh)
    srx = max(abs(p.x - scx) for p in sh) * 0.62 + 0.06
    sry = max(abs(p.y - scy) for p in sh) + 0.07
    bm = bmesh.new()
    rows = []
    for j in range(7):
        a = math.pi * j / 6
        row = []
        for i in range(36):
            t = TAU * i / 36
            rr = 1.0 + 0.06 * math.sin(t * 11)
            r_off = 0.05 * math.sin(a)
            row.append(bm.verts.new((scx + (srx + r_off - 0.04 * math.cos(a)) * math.cos(t) * rr,
                                     scy + (sry + r_off - 0.04 * math.cos(a)) * math.sin(t) * rr,
                                     nz - 0.03 + 0.045 * math.cos(a) - 0.06 * (j / 6))))
        rows.append(row)
    for j in range(6):
        for i in range(36):
            i2 = (i + 1) % 36
            bm.faces.new((rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    acc.add(bm, "npc_fur", smooth=True)
    for k in range(10):   # motas negras del armiño
        t = TAU * k / 10 + 0.2
        sphere(acc, (scx + (srx + 0.05) * math.cos(t), scy + (sry + 0.05) * math.sin(t), nz - 0.04), 0.012,
               "npc_fur_spot", sub=1, scale=(1, 1, 1.6))
    acc.bm.verts.ensure_lookup_table()
    cnt = len(acc.bm.verts) - n1
    for vi in range(n1, len(acc.bm.verts)):
        x = acc.bm.verts[vi].co.x - scx
        side = max(-1.0, min(1.0, x / srx))
        wl, wr = 0.4 * max(0.0, side) ** 2, 0.4 * max(0.0, -side) ** 2
        ws.append({B + "Spine2": 1.0 - wl - wr, B + "LeftShoulder": wl, B + "RightShoulder": wr})
    acc_ob = _make_skinned("Accesorios_rey", acc.bm, acc.mats, ws, arm, col)
    # capa morada: cae de los hombros por la espalda hasta el suelo
    cx, cy, rx0, ry0, rx1, ry1, zt = info["skirt"]
    back = [p for p, d in zip(P, dom) if d in TORSO]
    bm = bmesh.new()
    ws = []
    rows = []
    nzr, nxr = 16, 12
    z_top = nz - 0.06
    for j in range(nzr + 1):
        t = j / nzr
        z = z_top + (0.03 - z_top) * t
        near = [p.y for p in back if abs(p.z - z) < 0.04 and abs(p.x) < 0.18]
        yb = max(near) if near else cy
        if z < zt:
            e = ((zt - z) / max(zt - 0.03, 1e-3)) ** 0.75
            yb = max(yb, cy + ry0 + (ry1 - ry0) * e)
        else:
            yb = max(yb, cy + ry0 * (1.0 - min(1.0, (z - zt) / 0.25)))
        half = 0.22 + 0.32 * t ** 0.8
        row = []
        for i in range(nxr + 1):
            s = i / nxr
            x = -half + 2 * half * s
            yy = yb + 0.045 + 0.06 * t + 0.08 * (abs(x) / half) ** 2 * -1.0 * t * 0.5
            yy += 0.025 * t * math.sin(s * 9.0)
            row.append(bm.verts.new((x, yy, z)))
            k = min(1.0, max(0.0, (z_top - z) / max(z_top - zt, 1e-3)))
            if z >= zt:
                ws.append({B + "Spine2": 1.0 - k * 0.7, B + "Spine": k * 0.7})
            else:
                ws.append({B + "Hips": 1.0})
        rows.append(row)
    for j in range(nzr):
        for i in range(nxr):
            bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    _make_skinned("Capa_rey", bm, ["npc_cape_king"], ws, arm, col, solidify=0.012)
    return info


def build_mage(arm, body, col):
    cfg = dict(tag="mago", waist=0.06, off_torso=0.025, off_arm=0.03, sleeve_flare=0.09, belly=0.0,
               hem=(0.33, 0.3), robe="npc_robe_mage", trim="npc_trim_mage", belt="npc_rope")
    info = build_robe(arm, body, col, cfg)
    acc = Builder("Accesorios_mago")
    # sombrero puntiagudo de ala ancha, con la punta doblada hacia atrás
    zc = info["head_top"] - (info["head_top"] - info["head_bot"]) * 0.28
    cx, cy, rx, ry = _head_ring(acc, info, zc, 1.1, "npc_trim_mage", 0.035, segs=32)
    bm = bmesh.new()
    rows = []
    brim = 0.17
    for j, (rr, dz) in enumerate(((brim + max(rx, ry), -0.005), (brim + max(rx, ry), 0.01), (rx + 0.01, 0.0))):
        row = []
        for i in range(32):
            a = TAU * i / 32
            wav = 0.012 * math.sin(a * 5) * (j < 2)
            row.append(bm.verts.new((cx + (rr if j < 2 else rx + 0.012) * math.cos(a), cy + (rr if j < 2 else ry + 0.012) * math.sin(a), zc + dz + wav - 0.01 * (j < 2))))
        rows.append(row)
    for j in range(2):
        for i in range(32):
            i2 = (i + 1) % 32
            bm.faces.new((rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]))
    for i in range(32):
        i2 = (i + 1) % 32
        bm.faces.new((rows[2][i], rows[2][i2], rows[0][i2], rows[0][i]))
    acc.add(bm, "npc_robe_mage", smooth=True)
    bm = bmesh.new()
    rows = []
    H = 0.42
    nrow = 12
    for j in range(nrow + 1):
        t = j / nrow
        r = 1.0 - t ** 0.9
        bend = 0.16 * t ** 2.2
        z = zc + 0.03 + H * t - 0.08 * t ** 3
        row = []
        for i in range(20):
            a = TAU * i / 20
            row.append(bm.verts.new((cx + (rx + 0.012) * r * math.cos(a), cy + bend + (ry + 0.012) * r * math.sin(a), z)))
        rows.append(row)
    for j in range(nrow):
        for i in range(20):
            i2 = (i + 1) % 20
            bm.faces.new((rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    acc.add(bm, "npc_robe_mage", smooth=True)
    for k, (tz, ta) in enumerate(((0.12, 0.8), (0.22, 2.6), (0.3, 4.4))):
        t = tz / H
        a = ta
        r = (1.0 - t ** 0.9) * (rx + 0.016)
        sphere(acc, (cx + r * math.cos(a), cy + 0.16 * t ** 2.2 + r * math.sin(a), zc + 0.03 + tz), 0.012, "npc_trim_mage", sub=1, scale=(1, 0.4, 1))
    # barba blanca larga hasta el pecho
    _beard(acc, info, "npc_beard_mage", 0.3, 0.07, 0.045, seed=8, curl=0.05)
    ws = [{B + "Head": 1.0}] * len(acc.bm.verts)
    _make_skinned("Accesorios_mago", acc.bm, acc.mats, ws, arm, col)
    return info


# ───────────────────────────── poses y clips ─────────────────────────────

FPS = 30


def _src_action(arm):
    ad = arm.animation_data
    return ad.action, ad.action_slot


def _set_action(arm, act, slot=None):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if act is not None:
        try:
            ad.action_slot = slot or act.slots[0]
        except Exception:
            pass


def _arm_dir(arm, d):
    return (arm.matrix_world.to_3x3().normalized().inverted() @ Vector(d)).normalized()


def _apply_override(arm, ov, w, i):
    """ov = (hueso, tipo, valor). Tipos: aim (apunta el hueso a una dirección del mundo), lean (gira el
    hueso sobre su cabeza alrededor del eje X del mundo; + = hacia delante), turn (eje Z del mundo),
    roll (eje Y del mundo; + = inclina a la izquierda del personaje), curl (rota en su X local)."""
    bone, kind, val = ov[0], ov[1], ov[2]
    pb = arm.pose.bones.get(B + bone)
    if pb is None or w <= 0.0:
        return
    if callable(val):
        val = val(i)
    if kind == "curl":
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(val) * w)
        bpy.context.view_layer.update()
        return
    cur = pb.matrix.copy()
    head = cur.translation.copy()
    if kind == "aim":
        y = cur.col[1].xyz.normalized()
        R = y.rotation_difference(_arm_dir(arm, val))
    else:
        axis = {"lean": (1, 0, 0), "turn": (0, 0, 1), "roll": (0, 1, 0)}[kind]
        R = Quaternion(_arm_dir(arm, axis), math.radians(val))
    Rw = Quaternion().slerp(R, w)
    pb.matrix = Matrix.Translation(head) @ Rw.to_matrix().to_4x4() @ Matrix.Translation(-head) @ cur
    bpy.context.view_layer.update()


def bake_clip(arm, src, name, n, overrides, weight=lambda i: 1.0, src_start=None, src_speed=1.0):
    """Clip `name` de n fotogramas: cada fotograma toma la pose de la acción fuente (idle de Riva) y le
    aplica `overrides` (lista de (hueso, tipo, valor[, peso extra])) con el peso weight(i)."""
    act, slot = src
    f0, f1 = act.frame_range
    start = f0 if src_start is None else src_start
    sc = bpy.context.scene
    poses = []
    _set_action(arm, act, slot)
    for i in range(n):
        fs = start + i * src_speed
        fs = f0 + (fs - f0) % (f1 - f0)
        sc.frame_set(int(fs), subframe=fs - int(fs))
        w = weight(i)
        for ov in overrides:
            ww = w * (ov[3](i) if len(ov) > 3 else 1.0)
            _apply_override(arm, ov, ww, i)
        poses.append({pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in arm.pose.bones})
    _set_action(arm, None)
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for i, pose in enumerate(poses):
        for pb in arm.pose.bones:
            q, l = pose[pb.name]
            pb.rotation_quaternion = q
            pb.location = l
            pb.keyframe_insert("rotation_quaternion", frame=i + 1, group=pb.name)
            pb.keyframe_insert("location", frame=i + 1, group=pb.name)
    new = arm.animation_data.action
    new.name = name
    _set_action(arm, None)
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, 1, new)
    tr.mute = True
    new.use_fake_user = True
    print("clip", name, n)
    return new


def _ease(a, b):
    """Peso que sube suave de 0 (fotograma a) a 1 (fotograma b)."""
    def f(i):
        t = min(1.0, max(0.0, (i - a) / max(1, b - a)))
        return t * t * (3 - 2 * t)
    return f


def _bump(a, b, c, d):
    """Sube de a a b, se queda y baja de c a d."""
    up, down = _ease(a, b), _ease(c, d)
    return lambda i: up(i) * (1.0 - down(i))


def _wave(amp, period, phase=0.0):
    return lambda i: amp * math.sin(TAU * i / period + phase)


def _with(d, extra):
    """Dirección d + oscilación extra(i) en z (para gestos que tiemblan o acompañan la voz)."""
    return lambda i: (d[0], d[1], d[2] + extra(i))


def _fingers(side, deg):
    out = []
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for k in (1, 2, 3):
            out.append((side + "Hand" + f + str(k), "curl", deg))
    out.append((side + "HandThumb2", "curl", deg * 0.4))
    return out


def king_clips(arm, src):
    up_head = ("Head", "aim", (0, -0.12, 1))
    proud = [("Spine2", "lean", -4.0), ("Neck", "aim", (0, -0.1, 1)), up_head]
    L = int(src[0].frame_range[1] - src[0].frame_range[0])
    bake_clip(arm, src, "rey_idle", L, proud + _fingers("Left", 25) + _fingers("Right", 25))
    bake_clip(arm, src, "rey_invocar", 90, proud + [
        ("LeftArm", "aim", _with((0.75, -0.25, 0.55), _wave(0.06, 45))),
        ("LeftForeArm", "aim", _with((0.55, -0.35, 0.75), _wave(0.08, 45, 0.5))),
        ("RightArm", "aim", _with((-0.75, -0.25, 0.55), _wave(0.06, 45, 0.3))),
        ("RightForeArm", "aim", _with((-0.55, -0.35, 0.75), _wave(0.08, 45, 0.8))),
        ("Head", "aim", (0, -0.35, 0.95)),
    ] + _fingers("Left", -10) + _fingers("Right", -10))
    bake_clip(arm, src, "rey_hablar", 80, proud + [
        ("RightArm", "aim", _with((-0.45, -0.8, -0.2), _wave(0.07, 40))),
        ("RightForeArm", "aim", _with((-0.25, -0.95, 0.1), _wave(0.12, 40, 0.6))),
        ("LeftArm", "aim", (0.3, -0.25, -0.9)),
        ("LeftForeArm", "aim", (-0.75, -0.6, 0.15)),
        ("Head", "turn", _wave(5.0, 80)),
    ] + _fingers("Left", 40))
    bake_clip(arm, src, "rey_sorpresa", 50, [
        ("Spine", "lean", -9.0), ("Spine2", "lean", -8.0), ("Head", "lean", -12.0),
        ("LeftArm", "aim", (0.55, -0.65, -0.3)),
        ("LeftForeArm", "aim", _with((0.05, -0.45, 0.9), _wave(0.05, 7))),
        ("RightArm", "aim", (-0.55, -0.65, -0.3)),
        ("RightForeArm", "aim", _with((-0.05, -0.45, 0.9), _wave(0.05, 7, 1.0))),
    ] + _fingers("Left", -15) + _fingers("Right", -15), weight=_ease(0, 6))


def mage_clips(arm, src):
    grip = _fingers("Right", 75)
    L = int(src[0].frame_range[1] - src[0].frame_range[0])
    bake_clip(arm, src, "mago_idle", L, [("Spine1", "lean", 5.0), ("Head", "aim", (0, -0.25, 1))] + grip +
              [("RightForeArm", "aim", (-0.15, -0.55, -0.82))])
    bake_clip(arm, src, "mago_conjurar", 90, [
        ("Spine1", "lean", 8.0),
        ("RightArm", "aim", (-0.45, -0.55, 0.35)),
        ("RightForeArm", "aim", _with((-0.15, -0.75, 0.62), _wave(0.05, 9))),
        ("RightHand", "aim", (0.0, -0.55, -0.83)),
        ("LeftArm", "aim", (0.35, -0.88, -0.15)),
        ("LeftForeArm", "aim", _with((0.15, -0.95, -0.25), _wave(0.06, 7, 0.4))),
        ("LeftHand", "aim", (0.1, -0.6, 0.6)),
        ("Head", "aim", (0, -0.4, 0.92)),
    ] + grip + _fingers("Left", -20))
    bake_clip(arm, src, "mago_sorpresa", 50, [
        ("Spine", "lean", -12.0), ("Spine2", "lean", -6.0), ("Head", "lean", -10.0),
        ("LeftArm", "aim", (0.45, -0.75, 0.2)),
        ("LeftForeArm", "aim", _with((-0.55, -0.45, 0.7), _wave(0.05, 6))),
        ("RightArm", "aim", (-0.85, 0.15, -0.45)),
        ("RightForeArm", "aim", (-0.4, -0.5, -0.75)),
    ] + grip, weight=_ease(0, 5))
    bake_clip(arm, src, "mago_reverencia", 70, [
        ("Spine", "lean", 28.0), ("Spine1", "lean", 10.0), ("Head", "lean", 10.0),
        ("LeftArm", "aim", (0.25, -0.35, -0.9)), ("LeftForeArm", "aim", (-0.6, -0.75, -0.1)),
        ("RightForeArm", "aim", (-0.15, -0.55, -0.82)),
    ] + grip, weight=_bump(0, 18, 45, 68))


def build_staff(arm, col, src):
    """Bastón en la mano derecha: se modela vertical en la pose de mago_idle y se lleva a la pose de
    reposo con la matriz de deformación de la mano (así en el juego queda recto en la mano)."""
    act = bpy.data.actions["mago_idle"]
    _set_action(arm, act)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    pb = arm.pose.bones[B + "RightHand"]
    mid = arm.pose.bones[B + "RightHandMiddle1"]
    Mw = arm.matrix_world
    palm = Mw @ ((pb.matrix.translation + mid.matrix.translation) / 2)
    D = pb.matrix @ arm.data.bones[B + "RightHand"].matrix_local.inverted()
    to_rest = Mw @ D.inverted() @ Mw.inverted()
    b = _Tracked("Baston_mago")
    bot = Vector((palm.x - 0.02, palm.y - 0.02, 0.03))
    top = Vector((palm.x + 0.02, palm.y + 0.02, 1.78))
    d = top - bot
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    cyl(b, (0, 0, 0), 0.022, d.length, "npc_wood", segs=8, r_top=0.018, smooth=True)
    _move_last(b, Matrix.Translation(bot) @ q.to_matrix().to_4x4())
    # cabeza del bastón: garra de madera con un cristal que brilla
    for k in range(4):
        a = TAU * k / 4
        p0 = top + Vector((0.03 * math.cos(a), 0.03 * math.sin(a), 0.0))
        cyl(b, (0, 0, 0), 0.01, 0.16, "npc_wood", segs=5, r_top=0.004)
        _move_last(b, Matrix.Translation(top) @ Euler((0.35 * math.sin(a), -0.35 * math.cos(a), 0)).to_matrix().to_4x4())
    sphere(b, top + Vector((0, 0, 0.085)), 0.05, "npc_glow_crystal", sub=1, scale=(1, 1, 1.5))
    box(b, (0, 0, 0), (0.06, 0.06, 0.06), "npc_leather")
    _move_last(b, Matrix.Translation(palm + Vector((0, 0, 0.13))))
    bmesh.ops.transform(b.bm, matrix=to_rest, verts=b.bm.verts)
    _set_action(arm, None)
    ws = [{B + "RightHand": 1.0}] * len(b.bm.verts)
    return _make_skinned("Baston_mago", b.bm, b.mats, ws, arm, col)


def export_npc(arm, col, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in col.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False
    _set_action(arm, None)
    bpy.context.scene.frame_set(1)
    _gltf(os.path.join(OUT, name + ".glb"), use_selection=True, export_format="GLB", export_materials="EXPORT",
          export_normals=True, export_texcoords=True, export_apply=False, export_yup=True,
          export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
          export_frame_step=1, export_skins=True, export_def_bones=False, export_vertex_color="NONE")
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    print("exportado", name)


def build_npcs():
    os.makedirs(OUT, exist_ok=True)
    for tag in ("rey", "mago"):
        old = [o for o in bpy.data.objects if o.name.startswith(tag.capitalize() + "Armature")]
        dead = {c.name for o in old for c in o.children} | {o.name for o in old}
        for n in dead:
            if n in bpy.data.objects:
                bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
        for a in list(bpy.data.actions):
            if a.name.startswith(tag + "_") or a.name.startswith("RivaBaseArmature"):
                bpy.data.actions.remove(a)
    scn = bpy.context.scene
    scn.render.fps = FPS
    arm, body, col = _import_riva("rey", 1.80)
    src = _src_action(arm)
    build_king(arm, body, col)
    king_clips(arm, src)
    export_npc(arm, col, "rey")
    arm2, body2, col2 = _import_riva("mago", 1.74)
    src2 = _src_action(arm2)
    build_mage(arm2, body2, col2)
    mage_clips(arm2, src2)
    build_staff(arm2, col2, src2)
    export_npc(arm2, col2, "mago")


if __name__ == "__main__":
    main()
