"""Cuerpo base del personaje personalizable a partir de Riva (escena Riva_Personaje de rumbang_anims.blend).

Riva es una sola malla vestida (chándal, capucha, máscara, guantes, zapatillas). Este script la convierte en
un cuerpo base EN CALZONES, editable por partes:
  1. Ajusta la malla al cuerpo: la ropa holgada se encoge hacia el eje de cada hueso (brazos, piernas,
     torso) y la capucha se pega al cuello; después un suavizado laplaciano quita los pliegues.
  2. Separa la malla en materiales por zona (los recolorea el juego): piel, cara, cabello, calzones, uñas...
  3. Hornea una textura de detalle en gris (cara y cabello) para que el color elegido conserve ojos y mechones.

Se ejecuta desde el MCP (Blender abierto con rumbang_anims.blend):
  ns = {"__name__": "riva_base", "__file__": r"<repo>/tools/blender_riva_base.py"}
  exec(open(ns["__file__"], encoding="utf-8").read(), ns); ns["build"]()
"""
import bpy, bmesh, collections, colorsys, math, os
import numpy as np
from mathutils import Vector
from mathutils.geometry import intersect_point_line

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_FBX = os.path.join(REPO, "assets", "models", "riva", "riva-idle.fbx")
SRC_TEX = os.path.join(REPO, "assets", "textures", "entities", "riva", "texture_riva.png")
SCENE = "Riva_Personaje"
MESH = "RivaBase"
ARM = "RivaBaseArmature"
ORIG = "RivaBaseMesh_orig"   # copia intacta de la malla original (para poder re-ejecutar)

P = "mixamorig:"

# Cuánto se acerca cada zona al eje del hueso (1 = sin cambio). [radial]
SHRINK = {
	"Arm": 0.72, "ForeArm": 0.74, "UpLeg": 0.86, "Leg": 0.80,
}
TORSO_BONES = {"Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder"}


def bname(b):
	return b.split(":", 1)[1] if ":" in b else b


def side_less(n):
	return n.replace("Left", "").replace("Right", "")


def scene_objs():
	sc = bpy.data.scenes[SCENE]
	return sc, bpy.data.objects[MESH], bpy.data.objects[ARM]


def reset_mesh(mesh):
	"""Vuelve a la malla original (guardada la primera vez) para poder re-ejecutar el script."""
	orig = bpy.data.meshes.get(ORIG)
	if orig is None:
		orig = mesh.data.copy()
		orig.name = ORIG
		orig.use_fake_user = True
	old = mesh.data
	mesh.data = orig.copy()
	mesh.data.name = "RivaBaseMesh"
	if old.users == 0:
		bpy.data.meshes.remove(old)
	if mesh.data.has_custom_normals:
		with bpy.context.temp_override(object=mesh, active_object=mesh, selected_objects=[mesh]):
			bpy.ops.mesh.customdata_custom_splitnormals_clear()
	for p in mesh.data.polygons:
		p.use_smooth = True


def dominant_bones(mesh):
	names = [g.name for g in mesh.vertex_groups]
	out = []
	for v in mesh.data.vertices:
		best = max(v.groups, key=lambda g: g.weight) if v.groups else None
		out.append(bname(names[best.group]) if best else "")
	return out


def bone_seg(arm, name):
	b = arm.data.bones[P + name]
	m = arm.matrix_world
	return m @ b.head_local, m @ b.tail_local


