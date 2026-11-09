"""Personaje personalizable v3 (estilo PS3): humano de MPFB/MakeHuman (CC0) adaptado al esqueleto de Riva.

Sustituye al cuerpo en calzones sacado de Riva (tools/blender_riva_base.py) por un humano realista con rasgos
anime sutiles, conservando el esqueleto RivaBaseArmature (los clips riva-*.fbx siguen valiendo).

Requisitos en Blender: extensión MPFB 2.x y el pack "makehuman_system_assets" (CC0) instalado en MPFB.

Pasos (desde el MCP, con blender_sources/rumbang_anims.blend abierto):
  ns = {"__name__": "riva_human", "__file__": r"<repo>/tools/blender_riva_human.py"}
  exec(open(ns["__file__"], encoding="utf-8").read(), ns)
  ns["create"]()        # escena RivaHumano: humano + rig mixamo + piel, ojos, cejas, pestañas, peinados
  ns["conform"]()       # posa el rig para que cada hueso caiga sobre el de Riva y hornea la deformación
  ns["finish"]()        # une las piezas, ropa interior, materiales rb_*, sustituye RivaBase en Riva_Personaje
  ns["bake_textures"]() # texturas para Godot (assets/textures/entities/riva/)
  ns["export"]()        # riva-base.fbx + peinados .glb
"""
import bpy, bmesh, math, os, json
import numpy as np
from mathutils import Vector, Matrix

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE = "RivaHumano"
RIVA_SCENE = "Riva_Personaje"
RIVA_ARM = "RivaBaseArmature"
RIVA_MESH = "RivaBase"
HUMAN = "Human"
P = "mixamorig:"

# Chico joven, atlético y delgado; mezcla de rasgos para que cualquier tono de piel quede creíble.
MACRO = {"gender": 1.0, "age": 0.45, "muscle": 0.62, "weight": 0.45, "proportions": 0.75, "height": 0.6,
	"cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.40, "caucasian": 0.50, "african": 0.10}}
# Anime sutil: ojos algo más grandes y abiertos, nariz y boca finas, mandíbula en V suave, cara joven.
STYLE = {
	"l-eye-scale-incr": 0.35, "r-eye-scale-incr": 0.35, "l-eye-height2-incr": 0.25, "r-eye-height2-incr": 0.25,
	"nose-scale-horiz-decr": 0.30, "nose-volume-decr": 0.30, "nose-point-width-decr": 0.35, "nose-scale-vert-decr": 0.15,
	"chin-width-decr": 0.25, "chin-triangle": 0.25, "chin-prominent-incr": 0.10, "head-oval": 0.30,
	"head-age-decr": 0.25, "mouth-scale-horiz-decr": 0.15,
}
# Huesos que NO se giran hacia la dirección del de Riva: conservan la postura natural del humano (espalda
# recta, cabeza erguida, pie plano). El esqueleto mantiene la orientación de Riva, así que los clips aplican
# sus giros relativos sobre esa postura. Los pies además recuperan su orientación original tras girar la pierna.
KEEP_NATURAL = {"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"}
NO_STRETCH = {"Head"}


def _bare(name):
	return name[len(P):] if name.startswith(P) else name


def scenes():
	return bpy.data.scenes[SCENE], bpy.data.scenes[RIVA_SCENE]


def riva_objs():
	rs = bpy.data.scenes[RIVA_SCENE]
	return rs.objects[RIVA_ARM], rs.objects[RIVA_MESH]


def human_objs():
	sc = bpy.data.scenes[SCENE]
	bm = sc.objects[HUMAN]
	rig = bm.parent
	parts = [o for o in sc.objects if o.type == "MESH" and o.parent == rig]
	return bm, rig, parts


# Piezas del pack makehuman_system_assets (fragmento de ruta, subcarpeta)
SKIN = "young_caucasian_male/young_caucasian_male.mhmat"
BODYPARTS = [("eyes", "high-poly/high-poly.mhclo"), ("eyebrows", "eyebrow001/eyebrow001.mhclo"),
	("eyelashes", "eyelashes01/eyelashes01.mhclo")]
HAIRS = ["short02", "short01", "short03", "short04", "afro01", "ponytail01"]


def create_basic():
	"""Como create() pero sin el pack de MakeHuman: humano + rasgos + rig mixamo (ojos de las esferas auxiliares)."""
	from bl_ext.user_default.mpfb.services.humanservice import HumanService
	from bl_ext.user_default.mpfb.services.targetservice import TargetService
	sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
	bpy.context.window.scene = sc
	for ob in list(sc.objects):
		if ob.name != RIVA_ARM:
			bpy.data.objects.remove(ob)
	bm = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
		feet_on_ground=True, scale=0.1, macro_detail_dict=MACRO)
	bm.name = HUMAN
	for n, w in STYLE.items():
		TargetService.load_target(bm, TargetService.target_full_path(n), weight=w, name=n)
	rig = HumanService.add_builtin_rig(bm, "mixamo", import_weights=True)
	return bm, rig


