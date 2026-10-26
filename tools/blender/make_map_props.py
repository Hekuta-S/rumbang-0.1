import bpy, bmesh, math, random
from mathutils import Vector, Matrix, Euler

OUT = r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main\assets\models\mapa"
import os
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- materiales
def mat(name, color, rough=0.85, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        b.inputs["Emission Strength"].default_value = strength
    return m

M = {
    "bark":   mat("bark",   (0.10, 0.075, 0.06), 0.95),
    "bark2":  mat("bark_light", (0.17, 0.14, 0.11), 0.95),
    "wood":   mat("wood",   (0.22, 0.12, 0.06), 0.9),
    "wood_d": mat("wood_dark", (0.10, 0.06, 0.035), 0.95),
    "stone":  mat("stone",  (0.19, 0.19, 0.22), 0.95),
    "stone_d":mat("stone_dark", (0.10, 0.10, 0.13), 0.95),
    "moss":   mat("moss",   (0.07, 0.17, 0.07), 1.0),
    "iron":   mat("iron",   (0.10, 0.10, 0.12), 0.45, 0.8),
    "bone":   mat("bone",   (0.62, 0.57, 0.46), 0.9),
    "fire":   mat("fire",   (1.0, 0.35, 0.05), 0.5, 0.0, (1.0, 0.4, 0.08), 6.0),
    "fire2":  mat("fire_core", (1.0, 0.8, 0.3), 0.5, 0.0, (1.0, 0.75, 0.25), 8.0),
    "rune":   mat("rune",   (0.35, 0.15, 0.7), 0.5, 0.0, (0.55, 0.25, 1.0), 5.0),
    "glow":   mat("glow_teal", (0.1, 0.8, 0.7), 0.5, 0.0, (0.15, 1.0, 0.85), 4.0),
    "cap":    mat("mushroom_cap", (0.28, 0.1, 0.35), 0.8),
    "stem":   mat("mushroom_stem", (0.55, 0.5, 0.45), 0.9),
}

class B:
    def __init__(self, name, mats):
        self.name = name
        self.bm = bmesh.new()
        self.mats = [M[k] for k in mats]
        self.idx = {k: i for i, k in enumerate(mats)}

    def _tag(self, before, mk):
        mi = self.idx[mk]
        for f in set(self.bm.faces) - before:
            f.material_index = mi

    def box(self, c, s, mk, rot=(0, 0, 0)):
        before = set(self.bm.faces)
        m = Matrix.Translation(c) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._tag(before, mk)

    def cyl(self, c, r1, r2, h, seg, mk, rot=(0, 0, 0), caps=True):
        before = set(self.bm.faces)
        m = Matrix.Translation(c) @ Euler(rot).to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg,
                              radius1=r1, radius2=r2, depth=h, matrix=m)
        self._tag(before, mk)

    def limb(self, p0, p1, r0, r1, seg, mk):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        if d.length < 1e-4:
            return
        q = d.normalized().to_track_quat('Z', 'Y')
        before = set(self.bm.faces)
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r0, radius2=r1, depth=d.length, matrix=m)
        self._tag(before, mk)

    def blob(self, c, r, mk, sub=1, rot=(0, 0, 0)):
        before = set(self.bm.faces)
        m = Matrix.Translation(c) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((r[0], r[1], r[2], 1.0))
        bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=1.0, matrix=m)
        self._tag(before, mk)

    def lathe(self, profile, seg, mk, c=(0, 0, 0)):
        before = set(self.bm.faces)
        rows = []
        for (r, z) in profile:
            if r < 1e-5:
                rows.append([self.bm.verts.new((c[0], c[1], c[2] + z))])
            else:
                rows.append([self.bm.verts.new((c[0] + r * math.cos(2 * math.pi * j / seg),
                                                c[1] + r * math.sin(2 * math.pi * j / seg),
                                                c[2] + z)) for j in range(seg)])
        for i in range(len(rows) - 1):
            a, b = rows[i], rows[i + 1]
            for j in range(seg):
                j2 = (j + 1) % seg
                try:
                    if len(a) == 1:
                        self.bm.faces.new((a[0], b[j2], b[j]))
                    elif len(b) == 1:
                        self.bm.faces.new((a[j], a[j2], b[0]))
                    else:
                        self.bm.faces.new((a[j], a[j2], b[j2], b[j]))
                except ValueError:
                    pass
        self._tag(before, mk)

    def transform(self, rot=(0, 0, 0), scale=(1, 1, 1), loc=(0, 0, 0)):
        m = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
        bmesh.ops.transform(self.bm, matrix=m, verts=self.bm.verts)

    def jitter(self, amount, seed=1, zmin=None):
        rnd = random.Random(seed)
        for v in self.bm.verts:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * amount
            if zmin is not None and v.co.z < zmin:
                v.co.z = zmin

    def build(self):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.0005)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ---------------------------------------------------------------- props
