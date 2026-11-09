"""Hongos de las Cavernas a partir de hongo_fab.glb (CC-BY 4.0, Diego Duarte).

Uso: blender -b --python tools/blender_cave_mushrooms.py -- <hongo_fab.glb> [salida_dir] [atlas_dir]
  (o dentro de Blender con exec + run(...))

Separa el modelo en tres piezas y quita la base de césped ("Ground") y la "Puerta":
  mushroom_big.glb   hongo grande (Hongo_Big), 1.6 m de alto
  mushroom_small.glb hongo bajo (Hongo_Low), a la misma escala
  mushroom_cups.glb  las tres copas pequeñas (Speaker_1..3) juntas, a la misma escala
Origen = centro de la base (z = 0), sin materiales (DungeonMap les pone el shader mushroom_glow con
las texturas de assets/textures/mushrooms, ver tools/make_mushroom_textures.py). Con atlas_dir guarda
además las texturas originales del modelo (base color y normal) para ese script.
"""
import sys, os
import bpy
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else ""
BIG_H = 1.6
PARTS = {"mushroom_big": ["Hongo_Big"], "mushroom_small": ["Hongo_Low"], "mushroom_cups": ["Speaker_1", "Speaker_2", "Speaker_3"]}


def run(src, out_dir, atlas_dir=""):
    scene = bpy.data.scenes.get("MushBuild")
    if scene:
        for o in list(scene.objects):
            bpy.data.objects.remove(o)
    else:
        scene = bpy.data.scenes.new("MushBuild")
    bpy.context.window.scene = scene
    bpy.ops.import_scene.gltf(filepath=src)
    if atlas_dir:
        mat = next(o for o in scene.objects if o.type == "MESH").data.materials[0]
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.outputs[0].links:
                to = n.outputs[0].links[0].to_node.type
                name = {"BSDF_PRINCIPLED": "hongo_basecolor.png", "NORMAL_MAP": "hongo_normal.png"}.get(to)
                if name:
                    im = n.image.copy()
                    im.filepath_raw = os.path.join(atlas_dir, name)
                    im.file_format = "PNG"
                    im.save()
    meshes = {o.name.split("_Hongo")[0]: o for o in scene.objects if o.type == "MESH"}
    # todo a coordenadas del mundo
    for o in meshes.values():
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    big = meshes["Hongo_Big"]
    zs = [v.co.z for v in big.data.vertices]
    s = BIG_H / (max(zs) - min(zs))
    for name, parts in PARTS.items():
        obs = [meshes[p] for p in parts]
        pts = [v.co for o in obs for v in o.data.vertices]
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        base = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
        for o in obs:
            o.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-base))
            o.data.materials.clear()
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.active_object
        ob.name = name
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), use_selection=True,
                                  use_active_scene=True, export_animations=False, export_materials="NONE")
        d = ob.dimensions
        print(name, len(ob.data.polygons), "tamaño", round(d.x, 2), round(d.y, 2), round(d.z, 2))
    for k in ("Ground", "Puerta"):
        if k in meshes:
            bpy.data.objects.remove(meshes[k])
    # separarlas para verlas
    for i, name in enumerate(PARTS):
        scene.objects[name].location.x = i * 1.6


if __name__ == "__main__" and "--" in sys.argv:
    a = sys.argv[sys.argv.index("--") + 1:]
    run(a[0], a[1] if len(a) > 1 else os.path.join(ROOT, "assets", "models", "mapa"), a[2] if len(a) > 2 else "")
