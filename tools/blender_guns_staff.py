# Modelos de la Pistola, el Fusil y el Bastón de Fuego (mazmorra).
# Ejecutar sin interfaz:  blender.exe -b --factory-startup --python tools/blender_guns_staff.py
# Exporta a assets/models/weapons/pistola.glb, fusil.glb y baston_fuego.glb.
#
# Ejes (Blender, Z arriba): las armas de fuego apuntan a +Y (en Godot, -Z) con la empuñadura en el origen, como
# escopeta_humo.glb (WeaponAnimSets.SETS / HeldWeaponRig). El bastón va a lo largo de +Z (en Godot, +Y) con el
# agarre en el origen y la gema arriba, como la espalanza (PlayerWeaponVisuals.attach_staff).
import bpy, bmesh, math, os
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models", "weapons")


def mat(name, col, metal=0.0, rough=0.5, emit=None, strength=3.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


class Part:
    """Malla hecha de piezas; cada pieza lleva su material."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []
        self.face_mat = []

    def _tag(self, faces, m):
        if m not in self.mats:
            self.mats.append(m)
        idx = self.mats.index(m)
        for f in faces:
            f.material_index = idx

    def box(self, size, center, m, rot=(0, 0, 0)):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        xf = (Matrix.Translation(center) @ Matrix.Rotation(math.radians(rot[0]), 4, "X")
              @ Matrix.Rotation(math.radians(rot[1]), 4, "Y") @ Matrix.Rotation(math.radians(rot[2]), 4, "Z")
              @ Matrix.Diagonal((*size, 1)))
        bmesh.ops.transform(self.bm, matrix=xf, verts=r["verts"])
        self._tag({f for v in r["verts"] for f in v.link_faces}, m)

    def cyl(self, r1, r2, a, b, m, segs=10):
        """Cilindro (cono) de `a` a `b`."""
        a, b = Vector(a), Vector(b)
        d = b - a
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=d.length)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        xf = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=xf, verts=r["verts"])
        self._tag({f for v in r["verts"] for f in v.link_faces}, m)

    def ico(self, radius, center, m, subdiv=1, scale=(1, 1, 1)):
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius)
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*scale, 1)), verts=r["verts"])
        self._tag({f for v in r["verts"] for f in v.link_faces}, m)

    def finish(self, name, coll):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        o = bpy.data.objects.new(name, me)
        coll.objects.link(o)
        return o


def export(obj, filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, filename), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True)
    print("EXPORTADO", filename)


def build():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    coll = bpy.context.scene.collection
    black = mat("gn_black", (0.05, 0.05, 0.055), 0.6, 0.45)
    steel = mat("gn_steel", (0.42, 0.44, 0.48), 1.0, 0.3)
    grip = mat("gn_grip", (0.12, 0.08, 0.06), 0.0, 0.85)
    wood = mat("gn_wood", (0.36, 0.2, 0.1), 0.0, 0.7)
    brass = mat("gn_brass", (0.8, 0.55, 0.2), 1.0, 0.35)
    fire = mat("st_fire_gem", (1.0, 0.45, 0.08), 0.0, 0.3, emit=(1.0, 0.42, 0.06), strength=4.0)
    staff_wood = mat("st_wood", (0.24, 0.13, 0.07), 0.0, 0.8)

    # ── Pistola (~0,21 m): corredera, armazón, empuñadura inclinada y guardamonte ──
    p = Part()
    p.box((0.030, 0.205, 0.036), (0, 0.062, 0.052), black)          # corredera
    p.box((0.031, 0.06, 0.004), (0, 0.02, 0.072), steel)            # estrías de la corredera
    p.box((0.028, 0.165, 0.022), (0, 0.072, 0.025), black)          # armazón
    p.cyl(0.0075, 0.0075, (0, 0.16, 0.055), (0, 0.172, 0.055), steel, 10)   # boca del cañón
    p.box((0.028, 0.045, 0.105), (0, -0.012, -0.03), grip, rot=(-14, 0, 0))   # empuñadura
    p.box((0.030, 0.012, 0.008), (0, -0.025, -0.083), black, rot=(-14, 0, 0))  # base del cargador
    p.box((0.006, 0.05, 0.005), (0, 0.045, -0.002), black)          # guardamonte (abajo)
    p.box((0.006, 0.005, 0.026), (0, 0.068, 0.012), black)          # guardamonte (delante)
    p.box((0.004, 0.008, 0.016), (0, 0.035, 0.006), steel)          # gatillo
    p.box((0.006, 0.006, 0.008), (0, 0.155, 0.074), steel)          # mira delantera
    p.box((0.018, 0.006, 0.008), (0, -0.03, 0.074), steel)          # mira trasera
    export(p.finish("Pistola", coll), "pistola.glb")

    # ── Fusil (~0,98 m): culata, cajón, cargador curvo, guardamanos y cañón largo ──
    r = Part()
    r.box((0.040, 0.24, 0.075), (0, -0.20, 0.025), wood, rot=(4, 0, 0))     # culata
    r.box((0.044, 0.025, 0.11), (0, -0.325, 0.015), black)                  # cantonera
    r.box((0.048, 0.30, 0.075), (0, 0.075, 0.05), black)                    # cajón de mecanismos
    r.box((0.034, 0.042, 0.10), (0, -0.005, -0.03), grip, rot=(-16, 0, 0))  # empuñadura
    r.box((0.006, 0.06, 0.005), (0, 0.045, 0.0), black)                     # guardamonte
    r.box((0.004, 0.008, 0.018), (0, 0.04, 0.012), steel)                   # gatillo
    for i in range(3):                                                      # cargador curvo (3 tramos)
        r.box((0.03, 0.055, 0.055), (0, 0.13 + 0.018 * i, -0.005 - 0.045 * i), black, rot=(18 + 8 * i, 0, 0))
    r.box((0.056, 0.27, 0.058), (0, 0.345, 0.048), wood)                    # guardamanos
    r.box((0.012, 0.25, 0.006), (0, 0.345, 0.08), steel)                    # riel superior
    r.cyl(0.011, 0.011, (0, 0.47, 0.06), (0, 0.64, 0.06), steel, 10)       # cañón
    r.cyl(0.016, 0.016, (0, 0.62, 0.06), (0, 0.665, 0.06), black, 10)      # bocacha
    r.box((0.006, 0.008, 0.03), (0, 0.6, 0.085), steel)                     # mira delantera
    r.box((0.024, 0.03, 0.022), (0, -0.04, 0.095), steel)                   # mira trasera
    r.cyl(0.006, 0.006, (0.026, 0.02, 0.06), (0.026, 0.06, 0.06), brass, 6)   # palanca de carga
    export(r.finish("Fusil", coll), "fusil.glb")

    # ── Bastón de Fuego (~1,65 m): asta retorcida, anillas de latón, garras y gema ardiente ──
    s = Part()
    s.cyl(0.024, 0.02, (0, 0, -0.62), (0, 0, 0.9), staff_wood, 8)          # asta
    s.cyl(0.028, 0.02, (0, 0, -0.66), (0, 0, -0.6), brass, 8)              # contera
    for z in (-0.12, 0.12, 0.86):                                           # anillas
        s.cyl(0.03, 0.03, (0, 0, z - 0.015), (0, 0, z + 0.015), brass, 8)
    for i in range(3):                                                      # garras que abrazan la gema
        a = math.radians(120 * i)
        base = Vector((math.cos(a) * 0.022, math.sin(a) * 0.022, 0.88))
        mid = Vector((math.cos(a) * 0.075, math.sin(a) * 0.075, 0.99))
        top = Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 1.1))
        s.cyl(0.012, 0.009, base, mid, staff_wood, 6)
        s.cyl(0.009, 0.004, mid, top, staff_wood, 6)
    s.ico(0.058, (0, 0, 1.0), fire, 1, scale=(1, 1, 1.25))                  # gema
    export(s.finish("BastonFuego", coll), "baston_fuego.glb")


build()