def create():
	"""Escena RivaHumano con el humano, sus rasgos, el rig mixamo de MPFB, piel, ojos, cejas, pestañas y
	todos los peinados (cada uno, objeto Pelo_<id>)."""
	from bl_ext.user_default.mpfb.services.humanservice import HumanService
	from bl_ext.user_default.mpfb.services.targetservice import TargetService
	from bl_ext.user_default.mpfb.services.assetservice import AssetService
	sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
	bpy.context.window.scene = sc
	for ob in list(sc.objects):
		if ob.name != RIVA_ARM:
			bpy.data.objects.remove(ob)
	bm = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
		feet_on_ground=True, scale=0.1, macro_detail_dict=MACRO)
	bm.name = HUMAN
	for n, w in STYLE.items():
		TargetService.load_target(bm, TargetService.target_full_path(n), weight=w, name=n)
	rig = HumanService.add_builtin_rig(bm, "mixamo", import_weights=True)
	skin = AssetService.find_asset_absolute_path(SKIN, asset_subdir="skins")
	HumanService.set_character_skin(skin, bm, skin_type="MAKESKIN")
	for sub, frag in BODYPARTS:
		path = AssetService.find_asset_absolute_path(frag, asset_subdir=sub)
		before = set(sc.objects)
		HumanService.add_mhclo_asset(path, bm, asset_type=sub, subdiv_levels=0, material_type="MAKESKIN")
		for o in set(sc.objects) - before:
			o.name = "Parte_" + sub
	for hid in HAIRS:
		path = AssetService.find_asset_absolute_path("%s/%s.mhclo" % (hid, hid), asset_subdir="hair")
		if path is None:
			print("falta el peinado", hid)
			continue
		before = set(sc.objects)
		HumanService.add_mhclo_asset(path, bm, asset_type="hair", subdiv_levels=0, material_type="MAKESKIN")
		for o in set(sc.objects) - before:
			o.name = HAIR_PREFIX + hid
	print("humano creado:", [(o.name, len(o.data.polygons)) for o in sc.objects if o.type == "MESH"])
	return bm, rig


# ───────────────────────────── conformar al esqueleto de Riva ─────────────────────────────
def _riva_rest_points(riva):
	aw = riva.matrix_world
	return {b.name: (aw @ b.head_local, aw @ b.tail_local) for b in riva.data.bones}


def _bone_order(rig):
	out = []
	def walk(b):
		out.append(b.name)
		for c in b.children:
			walk(c)
	for b in rig.data.bones:
		if b.parent is None:
			walk(b)
	return out


def _pose_to_riva_dirs(rig, rp):
	"""Gira cada hueso del humano (de la raíz a las puntas) para que apunte como el de Riva en reposo.
	Sin estirar: el humano conserva sus proporciones."""
	inv3 = rig.matrix_world.inverted().to_3x3()
	for pb in rig.pose.bones:
		pb.matrix_basis = Matrix.Identity(4)
		for c in list(pb.constraints):
			pb.constraints.remove(c)
	bpy.context.view_layer.update()
	for name in _bone_order(rig):
		if name not in rp:
			continue
		pb = rig.pose.bones[name]
		if _bare(name) in KEEP_NATURAL:
			rest = pb.bone.matrix_local.copy()
			rest.translation = pb.matrix.translation
			pb.matrix = rest
			bpy.context.view_layer.update()
			continue
		want = (inv3 @ (rp[name][1] - rp[name][0])).normalized()
		m = pb.matrix.copy()
		cur = m.col[1].to_3d().normalized()
		q = cur.rotation_difference(want)
		h = m.translation.copy()
		pb.matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ m
		bpy.context.view_layer.update()


def conform():
	"""Escala el humano para que su cadera quede a la altura de la de Riva y lo posa en la pose de reposo de
	Riva (girando huesos, sin estirarlos). Devuelve las articulaciones posadas (mundo) por hueso."""
	sc, rs = scenes()
	riva, _rm = riva_objs()
	bm, rig, parts = human_objs()
	riva.data.pose_position = "REST"
	rig.data.pose_position = "POSE"
	rp = _riva_rest_points(riva)
	riva_h = rp[P + "Hips"][0].z - min(rp[P + "LeftToeBase"][0].z, rp[P + "RightToeBase"][0].z)
	for it in range(3):
		_pose_to_riva_dirs(rig, rp)
		ph = {pb.name: rig.matrix_world @ pb.head for pb in rig.pose.bones}
		h = ph[P + "Hips"].z - min(ph[P + "LeftToeBase"].z, ph[P + "RightToeBase"].z)
		k = riva_h / h
		rig.scale = rig.scale * k
		bpy.context.view_layer.update()
		ph_hips = rig.matrix_world @ rig.pose.bones[P + "Hips"].head
		rig.location += rp[P + "Hips"][0] - ph_hips
		bpy.context.view_layer.update()
		if abs(k - 1.0) < 1e-4:
			break
	_pose_to_riva_dirs(rig, rp)
	joints = {pb.name: (rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail) for pb in rig.pose.bones}
	print("conform: escala rig %.6f, cadera Riva %.6f" % (rig.scale.x, riva_h))
	return joints


def retarget_riva_skeleton(joints):
	"""Mueve las articulaciones de RivaBaseArmature a las del humano posado, conservando la orientación
	(dirección + roll) de cada hueso: las pistas de giro de los clips de Riva siguen siendo válidas."""
	riva, rmesh = riva_objs()
	inv = riva.matrix_world.inverted()
	view_layer = bpy.context.view_layer
	for ob in view_layer.objects:
		ob.select_set(False)
	riva.hide_set(False)
	riva.select_set(True)
	view_layer.objects.active = riva
	bpy.ops.object.mode_set(mode="EDIT")
	ebs = riva.data.edit_bones
	old = {eb.name: (eb.head.copy(), eb.tail.copy(), eb.roll) for eb in ebs}
	ratio = []
	for name in _bone_order(riva):
		eb = ebs[name]
		h0, t0, roll = old[name]
		d = (t0 - h0).normalized()
		if name in joints:
			jh, jt = joints[name]
			nh = inv @ jh
			L = (inv @ jt - nh).length
			ratio.append(L / max((t0 - h0).length, 1e-9))
		else:
			# huesos solo de Riva (puntas de dedos, HeadTop_End, Toe_End): siguen a su padre
			par = eb.parent
			ph0, pt0, _r = old[par.name]
			nh = par.tail.copy() if eb.use_connect else par.head + (h0 - ph0) * (par.length / max((pt0 - ph0).length, 1e-9))
			L = (t0 - h0).length * (par.length / max((pt0 - ph0).length, 1e-9))
		if eb.use_connect and eb.parent is not None:
			eb.use_connect = False
		eb.head = nh
		eb.tail = nh + d * L
		eb.roll = roll
	bpy.ops.object.mode_set(mode="OBJECT")
	print("esqueleto Riva reajustado; longitud media nuevo/viejo %.3f" % (sum(ratio) / len(ratio)))


