"""Cascos del personaje (Riva): normaliza los GLB descargados y los exporta a assets/models/riva/cascos/.

Cada casco sale NORMALIZADO para que CharacterLookApplier lo coloque con ESCALA UNIFORME (los cuernos no
se deben estirar como un gorro) y para que la Fase 2 (ajuste a la cabeza) parta de una referencia común:

  - Unidades: el ANCHO (eje X) del "núcleo" del casco (la cúpula, sin cuernos ni crestas) es 1.0.
  - Origen: centro X/Y del núcleo; z = 0 en el borde inferior del núcleo (por donde entra la cabeza).
  - Frente hacia -Y de Blender (el exportador glTF lo pasa a +Z de Godot, Y arriba).
  - Sin animaciones, sin mallas de contorno, metálico 0 (en Godot sin reflejos un metal se ve negro),
    emisión apagada y texturas a 512 px.
  - Materiales `helm_<id>_<n>`: NO empiezan por acc_, así que el aplicador no los recolorea.

Además imprime (y devuelve) el tamaño del casco ya normalizado, que la Fase 2 usa para calcular el ajuste.

Uso: blender.exe -b --factory-startup --python tools/blender_riva_helmets.py
     o en el MCP: exec(open(r"<repo>/tools/blender_riva_helmets.py").read(), {"__name__": "x"}); run()
     (con interfaz trabaja en una escena aparte "RivaHelmets" y la borra, junto con sus datos, al terminar)
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
SRC_DIR = os.path.join(os.path.expanduser("~"), "Downloads")
OUT_DIR = os.path.join(REPO, "assets", "models", "riva", "cascos")
TEX_SIZE = 512

# id -> configuración. Claves:
#   file       GLB de origen (en SRC_DIR)
#   drop       fragmentos del nombre de mallas que se descartan (mallas de contorno negras, duplicados)
#   rot_z      grados sobre Z para que la frente mire a -Y (se mide en la importación, ya con Z arriba)
#   rot_y      grados sobre Y (ladeo) para enderezar modelos torcidos; se mide buscando la simetría izquierda/derecha
#   core       cómo se mide la cúpula: {"meshes": [fragmentos de nombre]} | {"zband": (a, b)} (fracciones de alto)
#              | {} (todo)
#   recenter   fragmentos de nombre de mallas que se recentran sobre el núcleo (arreglo de modelos descentrados)
#   mirror_largest  fragmentos de nombre de mallas con piezas sueltas (p. ej. cuernos) de las que se conserva la
#              mayor y se refleja en X (el modelo trae un cuerno largo y un muñón); se aplica ya normalizado
#   colors     material original -> color base (solo materiales SIN textura; los de textura no se tocan)
HELMETS = {
	"cruzado": {
		"file": "crusader_great_helmet_low_poly.glb", "rot_z": 0.0, "core": {},
		"colors": {"Material.002": (0.55, 0.57, 0.62, 1), "Material.001": (0.80, 0.58, 0.14, 1)},
	},
	"cornudo": {
		"file": "horned_helmet.glb", "rot_z": 180.0, "drop": [".002_0"], "core": {"zband": (0.0, 0.5)},
	},
	"vikingo": {
		# Los dos cuernos vienen pegados al lado +X de la cúpula: se recentran sobre ella; la cresta va en X
		"file": "horned_viking_helmet.glb", "rot_z": -90.0, "core": {"meshes": ["Object_5"]},
		"recenter": ["Object_4"], "mirror_largest": ["Object_4"],
	},
	"nordico": {
		"file": "skyrim_helmet_low_poly.glb", "rot_z": 0.0, "rot_y": 8.0, "core": {"meshes": ["Helmet_0"]},
		"colors": {"Helmet": (0.10, 0.10, 0.12, 1), "Horn": (0.78, 0.74, 0.58, 1)},
	},
	"fantasia": {
		"file": "fantasy_helmet_low_poly.glb", "rot_z": 0.0, "core": {},
	},
	"coronado": {
		# "Helmet" de RimasBe (Sketchfab, CC-BY-4.0): hierro negro, corona de púas doradas y colmillos de hueso en las
		# mejillas. Ya mira a -Y. El núcleo es la franja media de la cúpula (sin las púas de arriba ni los colmillos).
		"file": "helmet.glb", "rot_z": 0.0, "core": {"zband": (0.45, 0.75)},
	},
}


def _snapshot():
	return {k: set(getattr(bpy.data, k)) for k in _KINDS}


_KINDS = ("objects", "meshes", "materials", "images", "actions", "armatures", "scenes")   # el importador glTF crea escenas vacías


def _purge(before):
	"""Borra todo lo que se importó desde `before` (escena del usuario intacta)."""
	for k in _KINDS:
		coll = getattr(bpy.data, k)
		for d in list(coll):
			if d not in before[k]:
				coll.remove(d)


def _import(path):
	bpy.ops.import_scene.gltf(filepath=path)


def _world_mesh_objects(sc, before_objs):
	return [o for o in sc.objects if o not in before_objs and o.type == "MESH"]


def _bake_world(ob):
	"""Aplica la transformación de mundo a la malla y suelta el padre (queda en el origen, sin escala)."""
	mw = ob.matrix_world.copy()
	ob.parent = None
	ob.data.transform(mw)
	ob.matrix_world = Matrix.Identity(4)
	if ob.data.shape_keys is None:
		ob.data.update()


def _pts(ob):
	return [ob.matrix_world @ v.co for v in ob.data.vertices]


def _bounds(pts):
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


def _mirror_largest(ob):
	"""Se queda con la pieza suelta más grande de la malla y la refleja respecto a x = 0 (par simétrico)."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.verts.ensure_lookup_table()
	seen, islands = set(), []
	for v in bm.verts:
		if v.index in seen:
			continue
		stack, comp = [v], []
		seen.add(v.index)
		while stack:
			a = stack.pop()
			comp.append(a)
			for e in a.link_edges:
				b = e.other_vert(a)
				if b.index not in seen:
					seen.add(b.index)
					stack.append(b)
		islands.append(comp)
	if len(islands) < 2:
		bm.free()
		return
	keep = set(max(islands, key=len))
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in keep], context="VERTS")
	twin = bm.copy()
	bmesh.ops.transform(twin, matrix=Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)), verts=twin.verts)
	bmesh.ops.reverse_faces(twin, faces=twin.faces)
	tmp = bpy.data.meshes.new("mirror_tmp")
	twin.to_mesh(tmp)
	twin.free()
	bm.from_mesh(tmp)
	bpy.data.meshes.remove(tmp)
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


