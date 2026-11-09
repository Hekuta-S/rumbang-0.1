"""Accesorios del personaje personalizable (Riva): gorros y calzado.

Cada accesorio se construye a partir de la propia malla de Riva (pose de enlace) y se exporta
NORMALIZADO a la caja de su región, así en el juego CharacterLookApplier lo coloca midiendo la
misma región en la malla de Godot (no depende de la escala/ejes del importador FBX):

  frame "head" : vértices cuyo hueso dominante es Head
  frame "foot" : vértices dominados por LeftFoot/LeftToeBase (el derecho usa el mismo modelo)
  frame "shin" : vértices dominados por LeftLeg en el 35 % inferior de su altura

Coordenadas normalizadas (Blender): x = (x-cx)/ancho, y = (y-cy)/fondo (-Y = frente), z = (z-zmin)/alto.
El exportador glTF pasa eso a Godot como (x, z, -y): Y arriba, +Z al frente.

Materiales (los recolorea el juego por nombre): acc_main, acc_second, acc_sole, acc_metal.

Uso: blender.exe -b --python tools/blender_riva_accessories.py
     o en el MCP: exec(open(r"<repo>/tools/blender_riva_accessories.py").read(), {"__name__": "x", "__file__": ...}); run()
"""
import bpy, bmesh, math, os, collections
from mathutils import Vector, Matrix

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
FBX = os.path.join(REPO, "assets", "models", "riva", "riva-idle.fbx")
OUT_DIR = os.path.join(REPO, "assets", "models", "riva", "accesorios")
SHIN_FRACTION = 0.35   # debe coincidir con CharacterLookApplier.SHIN_FRACTION

MAT_COLORS = {
	"acc_main": (0.8, 0.2, 0.2, 1), "acc_second": (0.9, 0.9, 0.9, 1),
	"acc_sole": (0.92, 0.9, 0.85, 1), "acc_metal": (0.75, 0.7, 0.55, 1),
}


# ───────────────────────────── utilidades ─────────────────────────────

def mat(name):
	m = bpy.data.materials.get(name)
	if m is None:
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
		b.inputs["Base Color"].default_value = MAT_COLORS[name]
		b.inputs["Roughness"].default_value = 0.8
	return m


def new_obj(name, bm, coll):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	coll.objects.link(ob)
	return ob


def apply_mods(ob):
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = ob
	ob.select_set(True)
	for m in list(ob.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)


def smooth_shade(ob):
	for p in ob.data.polygons:
		p.use_smooth = True


def set_mat(ob, names, assign=None):
	"""names: lista de materiales; assign(poly_center, normal) -> índice."""
	ob.data.materials.clear()
	for n in names:
		ob.data.materials.append(mat(n))
	if assign:
		for p in ob.data.polygons:
			p.material_index = assign(p.center, p.normal)


def hull_blob(points, name, coll, voxel, inflate, smooth_iters=6, decimate=0.35):
	"""Envolvente convexa -> remallado de vóxeles -> suavizado e inflado: forma blanda que cubre los puntos."""
	bm = bmesh.new()
	for p in points:
		bm.verts.new(p)
	bmesh.ops.convex_hull(bm, input=bm.verts)
	ob = new_obj(name, bm, coll)
	r = ob.modifiers.new("remesh", "REMESH"); r.mode = "VOXEL"; r.voxel_size = voxel
	# Suavizado laplaciano con conservación de volumen (el SMOOTH normal encoge la envolvente)
	s = ob.modifiers.new("smooth", "LAPLACIANSMOOTH"); s.iterations = smooth_iters; s.lambda_factor = 0.6
	s.use_volume_preserve = True
	d = ob.modifiers.new("inflate", "DISPLACE"); d.strength = inflate; d.mid_level = 0.0
	dec = ob.modifiers.new("dec", "DECIMATE"); dec.ratio = decimate
	apply_mods(ob)
	smooth_shade(ob)
	return ob