def fit_to_body(mesh, arm):
	mw = mesh.matrix_world
	inv = mw.inverted()
	dom = dominant_bones(mesh)
	verts = mesh.data.vertices
	segs = {}
	spine = [bone_seg(arm, n) for n in ("Hips", "Spine", "Spine1", "Spine2", "Neck")]
	head_z = bone_seg(arm, "Head")[0].z
	neck_z = bone_seg(arm, "Neck")[0].z
	sh_z = bone_seg(arm, "LeftArm")[0].z
	hips_z = bone_seg(arm, "Hips")[0].z
	for i, v in enumerate(verts):
		b = dom[i]
		key = side_less(b)
		p = mw @ v.co
		if key in SHRINK:
			if b not in segs:
				segs[b] = bone_seg(arm, b)
			a, t = segs[b]
			q, f = intersect_point_line(p, a, t)
			f = min(max(f, 0.0), 1.0)
			q = a.lerp(t, f)
			p = q + (p - q) * SHRINK[key]
		elif b in TORSO_BONES:
			# Eje de la columna a la altura del vértice
			z = min(max(p.z, spine[0][0].z), spine[-1][1].z)
			axis = spine[0][0]
			for a, t in spine:
				if a.z <= z <= t.z + 1e-9:
					f = (z - a.z) / max(t.z - a.z, 1e-9)
					axis = a.lerp(t, f)
					break
			d = p - Vector((axis.x, axis.y, p.z))
			kx, ky = 0.88, 0.78
			if p.z > sh_z - 0.0002:                  # capucha / cuello alto: se pega al cuello
				w = min(1.0, (p.z - (sh_z - 0.0002)) / max(neck_z - sh_z + 0.0006, 1e-9))
				kx = kx * (1 - w) + 0.55 * w
				ky = ky * (1 - w) + 0.5 * w
			if p.z < hips_z:                         # bajo de la chaqueta: ceñido a la cadera
				kx, ky = 0.86, 0.8
			p = Vector((axis.x + d.x * kx, axis.y + d.y * ky, p.z))
		v.co = inv @ p
	mesh.data.update()
	return dom


def smooth(mesh, dom, iters=12, factor=0.5, skip=("Head", "HeadTop_End")):
	"""Laplaciano sobre la ropa (no toca cabeza ni manos) para quitar pliegues."""
	bm = bmesh.new()
	bm.from_mesh(mesh.data)
	bm.verts.ensure_lookup_table()
	movable = [i for i, b in enumerate(dom) if side_less(b) not in skip and "Hand" not in b]
	nbrs = {i: [e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges] for i in movable}
	co = [v.co.copy() for v in bm.verts]
	for _ in range(iters):
		new = {}
		for i in movable:
			ns = nbrs[i]
			if not ns:
				continue
			avg = sum((co[j] for j in ns), Vector()) / len(ns)
			new[i] = co[i].lerp(avg, factor)
		for i, c in new.items():
			co[i] = c
	for i in movable:
		bm.verts[i].co = co[i]
	bm.to_mesh(mesh.data)
	bm.free()
	mesh.data.update()


def neck_clamp(mesh, arm, dom):
	"""Capucha: por encima de los hombros, el radio se limita al de un cuello (interpolado hasta la cabeza)."""
	mw = mesh.matrix_world
	inv = mw.inverted()
	n0, n1 = bone_seg(arm, "Neck")
	sh_z = bone_seg(arm, "LeftArm")[0].z
	head_z = bone_seg(arm, "Head")[0].z
	r_neck = 0.00042
	r_sh = 0.0012
	for i, v in enumerate(mesh.data.vertices):
		if dom[i] not in TORSO_BONES:
			continue
		p = mw @ v.co
		if p.z <= sh_z - 0.0004:
			continue
		f = min(1.0, max(0.0, (p.z - (sh_z - 0.0004)) / max(head_z - sh_z + 0.0004, 1e-9)))
		r_max = r_sh + (r_neck - r_sh) * min(1.0, f * 1.6)
		axis = n0.lerp(n1, f)
		d = Vector((p.x - axis.x, p.y - axis.y, 0))
		if d.length > r_max:
			d = d.normalized() * r_max
		p = Vector((axis.x + d.x, axis.y + d.y, min(p.z, head_z + 0.0002)))
		v.co = inv @ p
	mesh.data.update()