def bake_pose():
	"""Aplica la pose del rig a las mallas (con sus shape keys ya horneadas). Del humano base se rescatan los
	ojos auxiliares (Parte_eyes) antes de quitar la geometría de ayuda con la máscara."""
	from bl_ext.user_default.mpfb.services.targetservice import TargetService
	bm, rig, parts = human_objs()
	for ob in [bm] + [p for p in parts if p != bm]:
		if ob.data.shape_keys:
			if ob == bm:
				TargetService.bake_targets(ob)
			else:
				ob.shape_key_clear()
		_set_active(ob)
		for m in list(ob.modifiers):
			if m.type == "ARMATURE":
				bpy.ops.object.modifier_apply(modifier=m.name)
			elif m.type == "SUBSURF":
				ob.modifiers.remove(m)
		if ob == bm:
			extract_eyes(bm)
			_set_active(bm)
		for m in list(ob.modifiers):
			if m.type == "MASK":
				bpy.ops.object.modifier_apply(modifier=m.name)
	print("pose horneada")


def extract_eyes(bm):
	"""Copia las esferas auxiliares de los ojos a un objeto Parte_eyes (hijo del rig), con UV propia en
	proyección frontal (iris en el centro) y todo el peso en la cabeza."""
	me = bm.data
	gi = {g.name: g.index for g in bm.vertex_groups}
	sides = {"L": gi["helper-l-eye"], "R": gi["helper-r-eye"]}
	eye_v = {}
	for v in me.vertices:
		for g in v.groups:
			for side, idx in sides.items():
				if g.group == idx and g.weight > 0.5:
					eye_v[v.index] = side
	ob = bm.copy()
	ob.data = me.copy()
	ob.name = "Parte_eyes"
	for c in bm.users_collection:
		c.objects.link(ob)
	for m in list(ob.modifiers):
		ob.modifiers.remove(m)
	b = bmesh.new(); b.from_mesh(ob.data)
	bmesh.ops.delete(b, geom=[v for v in b.verts if v.index not in eye_v], context="VERTS")
	b.to_mesh(ob.data); b.free()
	me2 = ob.data
	# centro de cada ojo y UV frontal (el frente es -Y)
	cen = {}
	for side in ("L", "R"):
		pts = [v.co for v in me2.vertices if (v.co.x > 0) == (side == "L")]
		cen[side] = sum(pts, Vector()) / max(len(pts), 1)
	uv = me2.uv_layers.active.data
	for poly in me2.polygons:
		for li in poly.loop_indices:
			co = me2.vertices[me2.loops[li].vertex_index].co
			c = cen["L" if co.x > 0 else "R"]
			d = (co - c).normalized()
			uv[li].uv = (0.5 + 0.5 * d.x, 0.5 + 0.5 * d.z) if d.y < 0 else (0.5 + 0.5 * math.copysign(1, d.x), 0.5)
	head = ob.vertex_groups.get(P + "Head") or ob.vertex_groups.new(name=P + "Head")
	for g in list(ob.vertex_groups):
		if g != head:
			ob.vertex_groups.remove(g)
	head.add([v.index for v in me2.vertices], 1.0, "REPLACE")
	me2.materials.clear()
	me2.materials.append(_rb_material("rb_Ojos"))
	print("ojos:", len(me2.vertices), "vértices")
	return ob


def transplant_hair(old, old_rp, riva, body):
	"""Pelo de Riva (caras rb_Cabello del RivaBase anterior) ajustado al cráneo nuevo: misma caja que la
	cabeza nueva en ancho/fondo, apoyado en la coronilla. Objeto Pelo_riva, todo el peso en la cabeza."""
	ob = old.copy()
	ob.data = old.data.copy()
	ob.name = HAIR_PREFIX + "riva"
	for c in old.users_collection:
		c.objects.link(ob)
	mats = [m.name for m in ob.data.materials]
	hi = mats.index("rb_Cabello")
	b = bmesh.new(); b.from_mesh(ob.data)
	bmesh.ops.delete(b, geom=[f for f in b.faces if f.material_index != hi], context="FACES")
	bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
	b.to_mesh(ob.data); b.free()
	me = ob.data
	if me.uv_layers.get("Atlas"):
		me.uv_layers.remove(me.uv_layers["Atlas"])
	mw = ob.matrix_world
	# cráneo viejo (Riva): medido en la sesión anterior, mundo*1000
	old_box = (Vector((-0.88, -0.55, 15.21)), Vector((0.88, 1.46, 17.40)))
	# cráneo nuevo: vértices del cuerpo dominados por la cabeza, por encima de la boca
	names = [g.name for g in body.vertex_groups]
	bw = body.matrix_world
	pts = []
	for v in body.data.vertices:
		if v.groups and names[max(v.groups, key=lambda g: g.weight).group] == P + "Head":
			pts.append(bw @ v.co * 1000)
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi_ = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	k = 0.5 * ((hi_.x - lo.x) / (old_box[1].x - old_box[0].x) + (hi_.y - lo.y) / (old_box[1].y - old_box[0].y))
	k *= 1.04                                  # un poco de holgura: el pelo no debe atravesar el cráneo
	oc = Vector((0.0, (old_box[0].y + old_box[1].y) / 2, old_box[1].z))
	nc = Vector(((lo.x + hi_.x) / 2, (lo.y + hi_.y) / 2, hi_.z))
	inv = mw.inverted()
	for v in me.vertices:
		p = mw @ v.co * 1000
		q = nc + (p - oc) * k
		v.co = inv @ (q / 1000)
	for g in list(ob.vertex_groups):
		ob.vertex_groups.remove(g)
	head = ob.vertex_groups.new(name=P + "Head")
	head.add([v.index for v in me.vertices], 1.0, "REPLACE")
	me.materials.clear()
	me.materials.append(_rb_material("rb_Pelo_riva"))
	print("pelo trasplantado: escala %.3f, caja nueva" % k, lo, hi_)
	return ob