def dead_tree(name, seed, height, lean):
    rnd = random.Random(seed)
    b = B(name, ["bark", "bark2"])
    # tronco en segmentos con inclinación acumulada
    pts = [Vector((0, 0, -0.1))]
    r = 0.50
    d = Vector((0, 0, 1))
    segs = 6
    radii = []
    trunk_pts = [pts[0]]
    for i in range(segs):
        d = (d + Vector((rnd.uniform(-lean, lean), rnd.uniform(-lean, lean), 0))).normalized()
        trunk_pts.append(trunk_pts[-1] + d * (height / segs))
    for i in range(segs):
        r0 = 0.5 * (1 - i / segs) + 0.10
        r1 = 0.5 * (1 - (i + 1) / segs) + 0.08
        b.limb(trunk_pts[i], trunk_pts[i + 1], r0, r1, 7, "bark")
    # raíces
    for k in range(5):
        a = k * 2 * math.pi / 5 + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        b.limb(Vector((0, 0, 0.7)) , out * 1.1 + Vector((0, 0, -0.05)), 0.22, 0.06, 5, "bark")
    # ramas recursivas
    def branch(p, dirv, length, rad, depth):
        end = p + dirv * length
        b.limb(p, end, rad, rad * 0.55, 5, "bark2" if depth > 0 else "bark")
        if depth >= 2 or rad < 0.04:
            return
        for _ in range(2 if depth == 0 else 2):
            nd = (dirv + Vector((rnd.uniform(-.7, .7), rnd.uniform(-.7, .7), rnd.uniform(-.1, .5)))).normalized()
            branch(end, nd, length * rnd.uniform(0.55, 0.8), rad * 0.55, depth + 1)
    for i in range(2, segs + 1):
        if rnd.random() < 0.85:
            a = rnd.uniform(0, 2 * math.pi)
            dirv = Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, rnd.uniform(0.25, 0.8))).normalized()
            branch(trunk_pts[i], dirv, rnd.uniform(1.4, 2.3) * (1.1 - i / (segs + 3)), 0.13 * (1.1 - i / (segs + 1)), 0)
    # copa muerta: ramas finales
    top = trunk_pts[-1]
    for k in range(3):
        a = k * 2.1 + rnd.uniform(0, 1)
        branch(top, Vector((math.cos(a) * .6, math.sin(a) * .6, 1)).normalized(), 1.4, 0.07, 1)
    b.jitter(0.02, seed)
    return b.build()

def barrel():
    b = B("barrel", ["wood", "iron", "wood_d"])
    prof = [(0, 0), (0.34, 0), (0.41, 0.12), (0.47, 0.45), (0.41, 0.80), (0.35, 0.92), (0.0, 0.92)]
    b.lathe(prof, 12, "wood")
    def rad(z):
        for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
            if z0 <= z <= z1 and z1 > z0:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return 0.4
    for z in (0.14, 0.46, 0.78):
        b.cyl((0, 0, z), rad(z) + 0.03, rad(z) + 0.03, 0.07, 12, "iron", caps=False)
    b.cyl((0, 0, 0.925), 0.30, 0.30, 0.03, 12, "wood_d")
    b.jitter(0.008, 3)
    return b.build()

