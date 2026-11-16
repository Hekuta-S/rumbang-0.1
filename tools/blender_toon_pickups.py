"""Recogibles de supervivencia (bomba, imán, comida, reloj) y el DADO DEL DESTINO, en estilo cartoon con la
tinta HORNEADA en la textura (mismo horneado que los props: tools/blender_toon_props.py).

    blender -b --python tools/blender_toon_pickups.py [-- pickup_bomb,pickup_dice]

Sale assets/models/pickups/<nombre>.glb (con UV) y assets/textures/toon/props/<nombre>.png; en el juego los
carga MapPickup / FateDice con ProceduralMap.toon_prop_material(<nombre>). Las partes emisivas (chispa de la
mecha, esfera del reloj) se marcan con un material emisivo: brillan con el shader prop_toon.

Caras del dado (Blender, Z arriba) → Godot (Y arriba), ver FateDice.FACE_UP:
    +Z 1 · -Z 6 · +X 2 · -X 5 · +Y 3 · -Y 4   →   +Y 1 · -Y 6 · +X 2 · -X 5 · -Z 3 · +Z 4
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_toon_props as tp          # noqa: E402  (constructores B/M, bake_material y process)

tp.OUT_GLB = os.path.join(tp.ROOT, "assets", "models", "pickups")
os.makedirs(tp.OUT_GLB, exist_ok=True)

M = tp.M
M.update({
    "bomb": tp.mat("pk_bomb_body", (0.035, 0.035, 0.05), 0.6),
    "bomb_cap": tp.mat("pk_bomb_cap_iron", (0.16, 0.16, 0.2), 0.5),
    "fuse": tp.mat("pk_fuse_rope", (0.55, 0.42, 0.22), 0.9),
    "spark": tp.mat("pk_spark", (1.0, 0.75, 0.2), 0.5, 0.0, (1.0, 0.65, 0.15), 6.0),
    "red": tp.mat("pk_magnet_red", (0.75, 0.05, 0.05), 0.6),
    "tip": tp.mat("pk_magnet_tip", (0.72, 0.74, 0.8), 0.4),
    "meat": tp.mat("pk_meat", (0.42, 0.14, 0.06), 0.8),
    "meat_l": tp.mat("pk_meat_light", (0.62, 0.28, 0.12), 0.8),
    "bonef": tp.mat("pk_bone", (0.85, 0.8, 0.66), 0.8),
    "gold": tp.mat("pk_gold", (0.85, 0.6, 0.12), 0.4),
    "face": tp.mat("pk_clock_face", (0.75, 0.9, 1.0), 0.5, 0.0, (0.55, 0.8, 1.0), 2.0),
    "hand": tp.mat("pk_clock_hand", (0.03, 0.03, 0.05), 0.6),
    "die": tp.mat("pk_dice_ivory", (0.9, 0.86, 0.76), 0.5),
    "pip": tp.mat("pk_dice_pip", (0.55, 0.04, 0.08), 0.5),
})


def bomb():
    b = tp.B("pickup_bomb", ["bomb", "bomb_cap", "fuse", "spark"])
    bm = b.bm
    before = set(bm.faces)
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.3,
                              matrix=Matrix.Translation((0, 0, 0.32)))
    b._tag(before, "bomb")
    b.cyl((0, 0, 0.63), 0.1, 0.11, 0.1, 10, "bomb_cap")
    b.limb((0, 0, 0.67), (0.05, 0.03, 0.78), 0.025, 0.022, 6, "fuse")
    b.limb((0.05, 0.03, 0.78), (0.13, 0.02, 0.85), 0.022, 0.02, 6, "fuse")
    b.blob((0.15, 0.02, 0.88), (0.06, 0.06, 0.06), "spark", sub=1)
    for k in range(5):                                   # rayos de la chispa
        a = k * math.tau / 5
        d = Vector((math.cos(a), 0.3 * math.sin(a * 2), math.sin(a))).normalized()
        p0 = Vector((0.15, 0.02, 0.88))
        b.limb(p0 + d * 0.04, p0 + d * 0.12, 0.012, 0.0, 4, "spark")
    return b.build()


def sweep(b, path, radius, seg, mat_of):
    """Tubo continuo (sin tapas intermedias) a lo largo de `path`; mat_of(i) da el material de cada tramo."""
    bm = b.bm
    rings = []
    for i, p in enumerate(path):
        p = Vector(p)
        t = (Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
        side = t.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(t).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radius)
                      for a in (k * math.tau / seg for k in range(seg))])
    for i in range(len(rings) - 1):
        a, c = rings[i], rings[i + 1]
        for k in range(seg):
            f = bm.faces.new((a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]))
            f.material_index = b.idx[mat_of(i)]
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(list(reversed(ring)) if rev else ring)
        f.material_index = b.idx[mat_of(0 if rev else len(rings) - 2)]


def magnet():
    """Imán de herradura: un solo tubo rojo en U con las puntas plateadas, ancho para que se lea de frente."""
    b = tp.B("pickup_magnet", ["red", "tip"])
    r, t = 0.24, 0.085
    path = [(-r, 0, 0.06 + 0.04 * k) for k in range(0, 10)]                 # pata izquierda (sube)
    path += [(-math.cos(math.pi * k / 14) * r, 0, 0.42 + math.sin(math.pi * k / 14) * r) for k in range(1, 14)]
    path += [(r, 0, 0.42 - 0.04 * k) for k in range(0, 10)]                  # pata derecha (baja)
    n = len(path)
    sweep(b, path, t, 14, lambda i: "tip" if (path[i][2] < 0.2 and path[i + 1][2] < 0.2) else "red")
    for sx in (-1, 1):                                    # rayitas de "imán" sobre las puntas
        b.box((sx * r, -t * 0.9, 0.21), (t * 1.6, 0.01, 0.018), "tip")
    return b.build()


def food():
    """Muslo de pollo asado: carne en forma de gota y un hueso largo con sus dos nudos."""
    b = tp.B("pickup_food", ["meat", "meat_l", "bonef"])
    b.blob((-0.06, 0, 0.36), (0.24, 0.2, 0.2), "meat", sub=4)            # esfera fina: la tinta no marca vértices
    b.blob((-0.12, -0.1, 0.44), (0.1, 0.06, 0.06), "meat_l", sub=3)
    b.limb((0.12, 0, 0.36), (0.42, 0, 0.42), 0.05, 0.045, 10, "bonef")
    for dy in (-0.05, 0.05):
        b.blob((0.45, dy, 0.43), (0.065, 0.065, 0.065), "bonef", sub=3)
    return b.build()


def clock():
    b = tp.B("pickup_clock", ["gold", "face", "hand"])
    rot = (math.pi / 2, 0, 0)                              # de pie, mirando a -Y (frente)
    b.cyl((0, 0, 0.38), 0.28, 0.28, 0.12, 20, "gold", rot=rot)
    b.cyl((0, -0.062, 0.38), 0.23, 0.23, 0.02, 20, "face", rot=rot)
    b.cyl((0, 0.0, 0.7), 0.045, 0.045, 0.08, 8, "gold")      # botón
    b.cyl((0, 0.0, 0.76), 0.07, 0.07, 0.03, 10, "gold")
    b.box((0, -0.08, 0.45), (0.025, 0.012, 0.15), "hand")      # agujas
    b.box((0.05, -0.08, 0.38), (0.11, 0.012, 0.022), "hand")
    for k in range(12):                                     # marcas de las horas
        a = k * math.tau / 12
        b.box((math.cos(a) * 0.19, -0.075, 0.38 + math.sin(a) * 0.19), (0.02, 0.01, 0.02), "hand")
    return b.build()


# Pips de cada cara en coordenadas de la cara (u, v) en [-1, 1]
PIPS = {
    1: [(0, 0)],
    2: [(-1, -1), (1, 1)],
    3: [(-1, -1), (0, 0), (1, 1)],
    4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
    5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
    6: [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)],
}
# valor -> (normal, eje u, eje v) en Blender
FACES = {
    1: ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    6: ((0, 0, -1), (1, 0, 0), (0, -1, 0)),
    2: ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
    5: ((-1, 0, 0), (0, -1, 0), (0, 0, 1)),
    3: ((0, 1, 0), (-1, 0, 0), (0, 0, 1)),
    4: ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
}


def dice():
    s = 0.5                                                # lado
    b = tp.B("pickup_dice", ["die", "pip"])
    bm = b.bm
    before = set(bm.faces)
    bmesh.ops.create_cube(bm, size=s)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=s * 0.12, segments=3, affect='EDGES', profile=0.5)
    b._tag(before, "die")
    c = Vector((0, 0, 0))
    for val, (n, u, v) in FACES.items():
        n, u, v = Vector(n), Vector(u), Vector(v)
        for pu, pv in PIPS[val]:
            p = c + n * (s * 0.5 + 0.004) + (u * pu + v * pv) * s * 0.24
            before = set(bm.faces)
            q = n.to_track_quat('Z', 'Y')
            m = Matrix.Translation(p) @ q.to_matrix().to_4x4()
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=s * 0.07,
                                  radius2=s * 0.06, depth=0.006, matrix=m)
            b._tag(before, "pip")
    ob = b.build()
    ob.location = (0, 0, 0)
    return ob


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[0].split(",") if argv else None
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = tp.SAMPLES
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0, 0, -0.3))
    ground = bpy.context.active_object
    builders = {"pickup_bomb": (bomb, True), "pickup_magnet": (magnet, True), "pickup_food": (food, True),
                "pickup_clock": (clock, False), "pickup_dice": (dice, False)}
    for name, (fn, smooth) in builders.items():
        if only and name not in only:
            continue
        ob = fn()
        tp.process(ob, smooth, ground)
        bpy.data.objects.remove(ob, do_unlink=True)


main()