# ───────────────────────────── montaje final ─────────────────────────────
BODY = "RivaBase"
HAIR_PREFIX = "Pelo_"
# Ropa interior: slip. Alturas relativas a la cadera de Riva (mundo), ver _underwear_pred.
UW_OFFSET = 0.000012          # separación de la tela sobre la piel (mundo; el personaje mide ~0.019)


def _head_box(body):
	names = [g.name for g in body.vertex_groups]
	mats = [m.name for m in body.data.materials]
	bw = body.matrix_world
	pts = [bw @ v.co for v in body.data.vertices
		if v.groups and names[max(v.groups, key=lambda g: g.weight).group] == P + "Head"]
	lo = Vector([min(p[i] for p in pts) for i in range(3)])
	hi = Vector([max(p[i] for p in pts) for i in range(3)])
	return lo, hi


def refit_hair(old_body, new_body):
	"""Reajusta los peinados Pelo_* (hechos para la cabeza de old_body) a la cabeza de new_body."""
	bpy.context.view_layer.update()
	(lo0, hi0), (lo1, hi1) = _head_box(old_body), _head_box(new_body)
	k = 0.5 * ((hi1.x - lo1.x) / (hi0.x - lo0.x) + (hi1.y - lo1.y) / (hi0.y - lo0.y))
	c0 = Vector(((lo0.x + hi0.x) / 2, (lo0.y + hi0.y) / 2, hi0.z))
	c1 = Vector(((lo1.x + hi1.x) / 2, (lo1.y + hi1.y) / 2, hi1.z))
	for ob in [o for o in bpy.data.scenes[RIVA_SCENE].objects if o.name.startswith(HAIR_PREFIX)]:
		mw = ob.matrix_world
		inv = mw.inverted()
		for v in ob.data.vertices:
			v.co = inv @ (c1 + (mw @ v.co - c0) * k)
		ob.data.update()
	print("peinados reajustados: escala %.3f" % k)


def _set_active(ob):
	view_layer = bpy.context.view_layer
	for o in view_layer.objects:
		o.select_set(False)
	ob.hide_set(False)
	ob.select_set(True)
	view_layer.objects.active = ob


def _underwear_pred(riva):
	"""Devuelve f(p_mundo) -> 0 fuera, 1 tela, 2 elástico, para un slip a la altura de la cadera de Riva."""
	aw = riva.matrix_world
	hips = aw @ riva.data.bones[P + "Hips"].head_local
	lup = aw @ riva.data.bones[P + "LeftUpLeg"].head_local
	spine = aw @ riva.data.bones[P + "Spine"].head_local
	z_top = hips.z + 0.45 * (spine.z - hips.z) + 0.00012
	band = 0.00016
	z_crotch = lup.z - 0.00095
	slope = 0.75
	cx = hips.x
	def f(p):
		ax = abs(p.x - cx)
		z_low = z_crotch + slope * max(0.0, ax - 0.00028)
		if not (z_low < p.z < z_top):
			return 0
		return 2 if p.z > z_top - band else 1
	return f


def make_underwear(body, riva):
	"""Slip como capa aparte: copia las caras del cuerpo en la zona, las separa un poco por la normal y les da
	los materiales rb_Calzones / rb_Elastico. Las caras de piel tapadas se borran (sin parpadeo)."""
	pred = _underwear_pred(riva)
	mw = body.matrix_world
	inv3 = mw.inverted().to_3x3()
	me = body.data
	mats = [m.name for m in me.materials]
	for n in ("rb_Calzones", "rb_Elastico"):
		if n not in mats:
			me.materials.append(_rb_material(n))
	mats = [m.name for m in me.materials]
	i_cloth, i_band = mats.index("rb_Calzones"), mats.index("rb_Elastico")
	bm = bmesh.new(); bm.from_mesh(me)
	bm.faces.ensure_lookup_table()
	zone = {}
	for f in bm.faces:
		z = pred(mw @ f.calc_center_median())
		if z:
			zone[f] = z
	# copia
	geom = bmesh.ops.duplicate(bm, geom=list(zone.keys()))
	fmap = geom["face_map"]
	new_faces = [fmap[f] for f in zone]
	new_verts = {v for f in new_faces for v in f.verts}
	bm.normal_update()
	off_local = UW_OFFSET / mw.to_scale().x
	for v in new_verts:
		v.co += v.normal * off_local
	for f in zone:
		fmap[f].material_index = i_band if zone[f] == 2 else i_cloth
	# piel tapada: solo las caras cuyos vecinos también están dentro (borde con solape)
	inner = [f for f in zone if all(zone.get(lf, 0) for e in f.edges for lf in e.link_faces)]
	bmesh.ops.delete(bm, geom=inner, context="FACES")
	bm.to_mesh(me); bm.free()
	me.update()
	print("ropa interior: caras", len(new_faces), "piel borrada", len(inner))


def _rb_material(name, color=(0.8, 0.8, 0.8)):
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	m.use_nodes = True
	return m


PART_MATS = {"Parte_eyes": "rb_Ojos", "Parte_eyebrows": "rb_Cejas", "Parte_eyelashes": "rb_Pestanas"}


def _only_bone_groups(ob, bones):
	for g in list(ob.vertex_groups):
		if g.name not in bones:
			ob.vertex_groups.remove(g)