def smooth_region(mesh, pred, iters, factor=0.5):
	"""Suavizado laplaciano solo en los vértices que cumplen pred(i, pos_mundo)."""
	mw = mesh.matrix_world
	bm = bmesh.new()
	bm.from_mesh(mesh.data)
	bm.verts.ensure_lookup_table()
	sel = [v.index for v in bm.verts if pred(v.index, mw @ v.co)]
	nbrs = {i: [e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges] for i in sel}
	co = [v.co.copy() for v in bm.verts]
	for _ in range(iters):
		new = {i: co[i].lerp(sum((co[j] for j in nbrs[i]), Vector()) / len(nbrs[i]), factor) for i in sel if nbrs[i]}
		for i, c in new.items():
			co[i] = c
	for i in sel:
		bm.verts[i].co = co[i]
	bm.to_mesh(mesh.data)
	bm.free()
	mesh.data.update()


def flatten_mask(mesh, arm, dom):
	"""Bajo la máscara no hay cara: la mitad delantera de la parte baja de la cabeza se recoloca sobre una
	elipse de cara (mejillas -> barbilla) que se estrecha hacia abajo, con transición suave hacia los ojos."""
	mw = mesh.matrix_world
	inv = mw.inverted()
	h0 = bone_seg(arm, "Head")[0]
	top = bone_seg(arm, "HeadTop_End")[0]
	hh = top.z - h0.z
	cx, cy = h0.x, h0.y - 0.18 * hh          # centro de la cara en planta
	def sst(e0, e1, x):
		t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
		return t * t * (3 - 2 * t)
	for i, v in enumerate(mesh.data.vertices):
		if dom[i] not in ("Head", "Neck"):
			continue
		p = mw @ v.co
		f = (p.z - h0.z) / hh
		if f < -0.05 or f > 0.45 or p.y > cy:
			continue
		k = sst(-0.05, 0.42, f)
		a = 0.00042 + (0.00092 - 0.00042) * k            # semiancho
		bb = 0.00030 + (0.00082 - 0.00030) * k           # profundidad hacia delante
		th = math.atan2(p.y - cy, p.x - cx)
		tgt = Vector((cx + a * math.cos(th), cy + bb * math.sin(th), p.z))
		w = 1.0 - sst(0.32, 0.45, f)                    # cerca de los ojos se respeta la malla
		v.co = inv @ p.lerp(tgt, w)
	mesh.data.update()


def mask_pred(arm, dom):
	h0 = bone_seg(arm, "Head")[0]
	top = bone_seg(arm, "HeadTop_End")[0]
	hh = top.z - h0.z
	return lambda i, p: dom[i] in ("Head", "Neck") and h0.z - 0.05 * hh < p.z < h0.z + 0.4 * hh and p.y < h0.y - 0.18 * hh


def wrap_to_proxy(mesh, dom, voxel=0.0002, only=None, smooth_iters=15):
	"""Remallado de vóxeles + suavizado = piel lisa sin cavidades (bolsillos, cordones, cierre);
	los vértices del cuerpo se pegan a esa superficie."""
	from mathutils.bvhtree import BVHTree
	proxy = mesh.copy()
	proxy.data = mesh.data.copy()
	proxy.modifiers.clear()
	proxy.parent = None
	proxy.matrix_world = mesh.matrix_world.copy()
	bpy.context.scene.collection.objects.link(proxy)
	r = proxy.modifiers.new("remesh", "REMESH"); r.mode = "VOXEL"; r.voxel_size = voxel / proxy.matrix_world.to_scale().x
	s = proxy.modifiers.new("smooth", "LAPLACIANSMOOTH"); s.iterations = smooth_iters; s.lambda_factor = 0.5; s.use_volume_preserve = True
	dg = bpy.context.evaluated_depsgraph_get()
	ev = proxy.evaluated_get(dg)
	pm = ev.to_mesh()
	pw = proxy.matrix_world
	tree = BVHTree.FromPolygons([pw @ v.co for v in pm.vertices], [list(p.vertices) for p in pm.polygons])
	ev.to_mesh_clear()
	bpy.data.objects.remove(proxy)
	mw = mesh.matrix_world
	inv = mw.inverted()
	for i, v in enumerate(mesh.data.vertices):
		if only is not None and dom[i] not in only:
			continue
		hit = tree.find_nearest(mw @ v.co)
		if hit[0] is not None:
			v.co = inv @ hit[0]
	mesh.data.update()