def delete_faces(ob, pred):
	bm = bmesh.new(); bm.from_mesh(ob.data)
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if pred(f.calc_center_median(), f.normal)], context="FACES")
	bm.to_mesh(ob.data); bm.free()


def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	objs[0].name = name
	return objs[0]


# ───────────────────────────── regiones de Riva ─────────────────────────────

def load_riva():
	if bpy.context.window:   # Blender con interfaz (MCP): escena aparte para no tocar la del usuario
		sc = bpy.data.scenes.get("RivaAccessories") or bpy.data.scenes.new("RivaAccessories")
		bpy.context.window.scene = sc
	else:                    # blender -b --factory-startup
		sc = bpy.context.scene
	for ob in list(sc.objects):
		bpy.data.objects.remove(ob)
	bpy.ops.import_scene.fbx(filepath=FBX)
	sc.frame_set(1)
	return sc, next(o for o in sc.objects if o.type == "MESH")


def region_points(mesh):
	"""Puntos (mundo, pose de enlace) por región, con la misma regla que CharacterLookApplier."""
	names = [g.name for g in mesh.vertex_groups]
	mw = mesh.matrix_world
	out = collections.defaultdict(list)
	for v in mesh.data.vertices:
		if not v.groups:
			continue
		b = names[max(v.groups, key=lambda g: g.weight).group]
		p = mw @ v.co
		if b == "mixamorig:Head":
			out["head"].append(p)
		elif b in ("mixamorig:LeftFoot", "mixamorig:LeftToeBase"):
			out["foot"].append(p)
		elif b == "mixamorig:LeftLeg":
			out["leg"].append(p)
	zmin = min(p.z for p in out["leg"]); zmax = max(p.z for p in out["leg"])
	out["shin"] = [p for p in out["leg"] if p.z <= zmin + SHIN_FRACTION * (zmax - zmin)]
	return out


class Frame:
	"""Caja de una región: convierte entre mundo y coordenadas normalizadas."""
	def __init__(self, pts):
		self.lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
		self.hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
		self.size = self.hi - self.lo
		self.c = (self.lo + self.hi) * 0.5

	def to_unit(self, p):
		return Vector(((p.x - self.c.x) / self.size.x, (p.y - self.c.y) / self.size.y, (p.z - self.lo.z) / self.size.z))

	def from_unit(self, u):
		return Vector((self.c.x + u.x * self.size.x, self.c.y + u.y * self.size.y, self.lo.z + u.z * self.size.z))

	def matrix_to_unit(self):
		return Matrix.Diagonal((1 / self.size.x, 1 / self.size.y, 1 / self.size.z, 1)) @ \
			Matrix.Translation(-Vector((self.c.x, self.c.y, self.lo.z)))


# ───────────────────────────── gorros ─────────────────────────────
# Todo se construye en coordenadas normalizadas de la cabeza: z 0 = cuello, 1 = coronilla (con pelo).

def head_unit_points(regions, fr, zcut):
	return [fr.to_unit(p) for p in regions["head"] if fr.to_unit(p).z > zcut]


def ring(bm, cz, rx, ry, n=32, z_of=None, y_shift=0.0):
	vs = []
	for i in range(n):
		a = 2 * math.pi * i / n
		x, y = math.cos(a) * rx, math.sin(a) * ry + y_shift
		vs.append(bm.verts.new((x, y, z_of(x, y) if z_of else cz)))
	return vs


def bridge(bm, a, b):
	n = len(a)
	for i in range(n):
		bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))


