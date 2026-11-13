# Modelos de las Dagas Gemelas y la Maza Rúnica (escena "Armas_Melee" de rumbang_anims.blend).
# Ejecutar dentro de Blender (Text Editor o MCP): crea Daga y Maza con la hoja/mango a lo largo de +Z y
# el agarre en el origen, y las exporta a assets/models/weapons/daga.glb y maza.glb (+Y arriba en Godot).
# El juego las cuelga de la mano con el mismo agarre que la espalanza (PlayerWeaponVisuals.GRIP_*).
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "assets", "models", "weapons")


def mat(name, col, metal=0.0, rough=0.5, emit=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 3.0
    return m


def cyl(bm, r1, r2, depth, z0, segs):
    r = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.translate(bm, vec=(0, 0, z0 + depth / 2), verts=r["verts"])


def finish(name, bm, mats, rule, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.material_index = rule(p.center)
        p.use_smooth = False
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    return o


def build():
    sc = bpy.data.scenes.get("Armas_Melee") or bpy.data.scenes.new("Armas_Melee")
    for o in list(sc.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    steel = mat("am_steel", (0.72, 0.75, 0.8), 1.0, 0.25)
    dark = mat("am_dark_iron", (0.08, 0.08, 0.09), 0.9, 0.45)
    leather = mat("am_leather", (0.18, 0.09, 0.05), 0.0, 0.8)
    gold = mat("am_gold", (0.85, 0.6, 0.2), 1.0, 0.3)
    rune = mat("am_rune", (0.2, 1.0, 0.45), 0.0, 0.4, emit=(0.25, 1.0, 0.5))

    # ── Daga (~0,45 m): pomo, mango de cuero, guarda dorada y hoja en losange ──
    bm = bmesh.new()
    cyl(bm, 0.016, 0.014, 0.11, -0.06, 8)
    cyl(bm, 0.022, 0.022, 0.02, -0.08, 8)
    g = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((0, 0, 0.06)) @ Matrix.Diagonal((0.11, 0.022, 0.018, 1)), verts=g["verts"])
    outline = [(0, 0.07), (0.022, 0.09), (0.016, 0.30), (0, 0.37), (-0.016, 0.30), (-0.022, 0.09)]
    front = [bm.verts.new((x, 0.006, z)) for x, z in outline]
    back = [bm.verts.new((x, -0.006, z)) for x, z in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new([front[i], front[j], back[j], back[i]])
    daga = finish("Daga", bm, [steel, gold, leather],
        lambda c: 0 if c.z > 0.068 else (1 if (c.z > 0.048 or c.z < -0.058) else 2), sc.collection)

    # ── Maza de dos manos (~1,6 m): el origen es la mano derecha (la de arriba); la izquierda agarra
    # MACE_LEFT_GRIP más abajo. Mango de hierro con dos empuñaduras de cuero, cabeza enorme con seis aletas
    # en cuña, pinchos y runas verdes ──
    bm = bmesh.new()
    cyl(bm, 0.032, 0.028, 1.12, -0.5, 10)            # mango (-0,50 .. 0,62)
    cyl(bm, 0.05, 0.05, 0.06, -0.56, 10)             # pomo
    cyl(bm, 0.036, 0.036, 0.16, -0.08, 10)           # empuñadura derecha
    cyl(bm, 0.036, 0.036, 0.16, -0.42, 10)           # empuñadura izquierda
    cyl(bm, 0.045, 0.06, 0.1, 0.56, 10)              # cuello
    s = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.16)
    bmesh.ops.translate(bm, vec=(0, 0, 0.84), verts=s["verts"])
    for k in range(6):
        a = k * math.pi / 3
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.026
        inner, outer = d * 0.1, d * 0.27
        z0, z1, zo0, zo1 = 0.64, 1.04, 0.74, 0.94      # la arista exterior es más corta: cuña
        vs = [bm.verts.new(p) for p in (
            inner + side + Vector((0, 0, z0)), inner - side + Vector((0, 0, z0)),
            inner - side + Vector((0, 0, z1)), inner + side + Vector((0, 0, z1)),
            outer + Vector((0, 0, zo0)), outer + Vector((0, 0, zo1)))]
        for f in ((0, 1, 2, 3), (0, 4, 1), (1, 4, 5, 2), (2, 5, 3), (3, 5, 4, 0)):
            bm.faces.new([vs[i] for i in f])
        # Pincho entre aleta y aleta
        b = Vector((math.cos(a + math.pi / 6), math.sin(a + math.pi / 6), 0))
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.035, radius2=0.0, depth=0.14)
        rot = b.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation(b * 0.2 + Vector((0, 0, 0.84))) @ rot, verts=r["verts"])
    cyl(bm, 0.06, 0.0, 0.18, 0.98, 8)                # pincho superior (runa)
    cyl(bm, 0.17, 0.17, 0.03, 0.62, 16)              # anillos de runas
    cyl(bm, 0.15, 0.15, 0.03, 1.02, 16)

    def mace_rule(c):
        r = math.hypot(c.x, c.y)
        if c.z > 1.07 or (0.6 < c.z < 0.655 and r > 0.13) or (1.0 < c.z < 1.055 and r > 0.11):
            return 1
        if r > 0.03 and (-0.085 < c.z < 0.085 or -0.425 < c.z < -0.255):
            return 2
        return 0
    maza = finish("Maza", bm, [dark, rune, leather], mace_rule, sc.collection)
    maza.location.x = 0.5
    return sc, daga, maza


def export(sc, objs):
    bpy.context.window.scene = sc
    for name, fn in objs:
        o = bpy.data.objects[name]
        old = o.location.copy()
        o.location = (0, 0, 0)
        for x in sc.objects:
            x.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        # Sin animaciones: si no, el exportador recorre todas las acciones del archivo y se cuelga
        # use_active_scene: si no, también se cuelan los objetos seleccionados de las demás escenas
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, fn), use_selection=True, use_active_scene=True,
            export_format="GLB",
            export_apply=True, export_animations=False, export_skins=False, export_morph=False)
        o.location = old


if __name__ == "__main__" or True:
    sc, daga, maza = build()
    print(daga.dimensions, maza.dimensions)