def delete_inner_faces(mesh, dom, bones=TORSO_BONES, thresh=-0.3):
	"""Forro de la capucha y bolsillos: caras del torso que miran hacia dentro (quedan pegadas a la piel
	tras ajustar y se ven como manchas)."""
	mw = mesh.matrix_world
	n3 = mw.to_3x3()
	bm = bmesh.new()
	bm.from_mesh(mesh.data)
	bm.faces.ensure_lookup_table()
	bad = []
	for f in bm.faces:
		if all(dom[v.index] in bones for v in f.verts):
			c = mw @ f.calc_center_median()
			n = (n3 @ f.normal).normalized()
			out = Vector((c.x, c.y - 0.0001, 0)).normalized()
			if n.dot(out) < thresh:
				bad.append(f)
	bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")
	loose = [v for v in bm.verts if not v.link_faces]
	bmesh.ops.delete(bm, geom=loose, context="VERTS")
	bm.to_mesh(mesh.data)
	bm.free()
	mesh.data.update()
	return len(bad)


def build(do_smooth=True):
	sc, mesh, arm = scene_objs()
	reset_mesh(mesh)
	dom = fit_to_body(mesh, arm)
	neck_clamp(mesh, arm, dom)
	flatten_mask(mesh, arm, dom)
	if do_smooth:
		wrap_to_proxy(mesh, dom, only=TORSO_BONES)
		smooth(mesh, dom)
		# Torso: muchas pasadas (se tragan cordones, cierre y bolsillos)
		smooth_region(mesh, lambda i, p: dom[i] in TORSO_BONES, 30, 0.5)
		# Máscara: se aplana sobre la cara
		smooth_region(mesh, mask_pred(arm, dom), 20, 0.5)
	print("caras interiores borradas:", delete_inner_faces(mesh, dom))
	return sc, mesh, arm, dominant_bones(mesh)


# ───────────────────────────── cuerpo re-mallado ─────────────────────────────
KEEP_ORIGINAL = lambda b: b in ("Head", "HeadTop_End") or "Hand" in b   # cabeza y manos: geometría original
BODY_VOXEL = 0.000065     # m (mundo): ~270 vóxeles de alto
BODY_FACES = 9000


def _copy_obj(src, name):
	ob = src.copy()
	ob.data = src.data.copy()
	ob.name = name
	bpy.data.scenes[SCENE].collection.objects.link(ob)
	return ob


def _apply_all(ob, keep_armature=True):
	with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
		for m in list(ob.modifiers):
			if keep_armature and m.type == "ARMATURE":
				continue
			bpy.ops.object.modifier_apply(modifier=m.name)


def _delete_verts(ob, pred):
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if pred(v)], context="VERTS")
	bm.to_mesh(ob.data)
	bm.free()