def torus_band(coll, name, z, rx, ry, thick, height, tilt=0.0):
	"""Banda (dobladillo / cinta): tubo de sección rectangular redondeada alrededor de la cabeza."""
	bm = bmesh.new()
	rings = []
	prof = [(-thick * 0.2, -height * 0.5), (thick, -height * 0.45), (thick * 1.1, 0), (thick, height * 0.45), (-thick * 0.2, height * 0.5)]
	for dr, dz in prof:
		rings.append(ring(bm, 0, rx + dr, ry + dr, 40, z_of=lambda x, y, dz=dz: z + dz + tilt * y))
	for i in range(len(rings) - 1):
		bridge(bm, rings[i], rings[i + 1])
	bridge(bm, rings[-1], rings[0])
	ob = new_obj(name, bm, coll)
	sub = ob.modifiers.new("sub", "SUBSURF"); sub.levels = 1
	apply_mods(ob); smooth_shade(ob)
	return ob


def head_radii(pts, z):
	near = [p for p in pts if abs(p.z - z) < 0.06] or pts
	return max(abs(p.x) for p in near), max(abs(p.y) for p in near)


def make_beanie(coll, pts):
	zcut = 0.6
	top = [p for p in pts if p.z > zcut]
	# Copa: envolvente de la parte alta de la cabeza (pelo incluido), abierta por abajo
	dome = hull_blob([Vector((p.x * 1.0, p.y * 1.0, p.z)) for p in top] + [Vector((0, 0, 1.08))],
		"beanie_dome", coll, voxel=0.035, inflate=0.05, smooth_iters=10)
	delete_faces(dome, lambda c, n: c.z < zcut + 0.035)
	rx, ry = head_radii(pts, zcut + 0.06)
	cuff = torus_band(coll, "beanie_cuff", zcut + 0.06, rx + 0.01, ry + 0.01, 0.045, 0.13, tilt=0.1)
	pom = bpy.data.meshes.new("pom")
	bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.12)
	bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0.02, 1.13)); bm.to_mesh(pom); bm.free()
	pom_ob = bpy.data.objects.new("beanie_pom", pom); coll.objects.link(pom_ob); smooth_shade(pom_ob)
	set_mat(dome, ["acc_main"]); set_mat(cuff, ["acc_main"]); set_mat(pom_ob, ["acc_second"])
	# El dobladillo usa el color secundario solo si hay contraste: queda en main por defecto (look de lana)
	cuff.data.materials[0] = mat("acc_second") if False else mat("acc_main")
	return join([dome, cuff, pom_ob], "gorro")


def make_cap(coll, pts, backwards=False):
	zcut = 0.6
	top = [p for p in pts if p.z > zcut]
	dome = hull_blob(top + [Vector((0, 0, 1.03))], "cap_dome", coll, voxel=0.035, inflate=0.06, smooth_iters=10)
	delete_faces(dome, lambda c, n: c.z < zcut + 0.02)
	rx, ry = head_radii(pts, zcut + 0.05)
	# Visera: placa curva que sale por delante (-Y) desde el borde de la copa
	bm = bmesh.new()
	rows, cols = 6, 14
	grid = []
	for r in range(rows + 1):
		t = r / rows
		row = []
		for c in range(cols + 1):
			s = c / cols * 2 - 1
			a = s * math.radians(70)
			x = math.sin(a) * (rx + 0.02 + t * 0.06) * (1 - t * 0.25)
			y = -math.cos(a) * (ry + 0.02) - t * 0.42 * math.cos(a * 0.9)
			z = zcut + 0.05 - t * 0.06 - (s * s) * 0.03
			row.append(bm.verts.new((x, y, z)))
		grid.append(row)
	for r in range(rows):
		for c in range(cols):
			bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
	visor = new_obj("cap_visor", bm, coll)
	so = visor.modifiers.new("solid", "SOLIDIFY"); so.thickness = 0.025
	sub = visor.modifiers.new("sub", "SUBSURF"); sub.levels = 1
	apply_mods(visor); smooth_shade(visor)
	btn = bpy.data.meshes.new("btn")
	bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=0.045)
	bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 1.06)); bm.to_mesh(btn); bm.free()
	btn_ob = bpy.data.objects.new("cap_btn", btn); coll.objects.link(btn_ob); smooth_shade(btn_ob)
	set_mat(dome, ["acc_main"]); set_mat(visor, ["acc_second"]); set_mat(btn_ob, ["acc_second"])
	cap = join([dome, visor, btn_ob], "gorra_atras" if backwards else "gorra")
	if backwards:
		cap.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
	return cap


