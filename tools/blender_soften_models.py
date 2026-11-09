"""Suaviza un poco los modelos low poly originales del mapa (sin cambiar su silueta ni su estilo).

Lee los originales de blender_sources/backup/mapa_old/ y escribe en assets/models/mapa/:
 - biselado muy pequeño en las aristas marcadas (quita el filo de cuchilla),
 - sombreado suave en las superficies casi planas y aristas duras en los ángulos cerrados.
Uso: blender -b --factory-startup -P tools/blender_soften_models.py
"""
import bpy, math, os

ROOT = r"C:/Users/cabeu/Downloads/rumbang-0.1-main/rumbang-0.1-main/"
SRC = ROOT + "blender_sources/backup/mapa_old/"
OUT = ROOT + "assets/models/mapa/"
# La choza y el tótem ya no salen de aquí: se hacen pieza a pieza en blender_sources/dungeon_assets.blend
# (texto dungeon_structures.py) junto con su <nombre>_pieces.glb.
NAMES = ["goblin_palisade", "goblin_skull_pole", "goblin_campfire", "goblin_tent", "mushroom", "cave_stalagmite"]
BEVEL = 0.04           # m
SPLIT_ANGLE = 62       # grados: por encima de esto la arista queda dura (las cajas de 90° siguen duras)


def soften(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    bpy.ops.import_scene.gltf(filepath=SRC + name + ".glb")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    before = len(o.data.polygons)
    bpy.ops.object.shade_smooth()
    bev = o.modifiers.new("bevel", "BEVEL")
    bev.width = BEVEL
    bev.segments = 2
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(35)
    bev.harden_normals = False
    es = o.modifiers.new("split", "EDGE_SPLIT")
    es.split_angle = math.radians(SPLIT_ANGLE)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT + name + ".glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    print(name, "caras:", before, "->", len(o.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.polygons))


for n in NAMES:
    soften(n)
print("OK")
