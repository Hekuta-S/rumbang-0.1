"""Props de mazmorra con la textura cartoon HORNEADA (una lectura), enteros y en piezas.

    blender -b --python tools/blender_toon_dungeon_props.py [-- nombre1,nombre2]

Hasta ahora barriles, cajas, empalizadas, tiendas y demás iban con prop_detail: triplanar de hasta 6 lecturas por
píxel. Aquí se importa cada .glb de assets/models/mapa, se desenvuelve (todas las piezas de un
<prop>_pieces.glb en un mismo atlas), se hornea con el material de tools/blender_toon_props.py (color,
sombra cel, tinta en aristas, detalle dibujado) y se vuelve a exportar con UV. La textura va a
assets/textures/toon/props/<archivo>.png (shader prop_toon; ver ProceduralMap.toon_prop_material y
DestructibleProp._pieces_for). El color de vértice con la oclusión se hornea dentro y se quita del .glb.
Los .glb de antes están en blender_sources/glb_backup_pre_toon/.
"""
import json
import math
import os
import struct
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_toon_props as tp          # noqa: E402  (define bake_material; no ejecuta su main)

MAPA = tp.OUT_GLB
# La choza y el tótem (goblin_hut, goblin_totem y sus _pieces) NO van aquí: son mallas talladas de 10–13 mil
# triángulos y el desenvuelto automático las parte en miles de islas de pocos píxeles; se quedan con
# prop_detail. Hornearlas pide costuras puestas a mano en dungeon_assets.blend.
FILES = ["barrel", "barrel_pieces", "crate", "crate_pieces", "goblin_palisade", "goblin_skull_pole",
         "goblin_campfire", "goblin_tent", "cave_stalagmite"]


def read_materials(path):
    """nombre de material -> (color base, color emisivo o None), leído del propio .glb."""
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    g = json.loads(b[20:20 + n])
    out = {}
    for m in g.get("materials", []):
        base = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
        em = m.get("emissiveFactor")
        out[m.get("name", "")] = (tuple(base), tuple(em) if em and max(em) > 0.0 else None)
    return out


def lookup(mats, name):
    """Blender puede renombrar un material importado (pm_wood.001): se busca también sin el sufijo."""
    if name in mats:
        return mats[name]
    head = name.rsplit(".", 1)[0]
    return mats.get(head, ((0.5, 0.5, 0.5), None))


def process(name, ground):
    path = os.path.join(MAPA, name + ".glb")
    mats = read_materials(path)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    pieces = name.endswith("_pieces")
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(86), island_margin=0.006)
    bpy.ops.object.mode_set(mode='OBJECT')

    area = sum(sum(p.area for p in o.data.polygons) for o in meshes)
    size = 1024 if area > 22.0 else (512 if area > 4.0 else 256)
    image = bpy.data.images.new(name + "_toon", size, size, alpha=False)
    vcol = ""
    if all(len(o.data.color_attributes) > 0 for o in meshes):
        vcol = meshes[0].data.color_attributes[0].name
        if any(o.data.color_attributes[0].name != vcol for o in meshes):
            vcol = ""
    cache = {}
    originals = []
    for o in meshes:
        for slot in o.material_slots:
            src = slot.material
            originals.append((slot, src))
            if src.name not in cache:
                base, em = lookup(mats, src.name)
                cache[src.name] = tp.bake_material(src, image, base=base, emit_color=em, vcol=vcol,
                                                   local_ao=pieces, th_default=0.955, imported=True)
            slot.material = cache[src.name]
    ground.hide_render = pieces
    bpy.ops.object.bake(type='EMIT', margin=6, use_clear=True)
    for slot, src in originals:
        slot.material = src
    image.filepath_raw = os.path.join(tp.OUT_TEX, name + ".png")
    image.file_format = 'PNG'
    image.save()
    # El color de vértice ya está en la textura: fuera (y así no se exporta mal, ver dungeon_structures._gltf)
    for o in meshes:
        while o.data.color_attributes:
            o.data.color_attributes.remove(o.data.color_attributes[0])
    bpy.ops.object.select_all(action='DESELECT')
    for o in new:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False)
    print("TOON", name, "objetos", len(meshes), "area %.1f" % area, "tex", size, "vcol", vcol or "-")
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[0].split(",") if argv else None
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = tp.SAMPLES
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "bake_ground"
    for name in FILES:
        if only and name not in only:
            continue
        process(name, ground)


main()
