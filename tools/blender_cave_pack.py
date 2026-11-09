"""Piezas de decoración de las Cavernas sacadas del "Cave River Pack" (placeholder, Sketchfab STHModels).

Uso: blender -b --python tools/blender_cave_pack.py -- <poppy_playtime_cave_river_pack.glb> [salida_dir]

Cada pieza se diezma (aspecto algo menos detallado, coherente con la carcasa), se pasa a coordenadas del
mundo, se coloca con el origen en el centro de la base (z = 0) y se exporta SIN materiales: en Godot llevan
el shader cave_rock (textura de la gruta en triplanar, teñida con la paleta del nivel) como las paredes.
  - Las estalactitas del pack apuntan hacia arriba: se exportan dadas la vuelta, con el origen en la base
    ancha (que va pegada al techo) y colgando hacia -Z (-Y en Godot).
  - Los acantilados son placas curvas con la cara convexa hacia -Y (frente = +Z en Godot).
"""
import sys, os
import bpy, bmesh
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else ""
# salida: (pieza del pack, caras objetivo, colgar del techo)
PIECES = {
	"cave_stalactite_a": ("SM_Cave_Stalagtites_A", 1400, True),
	"cave_stalactite_b": ("SM_Cave_Stalagtites_B", 1000, True),
	"cave_stalactite_c": ("SM_Cave_Stalagtites_C", 1600, True),
	"cave_stalagmite_d": ("SM_Cave_Stalagmites_D", 2400, False),
	"cave_pillar":       ("SM_CavePillar_Large", 2400, False),
	"cave_rock_01":      ("sm_Rock_01", 900, False),
	"cave_rock_04":      ("sm_Rock_04", 800, False),
	"cave_cliff_a":      ("sm_Cliff_02_03", 1800, False),
	"cave_cliff_b":      ("sm_Cliff_03_02", 1800, False),
	"cave_cliff_c":      ("sm_Cliff_03_03", 1800, False),
	"cave_cliff_d":      ("sm_Cliff_04_03", 1800, False),
}


def run(src, out_dir):
	scene = bpy.data.scenes.get("PackBuild")
	if scene:
		for o in list(scene.objects):
			bpy.data.objects.remove(o)
	else:
		scene = bpy.data.scenes.new("PackBuild")
	bpy.context.window.scene = scene
	bpy.ops.import_scene.gltf(filepath=src)
	by_name = {o.name.split(".")[0]: o for o in scene.objects if o.type == "MESH"}
	report = []
	for out, (piece, faces, hang) in PIECES.items():
		src_ob = by_name[piece]
		me = src_ob.data.copy()
		me.transform(src_ob.matrix_world)
		ob = bpy.data.objects.new(out, me)
		scene.collection.objects.link(ob)
		me.materials.clear()
		pts = [v.co for v in me.vertices]
		mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
		mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
		base = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
		m = Matrix.Translation(-base)
		if hang:
			m = Matrix.Rotation(3.14159265, 4, "X") @ m        # base ancha arriba (z = 0), punta hacia -Z
		me.transform(m)
		bpy.ops.object.select_all(action="DESELECT")
		ob.select_set(True)
		bpy.context.view_layer.objects.active = ob
		d = ob.modifiers.new("dec", "DECIMATE")
		d.ratio = min(1.0, faces / max(1, len(me.polygons)))
		bpy.ops.object.modifier_apply(modifier="dec")
		ob.data.validate()
		# Normales limpias: fuera las personalizadas del glTF (la reducción las estropea) y todas hacia fuera
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
		bm = bmesh.new()
		bm.from_mesh(ob.data)
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
		bm.to_mesh(ob.data)
		bm.free()
		for p in ob.data.polygons:
			p.use_smooth = True
		bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, out + ".glb"), use_selection=True,
								  use_active_scene=True, export_animations=False, export_materials="NONE")
		dd = ob.dimensions
		report.append("%s %d caras %.2fx%.2fx%.2f" % (out, len(ob.data.polygons), dd.x, dd.y, dd.z))
	print("\n".join(report))


if __name__ == "__main__" and "--" in sys.argv:
	a = sys.argv[sys.argv.index("--") + 1:]
	run(a[0], a[1] if len(a) > 1 else os.path.join(ROOT, "assets", "models", "mapa"))