def _core_points(objs, core):
	allp = [p for o in objs for p in _pts(o)]
	if "meshes" in core:
		sel = [o for o in objs if any(f in o.name for f in core["meshes"])]
		return [p for o in sel for p in _pts(o)]
	if "zband" in core:
		lo, hi = _bounds(allp)
		a, b = core["zband"]
		return [p for p in allp if lo.z + a * (hi.z - lo.z) <= p.z <= lo.z + b * (hi.z - lo.z)]
	return allp


def _fix_materials(objs, cfg):
	small = set()
	for ob in objs:
		for slot in ob.material_slots:
			m = slot.material
			if m is None or not m.use_nodes:
				continue
			b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
			if b is None:
				continue
			for l in list(b.inputs["Metallic"].links):   # metálico por textura: también fuera (se vería negro)
				m.node_tree.links.remove(l)
			b.inputs["Metallic"].default_value = 0.0
			b.inputs["Emission Strength"].default_value = 0.0
			textured = bool(b.inputs["Base Color"].links)
			col = cfg.get("colors", {}).get(m.get("orig_name", m.name))
			if col and not textured:
				b.inputs["Base Color"].default_value = col
			if b.inputs["Roughness"].default_value < 0.5:
				b.inputs["Roughness"].default_value = 0.7
			for n in m.node_tree.nodes:
				if n.type == "TEX_IMAGE" and n.image and n.image not in small:
					small.add(n.image)
					w, h = n.image.size
					if max(w, h) > TEX_SIZE:
						n.image.scale(TEX_SIZE, TEX_SIZE)