def remesh_body(mesh, dom, keep_mask):
	"""Devuelve el objeto final: cuerpo re-mallado (con pesos transferidos) + cabeza y manos originales."""
	from mathutils.kdtree import KDTree
	sc = bpy.data.scenes[SCENE]
	mw = mesh.matrix_world
	# KD-tree de la malla ajustada para saber qué hueso domina cerca de cada vértice nuevo
	kd = KDTree(len(mesh.data.vertices))
	for i, v in enumerate(mesh.data.vertices):
		kd.insert(mw @ v.co, i)
	kd.balance()
	body = _copy_obj(mesh, "RivaBody_tmp")
	for m in list(body.modifiers):
		body.modifiers.remove(m)
	s = body.matrix_world.to_scale().x
	r = body.modifiers.new("remesh", "REMESH"); r.mode = "VOXEL"; r.voxel_size = BODY_VOXEL / s
	r.use_smooth_shade = True
	sm = body.modifiers.new("smooth", "LAPLACIANSMOOTH"); sm.iterations = 6; sm.lambda_factor = 0.4; sm.use_volume_preserve = True
	_apply_all(body, keep_armature=False)
	dec = body.modifiers.new("dec", "DECIMATE"); dec.ratio = min(1.0, BODY_FACES / max(len(body.data.polygons), 1))
	_apply_all(body, keep_armature=False)
	# Fuera del cuerpo nuevo lo que se queda original (cabeza y manos), con un pequeño solape en el cuello
	bw = body.matrix_world
	# Solo se borra lo que queda claramente dentro de una pieza conservada (todos sus vecinos lo son):
	# así el cuerpo nuevo solapa un poco con manos y cabeza y no se abren huecos en muñecas/cuello
	_delete_verts(body, lambda v: all(keep_mask[i] for _c, i, _d in kd.find_n(bw @ v.co, 10)))
	# Pesos: transferencia desde la malla ajustada (cara más cercana interpolada)
	body.vertex_groups.clear()
	for g in mesh.vertex_groups:
		body.vertex_groups.new(name=g.name)
	dt = body.modifiers.new("weights", "DATA_TRANSFER")
	dt.object = mesh
	dt.use_vert_data = True
	dt.data_types_verts = {"VGROUP_WEIGHTS"}
	dt.vert_mapping = "POLYINTERP_NEAREST"
	dt.layers_vgroup_select_src = "ALL"
	dt.layers_vgroup_select_dst = "NAME"
	with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body]):
		bpy.ops.object.modifier_move_to_index(modifier="weights", index=0)
		bpy.ops.object.modifier_apply(modifier="weights")
	# Parte original: cabeza y manos
	keep = _copy_obj(mesh, "RivaKeep_tmp")
	_delete_verts(keep, lambda v: not keep_mask[v.index])
	return body, keep


def join_into(mesh, body, keep):
	"""Sustituye la geometría de `mesh` por cuerpo + piezas originales (conserva objeto, padre y armadura)."""
	with bpy.context.temp_override(active_object=keep, selected_editable_objects=[keep, body], object=keep):
		bpy.ops.object.join()
	old = mesh.data
	mesh.data = keep.data
	mesh.data.name = "RivaBaseMesh"
	bpy.data.objects.remove(keep)
	if old.users == 0:
		bpy.data.meshes.remove(old)
	# Normales coherentes y suavizado
	bm = bmesh.new(); bm.from_mesh(mesh.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.000002 / mesh.matrix_world.to_scale().x)
	bm.to_mesh(mesh.data); bm.free()
	for p in mesh.data.polygons:
		p.use_smooth = True
	mesh.data.update()


def build_clean():
	sc, mesh, arm = scene_objs()
	reset_mesh(mesh)
	dom = fit_to_body(mesh, arm)
	neck_clamp(mesh, arm, dom)
	smooth(mesh, dom)          # no toca cabeza ni manos
	# Cabeza y manos: geometría original (la máscara queda como mandíbula y se pinta de piel)
	h0 = bone_seg(arm, "Head")[0]
	hh = bone_seg(arm, "HeadTop_End")[0].z - h0.z
	mw = mesh.matrix_world
	keep_mask = []
	for i, v in enumerate(mesh.data.vertices):
		p = mw @ v.co
		b = dom[i]
		if "Hand" in b:
			keep_mask.append(True)
		elif b in ("Head", "HeadTop_End"):
			keep_mask.append(True)
		else:
			keep_mask.append(False)
	body, keep = remesh_body(mesh, dom, keep_mask)
	join_into(mesh, body, keep)
	print("caras:", len(mesh.data.polygons))
	return sc, mesh, arm


