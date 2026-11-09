"""Cuerpo base v2 (estilo PS2 callejero con toque anime): proporciones y atlas de piel.

Parte del cuerpo en calzones que deja tools/blender_riva_base.py (objeto RivaBase de la escena
Riva_Personaje en rumbang_anims.blend) y:
  1. reshape(): engorda brazos, piernas y cuello y ensancha pecho/hombros escalando cada vértice en
     dirección perpendicular a sus huesos (mezcla por pesos: no se abren costuras). Los huesos no se
     mueven, así que los clips riva-*.fbx siguen valiendo.
  2. make_atlas(): capa UV nueva "Atlas" — cuerpo desplegado (smart project) en la parte de abajo y la
     cabeza con sus UV originales (para no perder ojos y mechones) en el cuadrante de arriba.
  3. bake_skin(): hornea (Cycles, CPU) una textura en escala de grises/teñida que el juego multiplica
     por el color elegido: AO, pliegues, rubor en rodillas/codos/mejillas, cara y pelo de la textura
     de detalle anterior. Sale a assets/textures/entities/riva/riva_skin.png.

Se ejecuta desde el MCP con rumbang_anims.blend abierto:
  ns = {"__name__": "riva_v2", "__file__": r"<repo>/tools/blender_riva_body_v2.py"}
  exec(open(ns["__file__"], encoding="utf-8").read(), ns); ns["reshape"]()
"""
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector
from mathutils.geometry import intersect_point_line

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE = "Riva_Personaje"
MESH = "RivaBase"
ARM = "RivaBaseArmature"
V1 = "RivaBaseMesh_v1"     # copia de la malla antes de reshape (para re-ejecutar)
P = "mixamorig:"

# Escala perpendicular al hueso por grupo: (x, y) en mundo para el torso, o un único factor radial.
# El frente es -Y. Valores pensados para un chico delgado pero atlético (no un palo).
SHAPE = {
	"Arm": 1.24, "ForeArm": 1.16, "UpLeg": 1.13, "Leg": 1.14,
	"Neck": 1.16, "Shoulder": 1.12,
	"Spine2": (1.12, 1.07), "Spine1": (1.07, 1.04), "Spine": (1.04, 1.03), "Hips": (1.03, 1.03),
}


def objs():
	sc = bpy.data.scenes[SCENE]
	return sc, sc.objects[MESH], sc.objects[ARM]


def _shape_for(bone):
	b = bone[len(P):] if bone.startswith(P) else bone
	for side in ("Left", "Right"):
		if b.startswith(side):
			b = b[len(side):]
	return SHAPE.get(b)


def _restore_v1(mesh):
	"""La primera vez guarda una copia de la malla; las siguientes la restaura (re-ejecutable)."""
	src = bpy.data.meshes.get(V1)
	if src is None:
		src = mesh.data.copy()
		src.name = V1
		src.use_fake_user = True
		return
	old = mesh.data
	mesh.data = src.copy()
	mesh.data.name = "RivaBaseMesh"
	if old.users == 0:
		bpy.data.meshes.remove(old)


def rebuild():
	"""Todo el paso v2 desde la copia guardada: proporciones + cabeza nueva."""
	sc, mesh, arm = objs()
	_restore_v1(mesh)
	reshape(restore=False)
	build_head()


def reshape(restore=True):
	sc, mesh, arm = objs()
	if restore:
		_restore_v1(mesh)
	mw = mesh.matrix_world
	inv = mw.inverted()
	aw = arm.matrix_world
	segs = {}
	for b in arm.data.bones:
		s = _shape_for(b.name)
		if s is not None:
			segs[b.name] = (aw @ b.head_local, aw @ b.tail_local, s)
	names = [g.name for g in mesh.vertex_groups]
	n_moved = 0
	for v in mesh.data.vertices:
		p = mw @ v.co
		disp = Vector()
		for g in v.groups:
			if g.weight <= 0.0:
				continue
			seg = segs.get(names[g.group])
			if seg is None:
				continue
			h, t, s = seg
			q, f = intersect_point_line(p, h, t)
			f = min(1.0, max(0.0, f))
			q = h.lerp(t, f)
			off = p - q
			if isinstance(s, tuple):
				off_s = Vector((off.x * s[0], off.y * s[1], off.z))
			else:
				axis = (t - h).normalized()
				along = axis * off.dot(axis)
				off_s = along + (off - along) * s
			disp += (off_s - off) * g.weight
		if disp.length_squared > 0.0:
			v.co = inv @ (p + disp)
			n_moved += 1
	mesh.data.update()
	print("reshape: vértices movidos", n_moved)