def make_hat(coll, pts):
	"""Sombrero de ala ancha: copa algo pellizcada, cinta y ala con los bordes levantados."""
	zb = 0.6
	rx, ry = head_radii(pts, zb + 0.08)
	rx += 0.05; ry += 0.05
	bm = bmesh.new()
	prof = [(1.0, zb), (1.02, zb + 0.2), (0.98, zb + 0.42), (0.85, zb + 0.55), (0.45, zb + 0.6), (0.0, zb + 0.58)]
	rings = []
	for k, z in prof:
		pinch = lambda x, y, z=z, k=k: z - (0.07 if k < 0.9 and abs(x) < 0.15 * rx else 0.0)
		rings.append(ring(bm, z, rx * max(k, 0.02), ry * max(k, 0.02), 32, z_of=pinch))
	for i in range(len(rings) - 1):
		bridge(bm, rings[i], rings[i + 1])
	crown = new_obj("hat_crown", bm, coll)
	sub = crown.modifiers.new("sub", "SUBSURF"); sub.levels = 2
	apply_mods(crown); smooth_shade(crown)
	band = torus_band(coll, "hat_band", zb + 0.07, rx + 0.005, ry + 0.005, 0.02, 0.1)
	bm = bmesh.new()
	inner = ring(bm, zb, rx * 0.98, ry * 0.98, 48)
	mid = ring(bm, 0, rx + 0.35, ry + 0.38, 48, z_of=lambda x, y: zb - 0.01 + 0.05 * (x / (rx + 0.35)) ** 2)
	outer = ring(bm, 0, rx + 0.55, ry + 0.58, 48, z_of=lambda x, y: zb + 0.03 + 0.22 * (x / (rx + 0.55)) ** 4)
	bridge(bm, inner, mid); bridge(bm, mid, outer)
	brim = new_obj("hat_brim", bm, coll)
	so = brim.modifiers.new("solid", "SOLIDIFY"); so.thickness = 0.03
	sub = brim.modifiers.new("sub", "SUBSURF"); sub.levels = 1
	apply_mods(brim); smooth_shade(brim)
	set_mat(crown, ["acc_main"]); set_mat(brim, ["acc_main"]); set_mat(band, ["acc_second"])
	return join([crown, brim, band], "sombrero")


# ───────────────────────────── calzado ─────────────────────────────
# Pie: coordenadas normalizadas del pie (z 0 = suelo, 1 = tobillo; -Y = punta).
# Caña: coordenadas normalizadas de la espinilla (z 0 = parte baja de la pierna).

def make_shoe(coll, foot_pts, name, high_sole, toe_cap):
	shoe = hull_blob(foot_pts + [Vector((0, -0.52, 0.05)), Vector((0, 0.5, 0.05))], name + "_foot", coll,
		voxel=0.04, inflate=0.06, smooth_iters=8, decimate=0.4)
	sole_h = high_sole
	# Cortes limpios (bisect) para que el borde suela/puntera sea una línea recta y no dientes de sierra
	toe_n = Vector((0, -1, -0.9)).normalized()
	toe_co = Vector((0, -0.3, 0.2))
	bm = bmesh.new(); bm.from_mesh(shoe.data)
	bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, sole_h), plane_no=(0, 0, 1))
	if toe_cap:
		bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=toe_co, plane_no=toe_n)
	bm.to_mesh(shoe.data); bm.free()
	def assign(c, n):
		if c.z < sole_h:
			return 1                                     # suela
		if toe_cap and (c - toe_co).dot(toe_n) > 0:
			return 2                                     # puntera de goma (converse)
		return 0
	set_mat(shoe, ["acc_main", "acc_sole", "acc_sole"], assign)
	return shoe