# ───────────────────────────── materiales y textura ─────────────────────────────
ZONES_PNG = os.path.join(REPO, "assets", "textures", "entities", "riva", "riva_zones.png")
DETAIL_PNG = os.path.join(REPO, "assets", "textures", "entities", "riva", "riva_base_detail.png")
TEX_RES = 1024
# Material -> color por defecto (el juego los sobrescribe con CharacterLook)
MATERIALS = {
	"Piel": (0.93, 0.80, 0.70),
	"Cara": (0.93, 0.80, 0.70),
	"Cabello": (0.10, 0.11, 0.16),
	"Calzones": (0.20, 0.35, 0.80),
	"Elastico": (0.95, 0.95, 0.95),
}
R_HAIR, R_FACE, R_MASK = 1, 2, 3


def _load_px(path, res):
	img = bpy.data.images.load(path, check_existing=False)
	if tuple(img.size) != (res, res):
		img.scale(res, res)
	px = np.empty(res * res * 4, np.float32)
	img.pixels.foreach_get(px)
	bpy.data.images.remove(img)
	return px.reshape(res, res, 4)


def bake_detail_texture():
	"""Textura en gris (se multiplica por el color elegido): cara = piel lisa con ojos/cejas oscuros,
	cabello = mechones (luminancia de la textura original), máscara = piel lisa."""
	tex = _load_px(SRC_TEX, TEX_RES)
	zones = np.rint(_load_px(ZONES_PNG, TEX_RES)[:, :, 0] * 15).astype(int)
	rgb = tex[:, :, :3]
	lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)   # Blender da píxeles lineales
	out = np.ones_like(lum)
	hair = zones == R_HAIR
	out[hair] = np.clip(0.8 * np.sqrt(lum[hair] / 0.018), 0.3, 1.0)
	face = zones == R_FACE
	mx = rgb.max(axis=2); mn = rgb.min(axis=2)
	sat = (mx - mn) / np.maximum(mx, 1e-6)
	skin = face & (sat > 0.12) & (mx > 0.25)
	dark = face & (mx < 0.08)
	out[face] = np.clip(lum[face] / 0.62, 0.15, 1.0)             # ojos: blanco ≈ 1, iris/pestañas oscuros
	out[skin] = np.clip(0.85 + 0.15 * lum[skin] / 0.62, 0.0, 1.0)
	out[dark] = np.clip(lum[dark] / 0.62 + 0.08, 0.08, 0.4)
	out[zones == R_MASK] = 1.0
	img = bpy.data.images.get("riva_base_detail") or bpy.data.images.new("riva_base_detail", TEX_RES, TEX_RES)
	rgba = np.dstack([out, out, out, np.ones_like(out)]).astype(np.float32)
	img.pixels.foreach_set(rgba.ravel())
	img.filepath_raw = DETAIL_PNG
	img.file_format = "PNG"
	img.save()
	return img


def _material(name, img=None):
	m = bpy.data.materials.get("rb_" + name) or bpy.data.materials.new("rb_" + name)
	m.use_nodes = True
	nt = m.node_tree
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	c = MATERIALS[name]
	bsdf.inputs["Roughness"].default_value = 0.85
	for n in [n for n in nt.nodes if n.type in ("TEX_IMAGE", "MIX")]:
		nt.nodes.remove(n)
	if img is None:
		bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
	else:
		t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
		mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
		mix.inputs[0].default_value = 1.0
		mix.inputs[6].default_value = (c[0], c[1], c[2], 1)
		nt.links.new(t.outputs[0], mix.inputs[7])
		nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
	m["rumbang_slot"] = name
	return m


