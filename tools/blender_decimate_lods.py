"""Genera los LOD de los enemigos en Blender (ejecutar desde el editor de scripts o con el MCP de Blender).

Flujo completo cuando cambia un modelo o animación de enemigo:
  1. godot --headless --path . -s tools/bake_enemy_vat.gd   -> (1ª pasada) deja el modelo original en assets/vat/_work/<clave>.obj
  2. (Blender) ejecutar este script                           -> assets/vat/_work/<clave>_lod0.obj, _lod1.obj, _lod2.obj
  3. godot --headless --path . -s tools/bake_enemy_vat.gd   -> (2ª pasada) mallas y texturas VAT con los LOD
Ajustar WORK a la ruta del proyecto.
"""
import bpy, bmesh

WORK = r"C:/Users/cabeu/Downloads/rumbang-0.1-main/rumbang-0.1-main/assets/vat/_work/"
KEYS = ["magoblin", "normal", "bruto", "zombie"]
RATIOS = {"lod0": 0.50, "lod1": 0.22, "lod2": 0.09}   # fracción de triángulos que se conserva (lod0 = malla base)

col = bpy.data.collections.get("LOD_WORK") or bpy.data.collections.new("LOD_WORK")
if col.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(col)

def tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)

for key in KEYS:
    before = set(bpy.data.objects.keys())
    bpy.ops.wm.obj_import(filepath=WORK + key + ".obj", forward_axis='NEGATIVE_Z', up_axis='Y')
    obj = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before][0]
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    # La malla viene "desenrollada": se sueldan los vértices por posición para que Decimate pueda colapsar aristas
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    for lod, ratio in RATIOS.items():
        dup = obj.copy()
        dup.data = obj.data.copy()
        col.objects.link(dup)
        mod = dup.modifiers.new("dec", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = dup
        bpy.ops.object.select_all(action='DESELECT')
        dup.select_set(True)
        bpy.ops.object.modifier_apply(modifier="dec")
        print(key, lod, tris(dup), "triángulos")
        bpy.ops.wm.obj_export(filepath=WORK + key + "_" + lod + ".obj", export_selected_objects=True,
                              forward_axis='NEGATIVE_Z', up_axis='Y', export_materials=False,
                              export_normals=True, export_uv=True, export_triangulated_mesh=True)
        bpy.data.objects.remove(dup, do_unlink=True)
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.data.collections.remove(col)