def shin_tube(coll, name, shin_pts, z0, z1, margin, flare=0.0):
	"""Caña: tubo elíptico que abraza la espinilla (coordenadas normalizadas de la espinilla)."""
	bm = bmesh.new()
	rings = []
	steps = 6
	for i in range(steps + 1):
		z = z0 + (z1 - z0) * i / steps
		near = [p for p in shin_pts if abs(p.z - z) < 0.12] or shin_pts
		cx = sum(p.x for p in near) / len(near); cy = sum(p.y for p in near) / len(near)
		rx = max(abs(p.x - cx) for p in near) + margin + flare * (i / steps)
		ry = max(abs(p.y - cy) for p in near) + margin + flare * (i / steps)
		vs = ring(bm, z, rx, ry, 28)
		for v in vs:
			v.co.x += cx; v.co.y += cy
		rings.append(vs)
	for i in range(steps):
		bridge(bm, rings[i], rings[i + 1])
	ob = new_obj(name, bm, coll)
	so = ob.modifiers.new("solid", "SOLIDIFY"); so.thickness = 0.04; so.offset = 1
	sub = ob.modifiers.new("sub", "SUBSURF"); sub.levels = 1
	apply_mods(ob); smooth_shade(ob)
	return ob


def make_footwear(coll, reg, fr_foot, fr_shin):
	foot_u = [fr_foot.to_unit(p) for p in reg["foot"]]
	shin_u = [fr_shin.to_unit(p) for p in reg["shin"]]
	out = {}
	boot = make_shoe(coll, foot_u, "botas", 0.12, False)
	shaft = shin_tube(coll, "botas_cana", shin_u, -0.3, 1.0, 0.06, flare=0.03)
	set_mat(shaft, ["acc_main", "acc_second"], lambda c, n: 1 if c.z > 0.9 else 0)   # borde superior
	out["botas"] = (boot, shaft)
	conv = make_shoe(coll, foot_u, "converse", 0.16, True)
	shaft2 = shin_tube(coll, "converse_cana", shin_u, -0.3, 0.42, 0.05)
	set_mat(shaft2, ["acc_main", "acc_sole"], lambda c, n: 1 if c.z > 0.36 else 0)
	out["converse"] = (conv, shaft2)
	return out


# ───────────────────────────── exportación ─────────────────────────────

def export(ob, path):
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.context.view_layer.objects.active = ob
	ob.location = (0, 0, 0)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
		export_animations=False, export_apply=True, export_yup=True, use_active_scene=True)
	print("exported", path, len(ob.data.polygons), "caras")


def run(do_export=True):
	sc, mesh = load_riva()
	reg = region_points(mesh)
	frames = {"head": Frame(reg["head"]), "foot": Frame(reg["foot"]), "shin": Frame(reg["shin"])}
	coll = bpy.data.collections.get("riva_acc") or bpy.data.collections.new("riva_acc")
	if coll.name not in sc.collection.children:
		sc.collection.children.link(coll)
	for ob in list(coll.objects):
		bpy.data.objects.remove(ob)
	head_u = [frames["head"].to_unit(p) for p in reg["head"]]
	items = {
		"gorro": make_beanie(coll, head_u),
		"gorra": make_cap(coll, head_u),
		"gorra_atras": make_cap(coll, head_u, backwards=True),
		"sombrero": make_hat(coll, head_u),
	}
	fw = make_footwear(coll, reg, frames["foot"], frames["shin"])
	for k, (foot, shaft) in fw.items():
		items[k] = foot
		items[k + "_cana"] = shaft
		foot.name = k; shaft.name = k + "_cana"
	if do_export:
		os.makedirs(OUT_DIR, exist_ok=True)
		for k, ob in items.items():
			export(ob, os.path.join(OUT_DIR, k + ".glb"))
	return sc, mesh, reg, frames, items


if __name__ == "__main__":
	run()
