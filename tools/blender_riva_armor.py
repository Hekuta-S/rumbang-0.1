"""Armaduras del pack embersstorm_magic_weapons__shields_pack.glb para el personaje (Riva).

El pack trae 4 sets elementales (fuego, sombra, frío, natural) en vista despiezada; cada pieza es una malla
"Object_N" con la textura común y, en la versión con brillo, otra malla de brillo (material Fire/Shadow/Cold/Natural).
Aquí se extrae cada pieza, se orienta (frente a -Y, Z arriba) y se normaliza a una CAJA UNIDAD, igual que los
accesorios de Riva: x en [-0.5, 0.5], y en [-0.5, 0.5] (-Y = frente), z en [0, 1]. En el juego
CharacterLookApplier la escala a la caja de su región del cuerpo con el ajuste de resources/armor_fit.json
(factores y desplazamientos relativos a esa caja), que se afina a ojo como los cascos.

Piezas del pack (ver tools/blender_riva_armor.py: PIECES):
  pechera  = peto + espaldar unidos por correas (Object_34/35, 70/71, 130/131, 190/191 según el set)
  hombrera_izq / hombrera_der = casquete del hombro con su correa negra (dos mallas distintas por set)
  muslo / rodilla / espinilla (izq y der) = armadura de la pierna: tres piezas por pierna (z ≈ 1.8, 0.4 y -0.8 en el pack)
  brazo_izq / brazo_der = pieza del resto del brazo, anillada, con su banda negra (Object_67/68 y 79/80 en sombra, ...)

Uso: blender.exe -b --factory-startup --python tools/blender_riva_armor.py
     (o con interfaz por el MCP; trabaja en una escena aparte y se limpia). Después, reimportar en Godot:
     Godot --headless --path . --import
"""
import bpy, bmesh, math, os, runpy
import numpy as np
from mathutils import Vector, Matrix

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
SRC = os.path.join(os.path.expanduser("~"), "Downloads", "embersstorm_magic_weapons__shields_pack.glb")
OUT_DIR = os.path.join(REPO, "assets", "models", "riva", "armaduras")
TEX_SIZE = 512
GLOW_MATS = ("Fire", "Shadow", "Cold", "Natural")   # materiales de brillo del pack

# Mallas del pack por set y pieza (la de textura y, detrás, la de brillo)
# Las hombreras son dos mallas distintas por set: "izq" = la del lado +Y del pack (el lado izquierdo del personaje
# tras girar -90° sobre Z) y "der" = la del lado -Y.
SETS = {
	"fuego":   {"pechera": ["Object_34", "Object_35"], "hombrera_izq": ["Object_28", "Object_29"], "hombrera_der": ["Object_46", "Object_47"], "brazo_izq": ["Object_31", "Object_32"], "brazo_der": ["Object_43", "Object_44"], "muslo_izq": ["Object_37", "Object_38"], "rodilla_izq": ["Object_40", "Object_41"], "espinilla_izq": ["Object_61", "Object_62"], "muslo_der": ["Object_49", "Object_50"], "rodilla_der": ["Object_52", "Object_53"], "espinilla_der": ["Object_55", "Object_56"]},
	"sombra":  {"pechera": ["Object_70", "Object_71"], "hombrera_izq": ["Object_64", "Object_65"], "hombrera_der": ["Object_82", "Object_83"], "brazo_izq": ["Object_67", "Object_68"], "brazo_der": ["Object_79", "Object_80"], "muslo_izq": ["Object_73", "Object_74"], "rodilla_izq": ["Object_76", "Object_77"], "espinilla_izq": ["Object_97", "Object_98"], "muslo_der": ["Object_85", "Object_86"], "rodilla_der": ["Object_88", "Object_89"], "espinilla_der": ["Object_91", "Object_92"]},
	"frio":    {"pechera": ["Object_130", "Object_131"], "hombrera_izq": ["Object_124", "Object_125"], "hombrera_der": ["Object_142", "Object_143"], "brazo_izq": ["Object_127", "Object_128"], "brazo_der": ["Object_139", "Object_140"], "muslo_izq": ["Object_133", "Object_134"], "rodilla_izq": ["Object_136", "Object_137"], "espinilla_izq": ["Object_157", "Object_158"], "muslo_der": ["Object_145", "Object_146"], "rodilla_der": ["Object_148", "Object_149"], "espinilla_der": ["Object_151", "Object_152"]},
	"natural": {"pechera": ["Object_190", "Object_191"], "hombrera_izq": ["Object_184", "Object_185"], "hombrera_der": ["Object_202", "Object_203"], "brazo_izq": ["Object_187", "Object_188"], "brazo_der": ["Object_199", "Object_200"], "muslo_izq": ["Object_193", "Object_194"], "rodilla_izq": ["Object_196", "Object_197"], "espinilla_izq": ["Object_217", "Object_218"], "muslo_der": ["Object_205", "Object_206"], "rodilla_der": ["Object_208", "Object_209"], "espinilla_der": ["Object_211", "Object_212"]},
}
# Giro sobre Z (grados) para que la pieza mire a -Y. En el pack el eje del cuerpo es Y (de lado a lado) y las
# placas delantera/trasera están en X; con -90 el peto queda con la placa de X máxima de frente.
PIECE_ROT_Z = {"pechera": -90.0, "hombrera_izq": -90.0, "hombrera_der": -90.0, "brazo_izq": -90.0, "brazo_der": -90.0,
	"muslo_izq": -90.0, "muslo_der": -90.0, "rodilla_izq": -90.0, "rodilla_der": -90.0, "espinilla_izq": -90.0, "espinilla_der": -90.0}