# ───────────────────────────── cabeza nueva ─────────────────────────────
# La cabeza original salía de la máscara de Riva (mandíbula con forma de cresta, sin nariz ni boca).
# Se sustituye por una cabeza estilizada (anime sutil): cráneo redondo, mandíbula que se estrecha hacia
# una barbilla suave, nariz pequeña, orejas y un trozo de cuello que se mete en el del cuerpo. Los rasgos
# (ojos, cejas, boca) van pintados en la textura (estilo PS2). Unidades: mundo * 1000.
HEAD_C = Vector((0.0, 0.42, 16.36))
HEAD_R = (0.84, 0.90, 1.00, 1.04)       # rx, ry delante, ry detrás, rz arriba
CHIN_DROP = 1.02                         # centro -> barbilla
HEAD_SEG = (40, 28)
# Rasgos en coordenadas de la esfera (z: 0 = centro, -1 = barbilla). El flequillo acaba en z ≈ -0.06.
EYE_Z = -0.22
NOSE_Z = -0.50
MOUTH_Z = -0.72
NECK = ((Vector((0.0, 0.74, 14.95)), 0.46, 0.57), (Vector((0.0, 0.58, 15.95)), 0.38, 0.42))   # (centro, rx, ry) base / arriba
NECK_CUT = 15.30    # por encima, el cuello del cuerpo (resto de la capucha) se borra: lo sustituye el de la cabeza
HEAD_BONES = ("mixamorig:Head", "mixamorig:HeadTop_End")


def _gauss(a, b, sa, sb):
	return math.exp(-0.5 * ((a / sa) ** 2 + (b / sb) ** 2))


def _head_point(x, y, z):
	"""Punto de la esfera unidad -> cabeza (y negativo = delante)."""
	rx, ryf, ryb, rzt = HEAD_R
	front = y < 0.0
	if z >= 0.0:
		X, Y, Z = x * rx, y * (ryf if front else ryb), z * rzt
	else:
		t = -z
		wj = 1.0 - 0.42 * t ** 2.4                      # la mandíbula se estrecha hacia la barbilla
		if front:
			Y = y * ryf * (1.0 - 0.18 * t ** 2)
			Z = z * CHIN_DROP
		else:
			k = min(1.0, y * 1.6)
			Y = y * ryb * (1.0 - 0.40 * t ** 1.3)
			Z = z * (CHIN_DROP * (1.0 - k) + 0.78 * k)   # la nuca no cuelga tanto como la barbilla
		X = x * rx * wj
	if front:
		# cara un poco plana y mejillas que caen hacia atrás
		Y *= 1.0 - 0.10 * _gauss(x, z + 0.15, 0.55, 0.5)
		# nariz: pequeña, más marcada abajo
		Y -= 0.14 * _gauss(x, z - NOSE_Z, 0.07 + 0.03 * max(0.0, z - NOSE_Z), 0.16 if z > NOSE_Z else 0.06)   # puente largo, punta corta
		# cuencas de los ojos muy suaves y arco de las cejas
		for sx in (-0.34, 0.34):
			Y += 0.035 * _gauss(x - sx, z - EYE_Z, 0.14, 0.08)
		Y -= 0.025 * _gauss(x, z - EYE_Z - 0.17, 0.45, 0.05)
		# barbilla: un pelín hacia delante
		Y -= 0.05 * _gauss(x, z + 1.0, 0.12, 0.10)
	return Vector((X, Y, Z))


def _neck_weights(z):
	lo, hi = 15.45, 15.85
	t = min(1.0, max(0.0, (z - lo) / (hi - lo)))
	return {"mixamorig:Neck": 1.0 - t, "mixamorig:Head": t}


