"""Armaduras del pack "Uruk armor pack" (Brice_VIARD, Sketchfab, CC-BY-4.0) para los goblins normales.

Fuente: ~/Downloads/uruk_armor_pack.glb. Trae armaduras de cuerpo completas (pose T, una malla rígida cada una) y
3 cascos. Las armaduras se DIVIDEN por regiones (cada trozo suelto de la malla va a la región de su centro):
  peto_<set>              pecho y espalda (con las correas del cinturón)
  hombrera_<set>_izq/der  cada hombrera con su correa (izq = lado +X del personaje)
  taparrabo_<set>         cinturón + faldón (solo el uruk: el del berserker es el mismo modelo)
Peto y hombreras forman un set (la pechera) pero se colocan por separado en el editor. Los brazales y las botas del
pack no se exportan. La versión "con escudo" repite el mismo peto y no se usa.

Cada pieza va a assets/models/entities/enemigos/goblins/armaduras/<id>.glb, aligerada (decimado) y con texturas de
512 px. La colocación sobre el goblin se hace a mano en tools/goblin_armor_editor.tscn (el editor de ropa con el
cuerpo del goblin) y se guarda en resources/goblin_armor_fit.json; en el juego se pega al esqueleto del goblin con
ClothingFit.build_skinned.

Uso: blender.exe -b --factory-startup --python tools/blender_goblin_armor.py
     Después, reimportar en Godot: Godot --headless --path . --import
"""
import bpy, bmesh, os
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
SRC = os.path.join(os.path.expanduser("~"), "Downloads", "uruk_armor_pack.glb")
OUT_DIR = os.path.join(REPO, "assets", "models", "entities", "enemigos", "goblins", "armaduras")
TEX_SIZE = 512
MAX_FACES = 3500   # por pieza, tras decimar

# Armaduras: nodo del pack -> (nombre del set, regiones que se exportan)
ARMORS = {
	"Uruk_Armor_L_M_Armor_0": ("uruk", ["peto", "hombrera_izq", "hombrera_der", "taparrabo"]),
	# Armor_Berserker no se usa: su cinturón + faldón es el mismo modelo que el taparrabo uruk
}
# Cascos: id -> nodo del pack
HELMETS = {
	"casco_berserker": "Uruk_Berserk_Helmet_M_Berserk_Helmet_0",
	"casco_uruk": "Helmet_Var01_L1_M_Uruk_Helmet_VAR01_0",
	"casco_uruk_cerrado": "Uruk_Helmet_Var2_M_Uruk_Helmet_Var2_0",
}


def region(dx, z):
	"""Región de un trozo suelto por su centro (unidades del pack: el cuerpo mide ~4,9 de alto, Z arriba, frente -Y;
	dx = distancia lateral al eje del cuerpo, +X = izquierda del personaje)."""
	if z < 1.6:
		return "botas"
	if z < 3.25 and abs(dx) < 0.9:
		return "taparrabo"
	if abs(dx) > 1.25:
		return "brazal"
	if z > 3.85 and abs(dx) > 0.6:
		return "hombrera_izq" if dx > 0 else "hombrera_der"
	if abs(dx) < 0.75:
		return "peto"
	return "brazal"


def _islands(bm):
	seen = set()
	for f in bm.faces:
		if f.index in seen:
			continue
		stack = [f]
		seen.add(f.index)
		grp = []
		while stack:
			x = stack.pop()
			grp.append(x)
			for v in x.verts:
				for g in v.link_faces:
					if g.index not in seen:
						seen.add(g.index)
						stack.append(g)
		yield grp


def _fix_materials(ob, done):
	for slot in ob.material_slots:
		m = slot.material
		if m is None or m in done or m.node_tree is None:
			continue
		done.add(m)
		for n in m.node_tree.nodes:
			if n.type == "TEX_IMAGE" and n.image:
				w, h = n.image.size
				if max(w, h) > TEX_SIZE:
					n.image.scale(TEX_SIZE, TEX_SIZE)


def _loose_copy(ob):
	"""Copia suelta (sin padres) con la transformación del pack aplicada."""
	dup = ob.copy()
	dup.data = ob.data.copy()
	bpy.context.scene.collection.objects.link(dup)
	dup.parent = None
	dup.matrix_world = ob.matrix_world.copy()
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = dup
	dup.select_set(True)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	for attr in list(dup.data.color_attributes):   # sin colores de vértice (Godot los multiplicaría)
		dup.data.color_attributes.remove(attr)
	return dup


def _export(dup, pid, done):
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = dup
	dup.select_set(True)
	faces = len(dup.data.polygons)
	if faces > MAX_FACES:
		mod = dup.modifiers.new("dec", "DECIMATE")
		mod.ratio = MAX_FACES / faces
		bpy.ops.object.modifier_apply(modifier=mod.name)
	_fix_materials(dup, done)
	path = os.path.join(OUT_DIR, pid + ".glb")
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
		export_apply=True, export_animations=False, export_skins=False, export_cameras=False,
		export_lights=False, export_image_format="AUTO", export_yup=True)
	print("[goblin_armor] %s: %d caras, caja %s" % (pid, len(dup.data.polygons), tuple(round(v, 3) for v in dup.dimensions)))
	bpy.data.objects.remove(dup)


def run():
	os.makedirs(OUT_DIR, exist_ok=True)
	for f in os.listdir(OUT_DIR):   # todo lo de esta carpeta lo genera este script
		os.remove(os.path.join(OUT_DIR, f))
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SRC)
	done = set()
	for node, (set_name, regions) in ARMORS.items():
		ob = bpy.data.objects[node]
		cx = ob.matrix_world.translation.x
		for reg in regions:
			dup = _loose_copy(ob)
			bm = bmesh.new()
			bm.from_mesh(dup.data)
			drop = []
			for grp in _islands(bm):
				ps = [v.co for g in grp for v in g.verts]
				c = (Vector([min(p[i] for p in ps) for i in range(3)]) + Vector([max(p[i] for p in ps) for i in range(3)])) / 2
				if region(c.x - cx, c.z) != reg:
					drop.extend(grp)
			bmesh.ops.delete(bm, geom=drop, context="FACES")
			bm.to_mesh(dup.data)
			bm.free()
			part, _, side = reg.partition("_")
			_export(dup, "%s_%s%s" % (part, set_name, "_" + side if side else ""), done)
	for pid, node in HELMETS.items():
		_export(_loose_copy(bpy.data.objects[node]), pid, done)


run()