def finish(joints):
	"""Hornea la pose, reajusta el esqueleto de Riva, pasa las piezas a Riva_Personaje (hijas de la armadura,
	mismo espacio que el RivaBase anterior), une cuerpo + ojos + cejas + pestañas en RivaBase, añade el slip
	y deja cada peinado como malla aparte Pelo_<id>."""
	sc, rs = scenes()
	riva, old = riva_objs()
	bm, rig, parts = human_objs()
	src_mats = {}
	for ob in [bm] + parts:
		src_mats[ob.name] = [m.name for m in ob.data.materials if m]
	old_rp = _riva_rest_points(riva)
	bake_pose()
	bm, rig, parts = human_objs()
	retarget_riva_skeleton(joints)
	target_mw = old.matrix_world.copy()
	bones = {b.name for b in riva.data.bones}
	pieces = [bm] + [p for p in parts if p != bm]
	for ob in pieces:
		ob.data.transform(target_mw.inverted() @ ob.matrix_world)
		ob.parent = riva
		ob.matrix_parent_inverse = old.matrix_parent_inverse.copy()
		ob.matrix_basis = old.matrix_basis.copy()
		for m in list(ob.modifiers):
			ob.modifiers.remove(m)
		mod = ob.modifiers.new("Armature", "ARMATURE")
		mod.object = riva
		_only_bone_groups(ob, bones)
		if ob.name not in rs.collection.objects:
			rs.collection.objects.link(ob)
		for c in list(ob.users_collection):
			if c != rs.collection:
				c.objects.unlink(ob)
		# materiales con nombre fijo (el juego los reconoce por nombre)
		name = "rb_Piel" if ob == bm else PART_MATS.get(ob.name, "rb_" + ob.name)
		if not ob.material_slots or ob.material_slots[0].material is None:
			ob.data.materials.clear()
			ob.data.materials.append(_rb_material(name))
		for i, slot in enumerate(ob.material_slots):
			if slot.material:
				m = slot.material
				m.name = name if i == 0 else "%s_%d" % (name, i)
	if "rb_Cabello" in [m.name for m in old.data.materials]:
		transplant_hair(old, old_rp, riva, bm)
	else:
		refit_hair(old, bm)
	# fuera el RivaBase anterior
	old_me = old.data
	bpy.data.objects.remove(old)
	if old_me.users == 0:
		bpy.data.meshes.remove(old_me)
	# cuerpo = humano + ojos + cejas + pestañas
	body_parts = [bm] + [p for p in parts if p.name in PART_MATS]
	bpy.context.window.scene = rs
	_set_active(bm)
	for p in body_parts:
		p.select_set(True)
	bpy.ops.object.join()
	bm.name = BODY
	bm.data.name = BODY + "Mesh"
	_cut_underwear_lines(bm, riva)
	make_underwear(bm, riva)
	for p in bm.data.polygons:
		p.use_smooth = True
	print("listo:", [(o.name, len(o.data.polygons), [m.name for m in o.data.materials]) for o in rs.objects if o.type == "MESH"])
	return bm


# ───────────────────────────── texturas para Godot ─────────────────────────────
TEX_OUT = os.path.join(REPO, "assets", "textures", "entities", "riva", "humano")


def _mhmat(path):
	"""Lee un .mhmat (clave valor por línea) y resuelve las rutas de textura relativas al archivo."""
	out = {}
	base = os.path.dirname(path)
	for line in open(path, encoding="utf-8", errors="ignore"):
		line = line.strip()
		if not line or line.startswith("#") or " " not in line:
			continue
		k, v = line.split(" ", 1)
		v = v.strip()
		if k.lower().endswith("texture"):
			cand = os.path.join(base, v) if not os.path.isabs(v) else v
			if not os.path.exists(cand):
				cand = os.path.join(base, os.path.basename(v))
			v = cand
		out[k] = v
	return out


def _load(path, res=None):
	img = bpy.data.images.load(path, check_existing=False)
	if res and tuple(img.size) != (res, res):
		img.scale(res, res)
	w, h = img.size
	px = np.empty(w * h * 4, np.float32)
	img.pixels.foreach_get(px)
	cs = img.colorspace_settings.name
	bpy.data.images.remove(img)
	return px.reshape(h, w, 4), cs


def _save(arr, name, linear=False):
	"""arr (h, w, 3|4) en [0,1] -> PNG en TEX_OUT."""
	os.makedirs(TEX_OUT, exist_ok=True)
	h, w = arr.shape[:2]
	if arr.shape[2] == 3:
		arr = np.dstack([arr, np.ones((h, w), np.float32)])
	img = bpy.data.images.new("tmp_" + name, w, h, alpha=True, float_buffer=False)
	if linear:
		img.colorspace_settings.name = "Non-Color"
	img.pixels.foreach_set(np.clip(arr, 0, 1).astype(np.float32).ravel())
	img.filepath_raw = os.path.join(TEX_OUT, name)
	img.file_format = "PNG"
	img.save()
	bpy.data.images.remove(img)
	print("textura", name, w, h)


def _normalize_detail(rgb, mask, mean_target=0.8):
	"""Divide por el color medio de la zona útil: queda una textura de detalle (≈ gris 0.8) que el juego
	multiplica por el color elegido conservando variaciones (labios, mejillas, poros, mechones)."""
	m = rgb[mask].mean(axis=0) if mask.any() else np.array([0.5, 0.5, 0.5])
	out = rgb / np.maximum(m, 1e-4) * mean_target
	return np.clip(out, 0, 1)


def _height_to_normal(height, strength=2.0):
	"""Mapa de normales (espacio tangente, convención OpenGL como Godot) a partir de una altura."""
	gy, gx = np.gradient(height)
	nx = -gx * strength
	ny = gy * strength      # las filas de Blender van de abajo a arriba
	nz = np.ones_like(height)
	l = np.sqrt(nx * nx + ny * ny + nz * nz)
	return np.dstack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5])


def _blur(a, r=2):
	out = a.copy()
	for axis in (0, 1):
		acc = np.zeros_like(out)
		for d in range(-r, r + 1):
			acc += np.roll(out, d, axis=axis)
		out = acc / (2 * r + 1)
	return out


# ───────────────────────────── exportar ─────────────────────────────
FBX_OUT = os.path.join(REPO, "assets", "models", "riva", "riva-base.fbx")


