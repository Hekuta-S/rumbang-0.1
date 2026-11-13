"""Rejilla de profundidad del escaneo de la Gruta do Janelão, para el relieve de la cueva (CaveShell).

Uso (Blender 5.2, sin MCP):
  blender -b --python tools/blender_cave_relief.py -- <escaneo.glb> <scan_depth.npy> [atlas.png]
y después:
  python tools/make_cave_relief.py <scan_depth.npy>          -> assets/textures/dungeon/cave_scan_height.png
  python tools/make_cave_scan_texture.py <atlas.png>         -> cave_scan_albedo/normal.png

El escaneo es una pared de ~28 x 17 m con el relieve mirando a +Y (Blender). Se lanzan rayos desde +Y
sobre una rejilla X/Z y se guarda la Y del impacto (NaN donde no hay malla).
"""
import sys
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

GRID_W, GRID_H = 448, 272
X_RANGE = (-13.0, 13.0)
Z_RANGE = (7.0, -7.5)          # de arriba abajo (fila 0 = arriba)


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(a) < 2:
        raise SystemExit("uso: -- <escaneo.glb> <scan_depth.npy> [atlas.png]")
    scene = bpy.data.scenes.new("GrutaScan")
    bpy.context.window.scene = scene
    bpy.ops.import_scene.gltf(filepath=a[0])
    co, tris = [], []
    for o in scene.objects:
        if o.type != "MESH":
            continue
        me = o.data
        me.calc_loop_triangles()
        mw = o.matrix_world
        base = len(co)
        co.extend((mw @ v.co)[:] for v in me.vertices)
        tris.extend(tuple(base + i for i in t.vertices) for t in me.loop_triangles)
    bvh = BVHTree.FromPolygons(co, tris, all_triangles=True)
    img = np.full((GRID_H, GRID_W), np.nan)
    for j, z in enumerate(np.linspace(Z_RANGE[0], Z_RANGE[1], GRID_H)):
        for i, x in enumerate(np.linspace(X_RANGE[0], X_RANGE[1], GRID_W)):
            hit = bvh.ray_cast(Vector((x, 8.0, z)), Vector((0, -1, 0)), 20.0)
            if hit[0] is not None:
                img[j, i] = hit[0].y
    np.save(a[1], img)
    if len(a) > 2:
        im = next(i for i in bpy.data.images if i.size[0] > 0 and i.name not in ("Render Result", "Viewer Node"))
        im.filepath_raw = a[2]
        im.file_format = "PNG"
        im.save()
    print("ok", a[1], "huecos", float(np.isnan(img).mean()))


main()