# Las hombreras y las piezas del brazo del pack están inclinadas ~42° hacia abajo hacia fuera (el modelo del pack está en
# pose A); Riva está en pose T, así que se levantan 42° (sobre Y; el signo depende del lado) para que su eje quede
# horizontal. Medido con el eje principal de cada malla en el plano (lateral, vertical).
A_POSE_TILT = 42.0
# Piernas: en el pack el eje del muslo se inclina ~8° con la parte alta hacia fuera, y el de Riva (hueso UpLeg->Leg en pose T)
# ~5° con la parte alta hacia dentro: se giran 12.4° (la espinilla, 3.1°). La rodilla es casi cuadrada: sin giro.
LEG_THIGH_TILT = 12.4
LEG_SHIN_TILT = 3.1
PIECE_ROT_Y = {"hombrera_izq": -A_POSE_TILT, "hombrera_der": A_POSE_TILT, "brazo_izq": -A_POSE_TILT, "brazo_der": A_POSE_TILT,
	"muslo_izq": -LEG_THIGH_TILT, "muslo_der": LEG_THIGH_TILT, "espinilla_izq": -LEG_SHIN_TILT, "espinilla_der": LEG_SHIN_TILT}

# Las correas y bandas del pack (en las piernas rodean la pierna y en Riva quedan sueltas) se quitan de TODAS las piezas: son
# las caras cuyo color en la textura es el de la correa de su set (medido en la pechera de cada uno; son los grupos de 128
# caras). La caja unidad no se renormaliza al quitarlas, así los ajustes de armor_fit.json siguen valiendo.
STRAP_COLORS = {
	"sombra": (0.051, 0.051, 0.051), "fuego": (0.29, 0.29, 0.29),
	"frio": (0.102, 0.165, 0.227), "natural": (0.102, 0.227, 0.102),
}
STRAP_TOLERANCE = 0.03   # distancia máxima por canal al color de la correa
QUITAR_CORREAS = True