def export():
	"""riva-base.fbx: armadura + RivaBase + peinados Pelo_* con el clip idle (desde el primer fotograma: Godot
	toma como reposo la pose del fotograma actual)."""
	rs = bpy.data.scenes[RIVA_SCENE]
	bpy.context.window.scene = rs
	riva = rs.objects[RIVA_ARM]
	riva.data.pose_position = "POSE"
	act = riva.animation_data.action
	rs.render.fps = 30
	rs.frame_start, rs.frame_end = int(act.frame_range[0]), int(act.frame_range[1])
	rs.frame_set(rs.frame_start)
	view_layer = bpy.context.view_layer
	for o in view_layer.objects:
		o.select_set(False)
	sel = [riva] + [o for o in rs.objects if o.type == "MESH" and (o.name == BODY or o.name.startswith(HAIR_PREFIX))]
	for o in sel:
		o.hide_set(False)
		o.select_set(True)
	view_layer.objects.active = riva
	bpy.ops.export_scene.fbx(filepath=FBX_OUT, use_selection=True, object_types={"ARMATURE", "MESH"},
		add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
		path_mode="STRIP", use_mesh_modifiers=False)
	print("exportado", FBX_OUT, [o.name for o in sel])


MPFB_TEX = os.path.join(os.environ.get("APPDATA", ""), "Blender Foundation", "Blender", "5.2", "extensions",
	"user_default", "mpfb", "data", "textures")
# Máscaras de MPFB (UV del humano base) -> multiplicador RGB del detalle de piel
SKIN_ZONES = {
	"mpfb_lips.jpg": (0.98, 0.66, 0.64), "mpfb_eyelids.jpg": (0.86, 0.74, 0.72),
	"mpfb_ears.jpg": (1.0, 0.86, 0.82), "mpfb_aureolae.jpg": (0.82, 0.62, 0.58),
	"mpfb_fingernails.jpg": (1.08, 0.97, 0.95), "mpfb_toenails.jpg": (1.08, 0.97, 0.95),
	"mpfb_crotch.jpg": (0.92, 0.84, 0.80),
}
SKIN_RES = 2048


def _bake(body, kind, res, img_name, emit_attr=None, samples=48):
	"""Hornea AO o la emisión de un atributo de color (Cycles CPU) en la UV del cuerpo. Devuelve (h, w, 4)."""
	rs = bpy.data.scenes[RIVA_SCENE]
	img = bpy.data.images.get(img_name) or bpy.data.images.new(img_name, res, res, alpha=False, float_buffer=True)
	if tuple(img.size) != (res, res):
		img.scale(res, res)
	dummy = bpy.data.images.get("bake_dummy") or bpy.data.images.new("bake_dummy", 8, 8)
	added = []
	for m in body.data.materials:
		m.use_nodes = True
		nt = m.node_tree
		t = nt.nodes.new("ShaderNodeTexImage"); t.image = img if m.name == "rb_Piel" else dummy
		added.append((nt, [t]))
		nt.nodes.active = t
		if emit_attr and m.name == "rb_Piel":
			out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
			old_link = [l.from_socket for l in out.inputs["Surface"].links]
			a = nt.nodes.new("ShaderNodeVertexColor"); a.layer_name = emit_attr
			e = nt.nodes.new("ShaderNodeEmission")
			nt.links.new(a.outputs[0], e.inputs[0]); nt.links.new(e.outputs[0], out.inputs["Surface"])
			added[-1][1].extend([a, e])
			added[-1] = (nt, added[-1][1], out, old_link)
	prev = rs.render.engine
	try:
		rs.render.engine = "CYCLES"
	except TypeError as ex:
		print(ex)
	rs.cycles.device = "CPU"
	rs.cycles.samples = samples
	rs.world = rs.world or bpy.data.worlds.new("bake_world")
	rs.world.light_settings.distance = 0.0006
	riva = rs.objects[RIVA_ARM]
	riva.data.pose_position = "REST"
	bpy.context.window.scene = rs
	_set_active(body)
	try:
		bpy.ops.object.bake(type=kind, margin=8, use_clear=True)
	finally:
		rs.render.engine = prev
		for entry in added:
			nt, nodes = entry[0], entry[1]
			if len(entry) > 2:
				out, old_link = entry[2], entry[3]
				for l in list(out.inputs["Surface"].links):
					nt.links.remove(l)
				for s in old_link:
					nt.links.new(s, out.inputs["Surface"])
			for n in nodes:
				nt.nodes.remove(n)
	px = np.empty(res * res * 4, np.float32)
	img.pixels.foreach_get(px)
	return px.reshape(res, res, 4)


def _brow_attr(body):
	"""Color por vértice 'rb_brow' (blanco = ceja) sobre los ojos: arco de dentro (nariz) a fuera."""
	me = body.data
	mw = body.matrix_world
	mats = [m.name for m in me.materials]
	ie = mats.index("rb_Ojos")
	eye_vs = {i for p in me.polygons if p.material_index == ie for i in p.vertices}
	out = {}
	for side in (1, -1):
		pts = [mw @ me.vertices[i].co for i in eye_vs if (mw @ me.vertices[i].co).x * side > 0]
		c = sum(pts, Vector()) / len(pts)
		r = max((p - c).length for p in pts)
		out[side] = (c, r)
	attr = me.color_attributes.get("rb_brow") or me.color_attributes.new("rb_brow", "FLOAT_COLOR", "POINT")
	for v in me.vertices:
		p = mw @ v.co
		side = 1 if p.x > 0 else -1
		c, r = out[side]
		u = (p.x - c.x) * side / r            # -1 hacia la nariz, +1 hacia fuera
		if v.index in eye_vs or p.y > c.y + 0.4 * r or not (-1.15 < u < 1.45):
			w = 0.0
		else:
			arch = 1.55 + 0.25 * (1.0 - ((u - 0.15) / 1.3) ** 2)          # altura del arco (en radios)
			thick = 0.36 * (1.0 - 0.55 * max(0.0, u) / 1.45)                # se afina hacia fuera
			dz = (p.z - c.z) / r - arch
			w = max(0.0, 1.0 - (dz / thick) ** 2)
			w *= min(1.0, (u + 1.15) / 0.35) * min(1.0, (1.45 - u) / 0.3)
		attr.data[v.index].color = (w, w, w, 1.0)
	return attr.name