def crate():
    b = B("crate", ["wood", "wood_d"])
    b.box((0, 0, 0.45), (0.9, 0.9, 0.9), "wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.43, sy * 0.43, 0.45), (0.1, 0.1, 0.94), "wood_d")
    for z in (0.04, 0.86):
        b.box((0, 0.45, z), (0.92, 0.08, 0.1), "wood_d")
        b.box((0, -0.45, z), (0.92, 0.08, 0.1), "wood_d")
        b.box((0.45, 0, z), (0.08, 0.92, 0.1), "wood_d")
        b.box((-0.45, 0, z), (0.08, 0.92, 0.1), "wood_d")
    b.box((0, -0.455, 0.45), (0.12, 0.05, 1.1), "wood_d", rot=(0, 0.75, 0))
    b.jitter(0.01, 5)
    return b.build()

def gravestone_round():
    b = B("gravestone_round", ["stone", "stone_d", "moss"])
    b.box((0, 0, 0.08), (1.1, 0.55, 0.16), "stone_d")
    b.box((0, 0, 0.55), (0.8, 0.24, 0.8), "stone")
    b.cyl((0, 0, 0.95), 0.4, 0.4, 0.24, 12, "stone", rot=(math.pi / 2, 0, 0))
    b.blob((0.1, 0, 0.16), (0.35, 0.3, 0.07), "moss")
    b.blob((-0.2, 0.1, 1.33), (0.18, 0.14, 0.05), "moss")
    b.box((0, -0.13, 0.62), (0.34, 0.03, 0.05), "stone_d")
    b.box((0, -0.13, 0.5), (0.5, 0.03, 0.04), "stone_d")
    b.jitter(0.012, 7)
    b.transform(rot=(0.05, -0.07, 0))
    return b.build()

def gravestone_cross():
    b = B("gravestone_cross", ["stone", "stone_d", "moss"])
    b.box((0, 0, 0.08), (1.0, 0.7, 0.16), "stone_d")
    b.box((0, 0, 0.75), (0.26, 0.2, 1.3), "stone")
    b.box((0, 0, 1.05), (0.85, 0.2, 0.24), "stone")
    b.blob((0.0, 0, 0.17), (0.4, 0.3, 0.06), "moss")
    b.jitter(0.012, 11)
    b.transform(rot=(-0.06, 0.1, 0))
    return b.build()

def pillar_broken():
    b = B("pillar_broken", ["stone", "stone_d", "moss"])
    b.box((0, 0, 0.12), (1.5, 1.5, 0.24), "stone_d")
    b.cyl((0, 0, 0.35), 0.65, 0.6, 0.22, 8, "stone_d")
    rnd = random.Random(21)
    z = 0.46
    while z < 3.0:
        h = 0.55
        b.cyl((rnd.uniform(-.02, .02), rnd.uniform(-.02, .02), z + h / 2), 0.5, 0.48, h, 8, "stone",
              rot=(0, 0, rnd.uniform(0, 1)))
        z += h
    # remate roto
    b.cyl((0, 0, z + 0.2), 0.48, 0.2, 0.4, 6, "stone", rot=(0.15, -0.1, 0))
    # tambor caído y escombros
    b.cyl((1.6, 0.4, 0.5), 0.5, 0.5, 0.8, 8, "stone", rot=(math.pi / 2, 0, 0.6))
    for i in range(5):
        b.box((rnd.uniform(-1.4, 1.6), rnd.uniform(-1.2, 1.2), 0.1), (rnd.uniform(.2, .4), rnd.uniform(.2, .4), rnd.uniform(.12, .25)),
              "stone_d", rot=(0, 0, rnd.uniform(0, 3)))
    b.blob((0.2, 0.3, 0.5), (0.35, 0.3, 0.12), "moss")
    b.jitter(0.015, 21)
    return b.build()

def wall_ruin():
    b = B("wall_ruin", ["stone", "stone_d", "moss"])
    rnd = random.Random(33)
    cols = 8
    w = 0.5
    for c in range(cols):
        x = (c - (cols - 1) / 2) * w
        hts = rnd.choice([2, 3, 4, 5, 6, 3, 4])
        if c in (3, 4):
            hts = rnd.choice([1, 2])
        for k in range(hts):
            if k > 1 and rnd.random() < 0.12:
                continue
            mk = "stone" if (c + k) % 2 == 0 else "stone_d"
            b.box((x + rnd.uniform(-.02, .02), rnd.uniform(-.03, .03), 0.25 + k * 0.5),
                  (w * 0.97, 0.62, 0.48), mk, rot=(0, 0, rnd.uniform(-0.03, 0.03)))
        if rnd.random() < 0.5:
            b.blob((x, 0, 0.25 + hts * 0.5), (0.22, 0.3, 0.07), "moss")
    for i in range(7):
        b.box((rnd.uniform(-2.2, 2.2), rnd.uniform(-.9, .9), 0.1), (rnd.uniform(.2, .45), rnd.uniform(.2, .4), rnd.uniform(.12, .25)),
              "stone_d", rot=(0, 0, rnd.uniform(0, 3)))
    b.jitter(0.015, 33, zmin=0)
    return b.build()

def rock(name, seed, scale, double):
    b = B(name, ["stone", "stone_d", "moss"])
    rnd = random.Random(seed)
    b.blob((0, 0, 0.5 * scale), (scale * 1.1, scale * 0.9, scale * 0.8), "stone", sub=2)
    if double:
        b.blob((scale * 0.7, scale * 0.3, 0.4 * scale), (scale * 0.7, scale * 0.6, scale * 0.6), "stone_d", sub=2)
    for v in b.bm.verts:
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * scale * 0.12
        if v.co.z < 0.0:
            v.co.z = 0.0
    b.blob((0, 0, 1.15 * scale), (scale * 0.55, scale * 0.45, scale * 0.12), "moss", sub=1)
    return b.build()

def brazier():
    b = B("brazier", ["iron", "fire", "fire2"])
    for k in range(3):
        a = k * 2 * math.pi / 3
        b.limb((0, 0, 0.95), (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.0), 0.05, 0.04, 5, "iron")
    b.limb((0, 0, 0.05), (0, 0, 0.95), 0.05, 0.05, 6, "iron")
    b.lathe([(0, 0.88), (0.2, 0.88), (0.36, 1.08), (0.44, 1.22), (0.39, 1.22), (0.31, 1.1), (0, 1.02)], 10, "iron")
    b.cyl((0, 0, 1.45), 0.34, 0.03, 0.55, 7, "fire")
    b.cyl((0.1, 0.05, 1.4), 0.2, 0.02, 0.5, 6, "fire", rot=(0.1, 0.2, 0))
    b.cyl((0, 0, 1.3), 0.16, 0.02, 0.35, 6, "fire2")
    b.jitter(0.01, 9)
    return b.build()

def bone_pile():
    b = B("bone_pile", ["bone", "stone_d"])
    rnd = random.Random(44)
    b.blob((0, 0, 0.17), (0.17, 0.2, 0.16), "bone", sub=1)
    b.box((0, -0.14, 0.06), (0.16, 0.12, 0.07), "bone")
    for i in range(10):
        a = rnd.uniform(0, 2 * math.pi)
        p = Vector((rnd.uniform(-.5, .5), rnd.uniform(-.5, .5), 0.05))
        d = Vector((math.cos(a), math.sin(a), rnd.uniform(-.05, .25)))
        b.limb(p, p + d * rnd.uniform(.3, .55), 0.035, 0.035, 5, "bone")
        b.blob(p, (0.05, 0.05, 0.05), "bone", sub=1)
    for i in range(4):
        b.blob((rnd.uniform(-.6, .6), rnd.uniform(-.6, .6), 0.05), (.12, .1, .06), "stone_d")
    b.jitter(0.006, 4, zmin=0)
    return b.build()

def altar():
    b = B("altar", ["stone", "stone_d", "rune"])
    b.box((0, 0, 0.14), (3.4, 3.4, 0.28), "stone_d")
    b.box((0, 0, 0.4), (2.6, 2.6, 0.26), "stone")
    b.box((0, 0, 1.0), (1.5, 0.9, 0.95), "stone_d")
    b.box((0, 0, 1.55), (1.8, 1.1, 0.2), "stone")
    # runas
    b.box((0, -0.455, 1.0), (0.1, 0.02, 0.6), "rune")
    b.box((-0.3, -0.455, 1.0), (0.08, 0.02, 0.4), "rune")
    b.box((0.3, -0.455, 1.0), (0.08, 0.02, 0.4), "rune")
    b.box((0, -0.455, 1.0), (0.4, 0.02, 0.08), "rune", rot=(0, 0.78, 0))
    b.box((0, 0, 1.67), (1.2, 0.5, 0.04), "rune")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 1.15, sy * 1.15, 0.9), (0.28, 0.28, 1.2), "stone")
            b.cyl((sx * 1.15, sy * 1.15, 1.75), 0.2, 0.01, 0.6, 4, "stone_d")
    b.jitter(0.01, 12)
    return b.build()

