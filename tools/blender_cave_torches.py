"""Antorcha de pared y brasero de pilar para las Cavernas (DungeonMap).

Uso: blender -b --python tools/blender_cave_torches.py -- <antorcha.glb> <antorchas_decorativas.glb> [salida_dir]
  (también se puede ejecutar dentro de Blender con exec; deja las escenas "TorchBuild" para revisar)

- torch_wall.glb: la antorcha de mano (antorcha.glb, CC-BY 4.0 Clases3d) reducida a TORCH_LEN m,
  inclinada TORCH_TILT hacia fuera de la pared, en un soporte de hierro hecho aquí (placa + brazo + aro).
  Origen = centro de la placa en la pared; frente (hacia la cueva) = -Y en Blender = +Z en Godot.
- brazier_pillar.glb: el pilar-brasero (antorchas_decorativas.glb, CC-BY 4.0 alef.acevedo) a PILLAR_H m de
  alto, origen en el centro de la base.
Imprime dónde va la llama de cada uno en coordenadas de Godot (para DungeonMap.TORCH_FLAME / PILLAR_FLAME).
"""
import sys, os, math
import bpy, bmesh
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else ""
TORCH_LEN = 0.72
TORCH_TILT = math.radians(28.0)
PILLAR_H = 1.6


def import_meshes(path, scene):
    bpy.context.window.scene = scene
    before = set(scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in scene.objects if o not in before and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    return ob


def bounds(ob):
    xs = [v.co for v in ob.data.vertices]
    mn = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    mx = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return mn, mx


def iron_material():
    mat = bpy.data.materials.get("torch_iron") or bpy.data.materials.new("torch_iron")
    mat.use_nodes = True
    b = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.06, 0.055, 0.05, 1.0)
    b.inputs["Metallic"].default_value = 0.85
    b.inputs["Roughness"].default_value = 0.55
    return mat


def bracket(scene, ring_center: Vector, ring_axis: Vector, ring_r: float):
    bm = bmesh.new()
    # placa en la pared (plano XZ, y = 0)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((0.16, 0.035, 0.30, 1.0)) @ Matrix.Translation((0, -0.5, 0)))
    # brazo: de la placa al aro
    a = Vector((0, 0.0, -0.06))
    b = ring_center + Vector((0, ring_r * 0.6, 0))
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.018, radius2=0.018, depth=d.length,
                          matrix=Matrix.Translation((a + b) / 2) @ rot)
    # aro alrededor de la antorcha (8 cilindros cortos formando un anillo)
    q = ring_axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    seg = 10
    for i in range(seg):
        t0 = 2 * math.pi * i / seg
        t1 = 2 * math.pi * (i + 1) / seg
        p0 = q @ Vector((math.cos(t0) * ring_r, math.sin(t0) * ring_r, 0))
        p1 = q @ Vector((math.cos(t1) * ring_r, math.sin(t1) * ring_r, 0))
        dd = p1 - p0
        r2 = dd.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.014, radius2=0.014, depth=dd.length * 1.1,
                              matrix=Matrix.Translation(ring_center + (p0 + p1) / 2) @ r2)
    me = bpy.data.meshes.new("torch_bracket")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("torch_bracket", me)
    scene.collection.objects.link(ob)
    me.materials.append(iron_material())
    for p in me.polygons:
        p.use_smooth = True
    return ob


def build_torch(path, scene):
    ob = import_meshes(path, scene)
    mn, mx = bounds(ob)
    # eje largo = Z (la copa arriba): base en el origen, longitud TORCH_LEN
    s = TORCH_LEN / (mx.z - mn.z)
    center = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    me = ob.data
    for v in me.vertices:
        v.co = (v.co - center) * s
    # inclinar hacia fuera de la pared (-Y) y colocar: el aro abraza la antorcha a 40% de su largo
    tilt = Matrix.Rotation(TORCH_TILT, 4, "X")          # +X: la punta va hacia -Y
    hold = 0.40 * TORCH_LEN
    ring_local = Vector((0, 0, hold))
    offset = Vector((0, -0.17, -0.02)) - (tilt @ ring_local)
    me.transform(Matrix.Translation(offset) @ tilt)
    me.update()
    axis = (tilt.to_3x3() @ Vector((0, 0, 1))).normalized()
    ring_center = offset + tilt @ ring_local
    tip = offset + tilt @ Vector((0, 0, TORCH_LEN))
    br = bracket(scene, ring_center, axis, 0.045 * TORCH_LEN / 0.72 * 1.4)
    select = [ob, br]
    bpy.ops.object.select_all(action="DESELECT")
    for o in select:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    ob.name = "torch_wall"
    return ob, tip


def build_pillar(path, scene):
    ob = import_meshes(path, scene)
    mn, mx = bounds(ob)
    s = PILLAR_H / (mx.z - mn.z)
    center = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for v in ob.data.vertices:
        v.co = (v.co - center) * s
    ob.data.update()
    ob.name = "brazier_pillar"
    # cuenco: la llama nace un poco por debajo del borde superior
    return ob, Vector((0, 0, PILLAR_H - 0.12))


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, use_active_scene=True, export_animations=False)


def godot(v: Vector):
    return (round(v.x, 3), round(v.z, 3), round(-v.y, 3))


def run(torch_glb, pillar_glb, out_dir):
    scene = bpy.data.scenes.get("TorchBuild")
    if scene:
        for o in list(scene.objects):
            bpy.data.objects.remove(o)
    else:
        scene = bpy.data.scenes.new("TorchBuild")
    torch, tip = build_torch(torch_glb, scene)
    pillar, top = build_pillar(pillar_glb, scene)
    export(torch, os.path.join(out_dir, "torch_wall.glb"))
    export(pillar, os.path.join(out_dir, "brazier_pillar.glb"))
    pillar.location.x = 1.0          # solo para verla al lado (después de exportar)
    print("TORCH_FLAME", godot(tip), "PILLAR_FLAME", godot(top))


if __name__ == "__main__" and "--" in sys.argv:
    a = sys.argv[sys.argv.index("--") + 1:]
    run(a[0], a[1], a[2] if len(a) > 2 else os.path.join(ROOT, "assets", "models", "mapa"))