def _eye_texture(res=512):
	"""Ojo procedural en la UV frontal de extract_eyes: esclerótica, iris en gris (alfa = máscara del iris,
	se tiñe en el juego), anillo límbico, pupila y brillo de la córnea."""
	y, x = np.mgrid[0:res, 0:res].astype(np.float32)
	u = (x + 0.5) / res - 0.5
	v = (y + 0.5) / res - 0.5
	r = np.sqrt(u * u + v * v)
	ang = np.arctan2(v, u)
	R_IRIS, R_PUP = 0.205, 0.075
	sclera = np.dstack([np.full_like(r, 0.93), np.full_like(r, 0.90), np.full_like(r, 0.88)])
	sclera *= (1.0 - 0.25 * np.clip((r - 0.30) / 0.2, 0, 1))[..., None]          # se oscurece hacia los lados
	streak = 0.5 + 0.5 * np.sin(ang * 37.0) * np.sin(ang * 13.0 + r * 40.0)
	t = np.clip((r - R_PUP) / (R_IRIS - R_PUP), 0, 1)
	iris_l = 0.55 + 0.30 * (1.0 - t) * (0.7 + 0.3 * streak) - 0.35 * np.clip((t - 0.82) / 0.18, 0, 1)
	iris = np.dstack([iris_l] * 3)
	in_iris = np.clip((R_IRIS - r) / 0.012, 0, 1)
	pupil = np.clip((R_PUP - r) / 0.01, 0, 1)
	rgb = sclera * (1 - in_iris[..., None]) + iris * in_iris[..., None]
	rgb = rgb * (1 - pupil[..., None]) + 0.02 * pupil[..., None]
	hl = np.clip(1.0 - np.sqrt((u + 0.07) ** 2 + (v - 0.08) ** 2) / 0.035, 0, 1) ** 2
	rgb = rgb + hl[..., None] * 0.9
	alpha = in_iris * (1 - pupil) * (1 - hl)
	return np.dstack([np.clip(rgb, 0, 1), alpha])


def bake_textures():
	"""Texturas del personaje en assets/textures/entities/riva/humano/ (ver CharacterLookApplier.SURFACES)."""
	rs = bpy.data.scenes[RIVA_SCENE]
	body = rs.objects[BODY]
	res = SKIN_RES
	# detalle de piel: gris 0.8 con las zonas de MPFB teñidas
	detail = np.full((res, res, 3), 0.8, np.float32)
	for f, mul in SKIN_ZONES.items():
		path = os.path.join(MPFB_TEX, f)
		if not os.path.exists(path):
			continue
		m, _cs = _load(path, res)
		w = _blur(m[:, :, 0], 3)[..., None]
		detail = detail * (1.0 - w) + detail * np.array(mul, np.float32) * w
	# AO (también da volumen a la textura: pliegues, axilas, entre dedos)
	ao = _bake(body, "AO", 1024, "rb_bake_ao")[:, :, 0]
	_save(np.dstack([ao, ao, ao]), "piel_ao.png", linear=True)
	# cejas: máscara aparte (el juego las tiñe del color del pelo)
	attr = _brow_attr(body)
	brow = _bake(body, "EMIT", 1024, "rb_bake_brow", emit_attr=attr)[:, :, 0]
	rng = np.random.default_rng(7)
	hairs = rng.random(brow.shape).astype(np.float32)
	brow = np.clip(brow * 1.6, 0, 1) * (0.55 + 0.45 * _blur(hairs, 1))
	_save(np.dstack([brow, brow, brow]), "piel_mask.png", linear=True)
	_save(detail, "piel.png")
	_save(_eye_texture(), "ojos.png")
	# pelo de Riva: mechones en gris de la textura de detalle anterior
	src = os.path.join(REPO, "assets", "textures", "entities", "riva", "riva_base_detail.png")
	hp, _cs = _load(src)
	_save(np.dstack([hp[:, :, :3], np.ones(hp.shape[:2], np.float32)]), "pelo_riva.png")
	print("texturas listas en", TEX_OUT)


def _cut_underwear_lines(body, riva):
	"""Corta la piel con planos por los bordes del slip (cintura, elástico, perneras) para que la selección
	por caras siga líneas rectas y no escalones."""
	aw = riva.matrix_world
	hips = aw @ riva.data.bones[P + "Hips"].head_local
	lup = aw @ riva.data.bones[P + "LeftUpLeg"].head_local
	spine = aw @ riva.data.bones[P + "Spine"].head_local
	z_top = hips.z + 0.45 * (spine.z - hips.z) + 0.00012
	z_crotch = lup.z - 0.00095
	cx, slope, w0 = hips.x, 0.75, 0.00028
	mw = body.matrix_world
	inv = mw.inverted()
	n3 = inv.to_3x3()
	bm = bmesh.new(); bm.from_mesh(body.data)
	mats = [m.name for m in body.data.materials]
	skin = mats.index("rb_Piel")
	def near(c):
		return abs(c.z - hips.z) < 0.0028 and abs(c.x - cx) < 0.0030
	def cut(co, no, extra=lambda c: True):
		bm.faces.ensure_lookup_table()
		fs = [f for f in bm.faces if f.material_index == skin and near(mw @ f.calc_center_median()) and extra(mw @ f.calc_center_median())]
		geom = list({v for f in fs for v in f.verts}) + list({e for f in fs for e in f.edges}) + fs
		bmesh.ops.bisect_plane(bm, geom=geom, plane_co=inv @ Vector(co), plane_no=(n3 @ Vector(no)).normalized())
	cut((cx, 0, z_top), (0, 0, 1))
	cut((cx, 0, z_top - 0.00016), (0, 0, 1))
	cut((cx, 0, z_crotch), (0, 0, 1), lambda c: abs(c.x - cx) < w0 + 0.0002)
	for s in (1, -1):
		cut((cx + s * w0, 0, z_crotch), (-s * slope, 0, 1), lambda c, s=s: (c.x - cx) * s > w0 - 0.0002)
	bm.to_mesh(body.data); bm.free()
	body.data.update()