def fence():
    b = B("fence", ["iron"])
    for i in range(4):
        x = (i - 1.5) * 0.8
        b.box((x, 0, 0.7), (0.1, 0.1, 1.4), "iron", rot=(0, 0, 0))
        b.cyl((x, 0, 1.52), 0.07, 0.0, 0.25, 4, "iron")
    b.box((0, 0, 0.45), (2.5, 0.05, 0.07), "iron")
    b.box((0, 0, 1.05), (2.5, 0.05, 0.07), "iron")
    for i in range(7):
        x = (i - 3) * 0.37 + 0.0
        b.box((x, 0, 0.7), (0.035, 0.035, 1.1), "iron")
        b.cyl((x, 0, 1.3), 0.03, 0.0, 0.18, 4, "iron")
    b.jitter(0.006, 6)
    return b.build()

def mushroom():
    b = B("mushroom", ["stem", "cap", "glow"])
    b.lathe([(0, 0), (0.18, 0), (0.12, 0.35), (0.1, 0.7), (0.08, 0.9)], 7, "stem")
    b.lathe([(0.08, 0.85), (0.55, 0.78), (0.8, 0.95), (0.7, 1.25), (0.35, 1.45), (0, 1.5)], 9, "cap")
    b.lathe([(0.1, 0.84), (0.5, 0.76), (0.52, 0.78), (0.12, 0.86)], 9, "glow")
    for a in range(5):
        ang = a * 1.3
        b.blob((math.cos(ang) * 0.38, math.sin(ang) * 0.38, 1.2 + 0.05 * a), (0.09, 0.09, 0.05), "glow")
    b.jitter(0.01, 8)
    return b.build()


# ---------------------------------------------------------------- generar y exportar
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)

props = [
    dead_tree("tree_dead_a", 1, 6.5, 0.18),
    dead_tree("tree_dead_b", 7, 5.0, 0.35),
    barrel(), crate(), gravestone_round(), gravestone_cross(),
    pillar_broken(), wall_ruin(),
    rock("rock_a", 3, 1.3, False), rock("rock_b", 5, 2.0, True),
    brazier(), bone_pile(), altar(), fence(), mushroom(),
]

for ob in props:
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, ob.name.split(".")[0] + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True,
                              export_cameras=False, export_lights=False)

# exposición para ver
x = 0
for ob in props:
    ob.location = (x, 0, 0)
    x += 6
print("OK", [ (o.name, len(o.data.polygons)) for o in props ])