# Temática del set Sombra a juego con el casco "coronado" (blender_riva_helmets.py): hierro negro, filos verde azulado y
# púas doradas curvadas hacia atrás como su corona. Todo en el modelo (sin trucos de shader):
#  - "cells": la textura es una paleta de 8x8 celdas; las caras que usaban una celda (fila desde abajo, columna) pasan a
#    otra moviendo sus UV.
#  - "glow": color nuevo de la malla de brillo del set (base, emisión, fuerza).
#  - "spikes": púas por pieza. at = punto de la caja unidad (x -.5..5, y -.5..5 con -Y = frente, z 0..1) desde el que se
#    lanza un rayo (en "ray" o, si no, en -d) hasta la superficie (si no toca nada, el punto de la superficie más cercano); d = hacia dónde crece (espacio real de la pieza, frente -Y, Z arriba; en las
#    piezas "izq" el exterior es +X y en las "der" se refleja); curl = hacia dónde se curva; length = largo en tamaños de
#    la pieza (su lado mayor). Se añaden ANTES de normalizar, así que no cambian la caja unidad (el ajuste sigue valiendo).
GOLD_CELL = (6, 6)   # ocre dorado
THEMES = {
	"sombra": {
		"cells": {(4, 1): (7, 1), (6, 1): (5, 0)},   # morados -> hierro negro (placas) y negro tostado (detalles, como el óxido del casco)
		"glow": ((0.02, 0.30, 0.27, 1.0), (0.05, 0.75, 0.65, 1.0), 0.8),
		"spikes": {
			# Una sola por hombrera. La pieza está en pose T pero en juego el brazo cuelga (~65° abajo): en pose T la púa
			# apunta hacia el cuello, y con el brazo bajado queda hacia arriba y algo hacia fuera.
			"hombrera": [{"at": (0.05, 0.0, 3.0), "ray": (0.0, 0.0, -1.0), "d": (-1.0, 0.0, 0.55), "curl": (0.0, 1.0, 0.0),
				"length": 0.50}],
			"brazo": [{"at": (x, 0.0, 3.0), "d": (0.35, 0.0, 1.0), "curl": (1.0, 0.0, 0.0), "length": 0.22} for x in (-0.18, 0.12)],
			"rodilla": [{"at": (0.0, -3.0, 0.62), "d": (0.0, -1.0, 0.6), "curl": (0.0, 0.0, 1.0), "length": 0.50}],
			"pechera": [{"at": (x, 0.40, 3.0), "ray": (0.0, 0.0, -1.0), "d": (x * 0.8, 0.35, 1.0), "curl": (0.0, 1.0, 0.0), "length": l}
				for x, l in ((-0.24, 0.17), (0.0, 0.22), (0.24, 0.17))],
		},
	},
}

_lib = None


def _helmets():
	"""Reutiliza las utilidades de blender_riva_helmets.py (importar, hornear la transformación, limpiar)."""
	global _lib
	if _lib is None:
		path = os.path.join(REPO, "tools", "blender_riva_helmets.py")
		_lib = runpy.run_path(path, run_name="lib")
	return _lib


def _fix_materials(objs):
	small = set()
	for ob in objs:
		for slot in ob.material_slots:
			m = slot.material
			if m is None or not m.use_nodes:
				continue
			b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
			if b is None:
				continue
			glow = m.get("orig_name", m.name) in GLOW_MATS
			if not glow:
				b.inputs["Metallic"].default_value = 0.0
				b.inputs["Emission Strength"].default_value = 0.0
				if b.inputs["Roughness"].default_value < 0.5:
					b.inputs["Roughness"].default_value = 0.7
			for n in m.node_tree.nodes:
				if n.type == "TEX_IMAGE" and n.image and n.image not in small:
					small.add(n.image)
					w, h = n.image.size
					if max(w, h) > TEX_SIZE:
						n.image.scale(TEX_SIZE, TEX_SIZE)


def _base_color_image(ob):
	for m in ob.data.materials:
		if m is None or not m.use_nodes:
			continue
		b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if b is None:
			continue
		for l in b.inputs["Base Color"].links:
			if l.from_node.type == "TEX_IMAGE" and l.from_node.image:
				return l.from_node.image
	return None