def redo_underwear():
	"""Rehace el slip de RivaBase con bordes rectos: devuelve la piel tapada (copia hacia dentro de la tela),
	la suelda, borra la tela vieja, corta la piel con planos y vuelve a crear la tela."""
	rs = bpy.data.scenes[RIVA_SCENE]
	body, riva = rs.objects[BODY], rs.objects[RIVA_ARM]
	me = body.data
	mats = [m.name for m in me.materials]
	cloth = {mats.index(n) for n in ("rb_Calzones", "rb_Elastico") if n in mats}
	skin = mats.index("rb_Piel")
	off = UW_OFFSET / body.matrix_world.to_scale().x
	bm = bmesh.new(); bm.from_mesh(me)
	shell = [f for f in bm.faces if f.material_index in cloth]
	edge_cnt = {}
	for f in shell:
		for e in f.edges:
			edge_cnt[e] = edge_cnt.get(e, 0) + 1
	# caras de tela interiores (sin aristas de borde) = piel que se borró debajo
	inner = [f for f in shell if all(edge_cnt[e] == 2 for e in f.edges)]
	dup = bmesh.ops.duplicate(bm, geom=inner)
	new_f = [dup["face_map"][f] for f in inner]
	new_v = list({v for f in new_f for v in f.verts})
	bm.normal_update()
	for v in new_v:
		v.co -= v.normal * off
	for f in new_f:
		f.material_index = skin
	bmesh.ops.delete(bm, geom=shell, context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	lo = Vector([min(v.co[i] for v in new_v) - 3 * off for i in range(3)])
	hi = Vector([max(v.co[i] for v in new_v) + 3 * off for i in range(3)])
	region = [v for v in bm.verts if all(lo[i] < v.co[i] < hi[i] for i in range(3))]
	bmesh.ops.remove_doubles(bm, verts=region, dist=off * 0.5)
	bm.to_mesh(me); bm.free()
	me.update()
	_cut_underwear_lines(body, riva)
	make_underwear(body, riva)


def fit_hair_from_backup(backup=os.path.join(REPO, "blender_sources", "backup", "rumbang_anims_pre_human.blend")):
	"""Rehace Pelo_riva desde el pelo original de Riva (RivaBase del backup) trabajando en el espacio LOCAL de
	la malla (Y arriba, +Z delante; transplant_hair usaba el del mundo y lo dejaba girado 90°). Escala uniforme
	por el ancho del cráneo, alineado por la coronilla y la nuca, y empuja fuera lo que atraviesa la piel."""
	from mathutils.bvhtree import BVHTree
	rs = bpy.data.scenes[RIVA_SCENE]
	cur = rs.objects[BODY]
	with bpy.data.libraries.load(backup, link=False) as (src, dst):
		dst.objects = [BODY]
	old = dst.objects[0]
	def head_mask(ob):
		names = [g.name for g in ob.vertex_groups]
		return [bool(v.groups) and names[max(v.groups, key=lambda g: g.weight).group] in (P + "Head", P + "HeadTop_End")
			for v in ob.data.vertices]
	om = [m.name for m in old.data.materials]
	hi = next(i for i, n in enumerate(om) if n.startswith("rb_Cabello"))
	oh, ch = head_mask(old), head_mask(cur)
	so = np.array([old.data.vertices[i].co[:] for p in old.data.polygons if p.material_index != hi for i in p.vertices if oh[i]])
	skin = [m.name for m in cur.data.materials].index("rb_Piel")
	sn = np.array([cur.data.vertices[i].co[:] for p in cur.data.polygons if p.material_index == skin for i in p.vertices if ch[i]])
	lo0, hi0, lo1, hi1 = so.min(0), so.max(0), sn.min(0), sn.max(0)
	k = (hi1[0] - lo1[0]) / (hi0[0] - lo0[0])
	c0 = Vector(((lo0[0] + hi0[0]) / 2, hi0[1], lo0[2]))
	c1 = Vector(((lo1[0] + hi1[0]) / 2, hi1[1], lo1[2]))
	me = old.data.copy(); me.name = HAIR_PREFIX + "riva_mesh"
	bm = bmesh.new(); bm.from_mesh(me)
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != hi], context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	for v in bm.verts:
		v.co = c1 + (v.co - c0) * k
	cb = bmesh.new(); cb.from_mesh(cur.data)
	bmesh.ops.delete(cb, geom=[f for f in cb.faces if f.material_index != skin or f.calc_center_median().y < lo1[1]], context="FACES")
	tree = BVHTree.FromBMesh(cb)
	gap = 0.003
	for v in bm.verts:
		loc, nor, _i, _d = tree.find_nearest(v.co)
		if loc is not None and (v.co - loc).dot(nor) < gap:
			v.co += nor * (gap - (v.co - loc).dot(nor))
	cb.free()
	bm.to_mesh(me); bm.free()
	me.materials.clear(); me.materials.append(_rb_material("rb_Pelo_riva"))
	for p in me.polygons:
		p.use_smooth = True
	prev = rs.objects.get(HAIR_PREFIX + "riva")
	if prev:
		bpy.data.objects.remove(prev)
	ob = bpy.data.objects.new(HAIR_PREFIX + "riva", me)
	rs.collection.objects.link(ob)
	ob.parent = cur.parent
	ob.matrix_parent_inverse = cur.matrix_parent_inverse.copy()
	ob.matrix_basis = cur.matrix_basis.copy()
	ob.vertex_groups.new(name=P + "Head").add([v.index for v in me.vertices], 1.0, "REPLACE")
	ob.modifiers.new("Armature", "ARMATURE").object = cur.parent
	arm2 = old.parent
	bpy.data.objects.remove(old)
	if arm2 is not None and not arm2.users_collection:
		bpy.data.objects.remove(arm2)
	print("pelo ajustado: escala %.3f" % k)
	return ob