def build(hid, cfg, sc):
	"""Importa, limpia y normaliza un casco. Devuelve la lista de objetos listos para exportar y sus medidas."""
	before = set(sc.objects)
	_import(os.path.join(SRC_DIR, cfg["file"]))
	objs = _world_mesh_objects(sc, before)
	for o in objs:
		o.data.materials  # asegura la carga
		for m in o.data.materials:
			if m and "orig_name" not in m:
				m["orig_name"] = m.name
	# Fuera mallas de contorno / duplicados
	for frag in cfg.get("drop", []):
		for o in [o for o in objs if frag in o.name]:
			objs.remove(o)
			bpy.data.objects.remove(o)
	for o in objs:
		_bake_world(o)
	# Quitar los vacíos de la importación (y con ellos animaciones)
	for o in [o for o in sc.objects if o not in before and o.type != "MESH"]:
		bpy.data.objects.remove(o)
	# Orientación: la frente a -Y
	rot = Matrix.Rotation(math.radians(cfg.get("rot_z", 0.0)), 4, "Z")
	rot = Matrix.Rotation(math.radians(cfg.get("rot_y", 0.0)), 4, "Y") @ rot   # ladeo (la frente sigue a -Y)
	for o in objs:
		o.data.transform(rot)
	# Núcleo (cúpula) = referencia de medida
	cpts = _core_points(objs, cfg.get("core", {}))
	clo, chi = _bounds(cpts)
	cc = (clo + chi) * 0.5
	# Recentrar piezas descentradas (cuernos pegados a un lado)
	for frag in cfg.get("recenter", []):
		for o in [o for o in objs if frag in o.name]:
			lo, hi = _bounds(_pts(o))
			c = (lo + hi) * 0.5
			o.data.transform(Matrix.Translation(Vector((cc.x - c.x, cc.y - c.y, 0.0))))
	# Escala uniforme: ancho del núcleo = 1; origen en el centro XY y el borde inferior del núcleo
	width = chi.x - clo.x
	norm = Matrix.Scale(1.0 / width, 4) @ Matrix.Translation(Vector((-cc.x, -cc.y, -clo.z)))
	for o in objs:
		o.data.transform(norm)
		o.data.update()
	for frag in cfg.get("mirror_largest", []):
		for o in [o for o in objs if frag in o.name]:
			_mirror_largest(o)
	_fix_materials(objs, cfg)
	mats = []
	for o in objs:
		for s in o.material_slots:
			if s.material and s.material not in mats:
				mats.append(s.material)
	for i, m in enumerate(mats):
		m.name = "helm_%s_%d" % (hid, i)
	for k, o in enumerate(objs):
		o.name = "helm_%s_%d" % (hid, k)
		o.data.name = o.name
	allp = [p for o in objs for p in _pts(o)]
	lo, hi = _bounds(allp)
	return objs, {"core_width_src": round(width, 4), "size": tuple(round(x, 3) for x in (hi - lo)),
		"min": tuple(round(x, 3) for x in lo), "max": tuple(round(x, 3) for x in hi),
		"tris": sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)}


def export(objs, path):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, use_active_scene=True, export_apply=True,
		export_animations=False, export_skins=False, export_cameras=False, export_lights=False,
		export_image_format="AUTO", export_yup=True)


def run(only=None):
	os.makedirs(OUT_DIR, exist_ok=True)
	prev = bpy.context.window.scene if bpy.context.window else None
	if prev:   # Blender con interfaz (MCP): escena aparte para no tocar la del usuario
		sc = bpy.data.scenes.get("RivaHelmets") or bpy.data.scenes.new("RivaHelmets")
		bpy.context.window.scene = sc
	else:                    # blender -b --factory-startup: fuera el cubo/cámara/luz de la escena por defecto
		sc = bpy.context.scene
		for o in list(sc.objects):
			bpy.data.objects.remove(o)
	snap = _snapshot()
	report = {}
	try:
		for hid, cfg in HELMETS.items():
			if only and hid not in only:
				continue
			objs, info = build(hid, cfg, sc)
			export(objs, os.path.join(OUT_DIR, hid + ".glb"))
			report[hid] = info
			print("[cascos]", hid, info)
			for o in list(objs):
				bpy.data.objects.remove(o)
	finally:
		if prev:
			bpy.context.window.scene = prev
		_purge(snap)
		if prev:
			bpy.data.scenes.remove(sc)
	return report


if __name__ == "__main__":
	run()