def _drop_straps(ob, strap_color):
	"""Borra las caras de color gris casi negro (correas). Devuelve cuántas quitó."""
	img = _base_color_image(ob)
	if img is None:
		return 0
	w, h = img.size
	px = np.array(img.pixels[:]).reshape(h, w, 4)
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	uv = bm.loops.layers.uv.active
	dead = []
	for f in bm.faces:
		u = sum((l[uv].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
		c = px[min(max(int(u.y * (h - 1)), 0), h - 1), min(max(int(u.x * (w - 1)), 0), w - 1), :3]
		if float(np.abs(c - np.array(strap_color)).max()) <= STRAP_TOLERANCE:
			dead.append(f)
	bmesh.ops.delete(bm, geom=dead, context="FACES")
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()
	return len(dead)


def _cell_uv(cell):
	return Vector(((cell[1] + 0.5) / 8.0, (cell[0] + 0.5) / 8.0))


def _add_spikes(ob, specs, mirror, lo, size):
	"""Púas doradas (hoja curvada de sección rombo) sobre la malla `ob`, en el espacio real de la pieza."""
	from mathutils.bvhtree import BVHTree
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bvh = BVHTree.FromBMesh(bm)
	uvl = bm.loops.layers.uv.active
	big = max(size)
	sx = -1.0 if mirror else 1.0
	added = 0
	for sp in specs:
		at = Vector((sp["at"][0] * sx, sp["at"][1], sp["at"][2]))
		src = Vector((lo.x + (at.x + 0.5) * size.x, lo.y + (at.y + 0.5) * size.y, lo.z + at.z * size.z))
		d = Vector((sp["d"][0] * sx, sp["d"][1], sp["d"][2])).normalized()
		ray = Vector((sp["ray"][0] * sx, sp["ray"][1], sp["ray"][2])).normalized() if "ray" in sp else -d
		hit, nrm, _, _ = bvh.ray_cast(src, ray)
		if hit is None:   # bordes finos o huecos: el punto de la superficie más cercano al de partida
			hit = bvh.find_nearest(src)[0]
		if hit is None:
			print("[armadura] púa sin superficie", sp)
			continue
		c = Vector((sp["curl"][0] * sx, sp["curl"][1], sp["curl"][2]))
		c = (c - c.dot(d) * d).normalized()
		L = sp["length"] * big
		w0, t0 = 0.62 * L, 0.20 * L   # hoja ancha y plana, como las de la corona del casco
		rings = []
		n_seg = 6
		for i in range(n_seg + 1):
			t = -0.18 + 1.18 * i / n_seg               # empieza algo hundida en la placa
			tt = max(t, 0.0)
			P = hit + d * (L * t) + c * (L * 0.38 * tt * tt)
			T = (d + c * (2 * L * 0.38 * tt / L)).normalized()
			Wd = (c - c.dot(T) * T).normalized()
			Nd = T.cross(Wd).normalized()
			f = (1.0 - max(tt, 0.0)) ** 1.15
			if i == n_seg:
				rings.append([bm.verts.new(P)])
				break
			rings.append([bm.verts.new(P + Wd * (w0 * 0.5 * f)), bm.verts.new(P + Nd * (t0 * 0.5 * f)),
				bm.verts.new(P - Wd * (w0 * 0.5 * f)), bm.verts.new(P - Nd * (t0 * 0.5 * f))])
		faces = [bm.faces.new(list(reversed(rings[0])))]
		for a, b in zip(rings[:-1], rings[1:]):
			for k in range(4):
				if len(b) == 1:
					faces.append(bm.faces.new((a[k], a[(k + 1) % 4], b[0])))
				else:
					faces.append(bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])))
		uv = _cell_uv(GOLD_CELL)
		for f in faces:
			f.material_index = 0
			f.smooth = False
			for l in f.loops:
				l[uvl].uv = uv
		added += 1
	bm.normal_update()
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()
	return added


def _retheme(objs, theme):
	"""Cambia las celdas de la paleta (moviendo UV) y el color de la malla de brillo."""
	for ob in objs:
		glow = any(m and m.get("orig_name", m.name) in GLOW_MATS for m in ob.data.materials)
		if glow and "glow" in theme:
			base, emit, strength = theme["glow"]
			for m in ob.data.materials:
				b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
				if b:
					b.inputs["Base Color"].default_value = base
					b.inputs["Emission Color"].default_value = emit
					b.inputs["Emission Strength"].default_value = strength
		uv = ob.data.uv_layers.active
		if uv is None or glow:
			continue
		for p in ob.data.polygons:
			u = sum(uv.data[li].uv.x for li in p.loop_indices) / p.loop_total
			v = sum(uv.data[li].uv.y for li in p.loop_indices) / p.loop_total
			cell = (min(int(v * 8), 7), min(int(u * 8), 7))
			to = theme.get("cells", {}).get(cell)
			if to:
				off = Vector(((to[1] - cell[1]) / 8.0, (to[0] - cell[0]) / 8.0))
				for li in p.loop_indices:
					uv.data[li].uv = uv.data[li].uv + off