def build_head(join=True):
	sc, mesh, arm = objs()
	mw = mesh.matrix_world
	inv = mw.inverted()
	s = 0.001
	bm = bmesh.new()
	# cráneo + cara
	bmesh.ops.create_uvsphere(bm, u_segments=HEAD_SEG[0], v_segments=HEAD_SEG[1], radius=1.0)
	for v in bm.verts:
		v.co = HEAD_C + _head_point(v.co.x, v.co.y, v.co.z)
	n_head = len(bm.verts)
	# orejas: elipsoides aplastados a los lados
	for sx in (-1, 1):
		g = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=1.0)
		for v in g["verts"]:
			c = v.co
			v.co = Vector((sx * (HEAD_R[0] * 0.93) + c.x * 0.07, 0.50 + c.y * 0.17, 16.22 + c.z * 0.27))
	n_ears = len(bm.verts)
	# cuello
	(b0, bx, by), (t0, tx, ty) = NECK
	SEG, RINGS = 24, 6
	rings = []
	for r in range(RINGS):
		t = r / (RINGS - 1)
		c = b0.lerp(t0, t)
		rx = bx + (tx - bx) * t
		ry = by + (ty - by) * t
		rings.append([bm.verts.new((c.x + math.cos(2 * math.pi * k / SEG) * rx,
			c.y + math.sin(2 * math.pi * k / SEG) * ry, c.z)) for k in range(SEG)])
	for r in range(RINGS - 1):
		for k in range(SEG):
			k2 = (k + 1) % SEG
			bm.faces.new((rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.verts.index_update()
	for v in bm.verts:
		v.co = inv @ (v.co * s)
	head_me = bpy.data.meshes.new("RivaHead_tmp")
	bm.to_mesh(head_me)
	bm.free()
	ob = bpy.data.objects.new("RivaHead_tmp", head_me)
	sc.collection.objects.link(ob)
	ob.matrix_world = mw.copy()
	for p in head_me.polygons:
		p.use_smooth = True
	# parte de cada cara (0 cabeza, 1 oreja, 2 cuello) para el atlas
	part = head_me.attributes.new("rb_part", "INT", "FACE")
	for p in head_me.polygons:
		vi = p.vertices[0]
		part.data[p.index].value = 0 if vi < n_head else (1 if vi < n_ears else 2)
	# pesos
	for g in mesh.vertex_groups:
		ob.vertex_groups.new(name=g.name)
	vg = {g.name: g for g in ob.vertex_groups}
	for v in head_me.vertices:
		z = (mw @ v.co).z * 1000
		ws = _neck_weights(z) if v.index >= n_head or z < 15.85 else {"mixamorig:Head": 1.0}
		for name, w in ws.items():
			if w > 0.0:
				vg[name].add([v.index], w, "REPLACE")
	# material: cara (se pinta en la textura del atlas)
	head_me.materials.clear()
	for m in mesh.data.materials:
		head_me.materials.append(m)
	cara = [m.name for m in mesh.data.materials].index("rb_Cara")
	for p in head_me.polygons:
		p.material_index = cara
	if not join:
		return ob
	# borrar la cabeza vieja (todo lo que no es pelo y domina la cabeza)
	names = [g.name for g in mesh.vertex_groups]
	mats = [m.name for m in mesh.data.materials]
	dom = [names[max(v.groups, key=lambda g: g.weight).group] if v.groups else "" for v in mesh.data.vertices]
	bm = bmesh.new(); bm.from_mesh(mesh.data)
	bm.faces.ensure_lookup_table()
	mwz = lambda f: (mw @ f.calc_center_median()).z * 1000
	kill = [f for f in bm.faces if mats[f.material_index] in ("rb_Piel", "rb_Cara") and (
		sum(dom[v.index] in HEAD_BONES for v in f.verts) * 2 >= len(f.verts)
		or (mwz(f) > NECK_CUT and abs((mw @ f.calc_center_median()).x) < 0.0006))]
	bmesh.ops.delete(bm, geom=kill, context="FACES")
	bm.to_mesh(mesh.data); bm.free()
	mesh.data.update()
	with bpy.context.temp_override(active_object=mesh, selected_editable_objects=[mesh, ob], object=mesh):
		bpy.ops.object.join()
	print("cabeza nueva; caras borradas", len(kill), "total", len(mesh.data.polygons))


# ───────────────────────────── UV "Atlas" ─────────────────────────────
# Segunda capa UV (en Godot: UV2). Cada superficie tiene el cuadrado 0-1 entero para su textura:
#   rb_Cara (cabeza nueva, orejas, cuello)  -> riva_face_*.png, proyección cilíndrica (delante = u 0.5)
#   rb_Piel / rb_Calzones / rb_Elastico     -> riva_body.png, smart project
#   rb_Cabello                               -> sigue usando la UV original (textura de mechones)
ATLAS = "Atlas"
FACE_V = (15.25, 17.45)     # z (mundo*1000) de la cabeza -> v [HEAD_V0, 1]
HEAD_V0 = 0.22
NECK_V = (14.95, 15.95)     # cuello -> v [0, 0.2], u [0.12, 0.88]
TEX_DIR = os.path.join(REPO, "assets", "textures", "entities", "riva")
BODY_RES, FACE_RES = 1024, 512
BODY_MATS = ("rb_Piel", "rb_Calzones", "rb_Elastico")


def face_uv(p):
	"""Punto (mundo*1000) de la cabeza -> UV de la textura de la cara. Más resolución delante (sin(a/2))."""
	d = p - HEAD_C
	a = math.atan2(d.x, -d.y)                 # 0 = de frente
	u = 0.5 + 0.5 * math.sin(a / 2.0)
	v = HEAD_V0 + (1.0 - HEAD_V0) * (p.z - FACE_V[0]) / (FACE_V[1] - FACE_V[0])
	return u, v


def neck_uv(p):
	c = NECK[0][0]
	a = math.atan2(p.x - c.x, -(p.y - c.y))
	u = 0.5 + 0.38 * a / math.pi
	v = 0.2 * (p.z - NECK_V[0]) / (NECK_V[1] - NECK_V[0])
	return u, v


def ear_uv(p):
	side = 1 if p.x > 0 else 0
	u = (0.9 if side else 0.0) + 0.1 * min(1.0, max(0.0, (p.y - 0.33) / 0.34))
	v = 0.2 * min(1.0, max(0.0, (p.z - 15.95) / 0.54))
	return u, v


def face_uv_inv(u, v):
	"""Inversa aproximada para pintar: UV -> (x frontal, z) en mundo*1000 (proyección de frente)."""
	a = 2.0 * np.arcsin(np.clip(2.0 * (u - 0.5), -1.0, 1.0))
	z = FACE_V[0] + (v - HEAD_V0) / (1.0 - HEAD_V0) * (FACE_V[1] - FACE_V[0])
	return a, z


def make_atlas():
	sc, mesh, arm = objs()
	me = mesh.data
	if me.uv_layers.get(ATLAS) is None:
		me.uv_layers.new(name=ATLAS)
	src_uv = me.uv_layers[0]
	src_uv.active_render = True
	uv = me.uv_layers[ATLAS]
	mats = [m.name for m in me.materials]
	mw = mesh.matrix_world
	# cabeza: cilíndrica; cuello y orejas en su propia franja
	part = me.attributes.get("rb_part")
	fn = (face_uv, ear_uv, neck_uv)
	for p in me.polygons:
		if mats[p.material_index] == "rb_Cara":
			f = fn[part.data[p.index].value if part else 0]
			for li in p.loop_indices:
				co = mw @ me.vertices[me.loops[li].vertex_index].co * 1000
				uv.data[li].uv = f(co)
		elif mats[p.material_index] == "rb_Cabello":
			for li in p.loop_indices:
				uv.data[li].uv = (0.999, 0.999)
	# cuerpo: smart project sólo de sus caras
	me.uv_layers.active = uv
	body_idx = {mats.index(n) for n in BODY_MATS if n in mats}
	for p in me.polygons:
		p.select = p.material_index in body_idx
	view_layer = bpy.context.view_layer
	for ob in view_layer.objects:
		ob.select_set(False)
	mesh.hide_set(False)
	mesh.select_set(True)
	view_layer.objects.active = mesh
	sc.tool_settings.mesh_select_mode = (False, False, True)
	for v in me.vertices:
		v.select = False
	for e in me.edges:
		e.select = False
	for p in me.polygons:
		if p.select:
			for i in p.vertices:
				me.vertices[i].select = True
	bpy.ops.object.mode_set(mode="EDIT")
	try:
		bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0,
			correct_aspect=True, scale_to_bounds=False)
	finally:
		bpy.ops.object.mode_set(mode="OBJECT")
	me.uv_layers.active = src_uv
	print("atlas listo")


# ───────────────────────────── texturas ─────────────────────────────
def _image(name, res, path):
	img = bpy.data.images.get(name)
	if img is None or tuple(img.size) != (res, res):
		if img:
			bpy.data.images.remove(img)
		img = bpy.data.images.new(name, res, res, alpha=False, float_buffer=False)
	img.filepath_raw = path
	img.file_format = "PNG"
	return img


def _set_bake_targets(targets):
	"""targets: material -> imagen (nodo de imagen activo con UV Atlas) para el horneado."""
	for m in bpy.data.objects[MESH].data.materials:
		nt = m.node_tree
		for n in [n for n in nt.nodes if n.name.startswith("bake_")]:
			nt.nodes.remove(n)
		img = targets.get(m.name)
		if img is None:
			img = targets["__dummy__"]
		t = nt.nodes.new("ShaderNodeTexImage"); t.name = "bake_img"; t.image = img
		uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.name = "bake_uv"
		uvn.uv_map = ATLAS if m.name != "rb_Cabello" else bpy.data.objects[MESH].data.uv_layers[0].name
		nt.links.new(uvn.outputs[0], t.inputs[0])
		nt.nodes.active = t


def _clear_bake_nodes():
	for m in bpy.data.objects[MESH].data.materials:
		nt = m.node_tree
		for n in [n for n in nt.nodes if n.name.startswith("bake_")]:
			nt.nodes.remove(n)


def bake_ao(samples=48):
	"""Hornea oclusión ambiental (Cycles, CPU) del cuerpo y la cabeza en reposo. Devuelve arrays (H, W)."""
	sc, mesh, arm = objs()
	arm.data.pose_position = "REST"
	body = _image("riva_ao_body", BODY_RES, os.path.join(TEX_DIR, "_ao_body.png"))
	face = _image("riva_ao_face", FACE_RES, os.path.join(TEX_DIR, "_ao_face.png"))
	dummy = _image("riva_ao_dummy", 16, os.path.join(TEX_DIR, "_ao_dummy.png"))
	targets = {n: body for n in BODY_MATS}
	targets["rb_Cara"] = face
	targets["__dummy__"] = dummy
	_set_bake_targets(targets)
	prev = sc.render.engine
	try:
		sc.render.engine = "CYCLES"
	except TypeError as e:
		print(e)
	sc.cycles.device = "CPU"
	sc.cycles.samples = samples
	sc.world = sc.world or bpy.data.worlds.new("bake_world")
	sc.world.light_settings.distance = 0.0004        # mundo: ~2/3 del ancho de la cabeza
	sc.render.bake.margin = 6
	sc.render.bake.use_clear = True
	uvl = mesh.data.uv_layers
	uvl.active = uvl[ATLAS]
	view_layer = bpy.context.view_layer
	for ob in view_layer.objects:
		ob.select_set(False)
	mesh.select_set(True)
	view_layer.objects.active = mesh
	try:
		bpy.ops.object.bake(type="AO", margin=6, use_clear=True)
	finally:
		uvl.active = uvl[0]
	sc.render.engine = prev
	_clear_bake_nodes()
	out = {}
	for key, img in (("body", body), ("face", face)):
		px = np.empty(img.size[0] * img.size[1] * 4, np.float32)
		img.pixels.foreach_get(px)
		out[key] = px.reshape(img.size[1], img.size[0], 4)[:, :, 0].copy()
	return out