def assign_materials(mesh, arm):
	img = bake_detail_texture()
	zones = np.rint(_load_px(ZONES_PNG, TEX_RES)[:, :, 0] * 15).astype(int)
	me = mesh.data
	me.materials.clear()
	order = list(MATERIALS)
	for n in order:
		me.materials.append(_material(n, img if n in ("Cara", "Cabello") else None))
	dom = dominant_bones(mesh)
	mw = mesh.matrix_world
	hips_z = bone_seg(arm, "Hips")[0].z
	upleg_z = bone_seg(arm, "LeftUpLeg")[0].z
	cx = bone_seg(arm, "Hips")[0].x
	uv = me.uv_layers.active.data if me.uv_layers.active else None
	z_top = hips_z + 0.00045
	band = 0.00018
	head_z = bone_seg(arm, "Head")[0].z
	head_h = bone_seg(arm, "HeadTop_End")[0].z - head_z
	for p in me.polygons:
		c = mw @ p.center
		b = collections.Counter(dom[v] for v in p.vertices).most_common(1)[0][0]
		idx = order.index("Piel")
		if b in ("Head", "HeadTop_End") and uv is not None:
			us = [uv[li].uv for li in p.loop_indices]
			u = sum(x[0] for x in us) / len(us); w = sum(x[1] for x in us) / len(us)
			reg = zones[min(TEX_RES - 1, max(0, int(w * TEX_RES))), min(TEX_RES - 1, max(0, int(u * TEX_RES)))]
			if reg == R_HAIR:
				idx = order.index("Cabello")
			elif (c.z - head_z) / head_h > 0.37:
				idx = order.index("Cara")          # ojos y cejas (textura de detalle)
			# por debajo de los ojos (antes máscara): piel lisa
		elif "Hand" not in b:
			ax = abs(c.x - cx)
			z_low = (upleg_z - 0.0011) + SLOPE * max(0.0, ax - 0.0003)
			if z_low < c.z < z_top:
				idx = order.index("Elastico" if c.z > z_top - band else "Calzones")
		p.material_index = idx
	me.update()


SLOPE = 0.6 / 0.9          # subida del corte de la pierna hacia fuera (calzón tipo slip)


def cut_underwear(mesh, arm):
	"""Corta la malla por los bordes del calzón (cintura, elástico, perneras) para que queden rectos."""
	mw = mesh.matrix_world
	inv = mw.inverted()
	hips_z = bone_seg(arm, "Hips")[0].z
	upleg_z = bone_seg(arm, "LeftUpLeg")[0].z
	knee_z = bone_seg(arm, "LeftLeg")[0].z
	cx = bone_seg(arm, "Hips")[0].x
	z_top = hips_z + 0.00045
	z0 = upleg_z - 0.0011
	n3 = inv.to_3x3()
	bm = bmesh.new(); bm.from_mesh(mesh.data)
	def region(sel):
		bm.faces.ensure_lookup_table()
		fs = [f for f in bm.faces if sel(mw @ f.calc_center_median())]
		vs = {v for f in fs for v in f.verts}
		es = {e for f in fs for e in f.edges}
		return list(vs) + list(es) + fs
	def cut(co, no, sel):
		co_l = inv @ Vector(co)
		no_l = (n3 @ Vector(no)).normalized()
		bmesh.ops.bisect_plane(bm, geom=region(sel), plane_co=co_l, plane_no=no_l)
	near = lambda c: knee_z < c.z < hips_z + 0.0012 and abs(c.x - cx) < 0.0025
	cut((cx, 0, z_top), (0, 0, 1), near)
	cut((cx, 0, z_top - 0.00018), (0, 0, 1), near)
	cut((cx, 0, z0), (0, 0, 1), lambda c: near(c) and abs(c.x - cx) < 0.0003)
	for s in (1, -1):
		cut((cx + s * 0.0003, 0, z0), (-s * SLOPE, 0, 1), lambda c, s=s: near(c) and (c.x - cx) * s > 0.0002)
	bm.to_mesh(mesh.data); bm.free()
	mesh.data.update()