def build(set_id, piece, names, sc):
	"""Extrae las mallas `names` del pack, las orienta y las normaliza a la caja unidad. Devuelve (objetos, info)."""
	lib = _helmets()
	before = set(sc.objects)
	lib["_import"](SRC)
	all_meshes = lib["_world_mesh_objects"](sc, before)
	keep = [o for o in all_meshes if o.name in names]
	assert len(keep) == len(names), "faltan mallas %s en el pack" % names
	for o in all_meshes:
		if o not in keep:
			bpy.data.objects.remove(o)
	for o in keep:
		for m in o.data.materials:
			if m and "orig_name" not in m:
				m["orig_name"] = m.name
		lib["_bake_world"](o)
	for o in [o for o in sc.objects if o not in before and o.type != "MESH"]:
		bpy.data.objects.remove(o)
	rot = Matrix.Rotation(math.radians(PIECE_ROT_Z.get(piece, 0.0)), 4, "Z")
	rot = Matrix.Rotation(math.radians(PIECE_ROT_Y.get(piece, 0.0)), 4, "Y") @ rot   # pose A -> pose T
	for o in keep:
		o.data.transform(rot)
	pts = [p for o in keep for p in lib["_pts"](o)]
	lo, hi = lib["_bounds"](pts)
	size = hi - lo
	c = (lo + hi) * 0.5
	norm = Matrix.Diagonal((1.0 / size.x, 1.0 / size.y, 1.0 / size.z, 1.0)) @ Matrix.Translation(Vector((-c.x, -c.y, -lo.z)))
	theme = THEMES.get(set_id, {})
	kind = piece.rsplit("_", 1)[0] if piece.endswith(("_izq", "_der")) else piece
	spikes = 0
	if theme.get("spikes", {}).get(kind):   # en la malla con textura (no la de brillo), antes de normalizar
		tex = next(o for o in keep if not any(m and m.get("orig_name", m.name) in GLOW_MATS for m in o.data.materials))
		spikes = _add_spikes(tex, theme["spikes"][kind], piece.endswith("_der"), lo, size)
	for o in keep:
		o.data.transform(norm)
		o.data.update()
	removed = 0
	if QUITAR_CORREAS:
		for o in keep:
			removed += _drop_straps(o, STRAP_COLORS[set_id])
	if theme:
		_retheme(keep, theme)
	_fix_materials(keep)
	mats = []
	for o in keep:
		for s in o.material_slots:
			if s.material and s.material not in mats:
				mats.append(s.material)
	for i, m in enumerate(mats):
		m.name = "arm_%s_%s_%d" % (set_id, piece, i)
	for k, o in enumerate(keep):
		o.name = "arm_%s_%s_%d" % (set_id, piece, k)
		o.data.name = o.name
	return keep, {"src_size": tuple(round(x, 3) for x in size), "correas_quitadas": removed, "puas": spikes,
		"tris": sum(len(p.vertices) - 2 for o in keep for p in o.data.polygons)}


def run(only_sets=None, only_pieces=None):
	lib = _helmets()
	os.makedirs(OUT_DIR, exist_ok=True)
	prev = bpy.context.window.scene if bpy.context.window else None
	if prev:
		sc = bpy.data.scenes.get("RivaArmor") or bpy.data.scenes.new("RivaArmor")
		bpy.context.window.scene = sc
	else:
		sc = bpy.context.scene
		for o in list(sc.objects):
			bpy.data.objects.remove(o)
	snap = lib["_snapshot"]()
	report = {}
	try:
		for set_id, pieces in SETS.items():
			if only_sets and set_id not in only_sets:
				continue
			for piece, names in pieces.items():
				if only_pieces and piece not in only_pieces:
					continue
				objs, info = build(set_id, piece, names, sc)
				lib["export"](objs, os.path.join(OUT_DIR, "%s_%s.glb" % (set_id, piece)))
				report["%s_%s" % (set_id, piece)] = info
				print("[armadura]", set_id, piece, info)
				for o in list(objs):
					bpy.data.objects.remove(o)
	finally:
		if prev:
			bpy.context.window.scene = prev
		lib["_purge"](snap)
		if prev:
			bpy.data.scenes.remove(sc)
	return report


if __name__ == "__main__":
	run()
