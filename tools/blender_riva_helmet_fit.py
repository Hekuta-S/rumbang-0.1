"""Ajuste de los cascos (assets/models/riva/cascos/*.glb, ver blender_riva_helmets.py) a la cabeza de Riva.

Calcula para cada casco, SOBRE LA MALLA de riva-base.fbx (pose de enlace), una escala uniforme y un
desplazamiento tales que ningún vértice del casco entre en la cabeza (envolvente convexa de los vértices cuyo
hueso dominante es Head, la misma región que usa CharacterLookApplier) dejando un pequeño margen, y que el casco
quede lo más pegado posible a la coronilla. La altura del borde inferior del casco es una decisión de diseño
(RIM_HEAD_FRACTION: dónde acaba el casco en la cabeza); se admite una holgura vertical pequeña alrededor.

Resultado -> resources/helmet_fit.json, en unidades de la caja de la cabeza (W = ancho X de la región "head"):
    scale  factor sobre W: el casco normalizado (ancho de cúpula = 1) se escala a  scale * W  (uniforme en X/Z)
    stretch  factor extra de altura (1 = uniforme); solo los cascos de cúpula muy plana lo usan
    up     altura del borde inferior del casco sobre el fondo de la caja, en W
    tilt   (opcional, grados; por defecto 0) inclinación hacia delante sobre el eje X del casco, con pivote en su origen
    yaw    (opcional, grados; por defecto 0) giro hacia la DERECHA del personaje sobre la vertical, aplicado tras el tilt.
           En Godot: Basis(Vector3.UP, -deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(tilt))
    fwd    desplazamiento hacia la cara respecto al centro de la caja, en W (en Godot: +Z)
    rim    fracción de la altura de la caja donde se pidió el borde (informativo)
CharacterLookApplier lo coloca: escala k*W, origen (centro.x, caja.y_fondo + up*W, centro.z + fwd*W).
Como el casco cuelga del hueso Head, sigue solo el deslizador de cabeza (el hueso se escala con la piel).

Uso: blender.exe -b --factory-startup --python tools/blender_riva_helmet_fit.py
     (necesita los glb de cascos ya exportados). Con interfaz no hace falta: es todo numérico.
"""
import bpy, bmesh, os, json, sys
import numpy as np
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
FBX = os.path.join(REPO, "assets", "models", "riva", "riva-base.fbx")
HELM_DIR = os.path.join(REPO, "assets", "models", "riva", "cascos")
OUT = os.path.join(REPO, "resources", "helmet_fit.json")
HEAD_BONE = "mixamorig:Head"
SCALE_UP = 1000.0   # el FBX viene en metros/100: se trabaja en milímetros para no perder precisión

CLEARANCE = 0.025   # margen mínimo entre la piel (envolvente) y el casco, en W
# Dónde debe acabar el borde inferior del casco, como fracción de la altura de la caja de la cabeza
# (0 = cuello, ~0.3 = mandíbula, ~0.6 = frente) y holgura vertical permitida alrededor.
RIM_HEAD_FRACTION = {"cruzado": 0.20, "cornudo": 0.36, "vikingo": 0.56, "nordico": 0.36, "fantasia": 0.26,
	"coronado": 0.50}   # coronado: casco cerrado hasta la barbilla; su origen está a media altura (franja de la cúpula)
RIM_SLACK = 0.04
# Margen por casco: negativo = se tolera que el casco se hunda en la envolvente de la cabeza (cascos de pared muy gruesa
# o con huecos para la cara, como el nórdico, cuyo forro interior no se ve).
CLEARANCE_BY = {"nordico": -0.12}
# Mallas del glb que forman el casco propiamente dicho (el resto, p. ej. cuernos, nace DENTRO de la cúpula y no
# debe contar como atravesar la cabeza). Por defecto, todas.
SHELL_MESHES = {"nordico": ["helm_nordico_0"], "vikingo": ["helm_vikingo_1"]}
# Estiramiento vertical permitido (la cúpula del vikingo es muy plana para esta cabeza): factores a probar.
STRETCH = {"vikingo": [1.0, 1.25, 1.5, 1.75, 2.0]}
STRETCH_PENALTY = 0.12   # coste por unidad de estiramiento, en W de hueco
# Punto dentro de la cavidad (coordenadas normalizadas del casco, z = altura) para distinguir caras exteriores de las
# del forro interior: solo se exige que las exteriores no atraviesen la cabeza (el forro puede quedar dentro de la piel).
CAVITY_Z = {"default": 0.4, "vikingo": 0.15, "coronado": 0.0}
# Ajustes a mano (revisados a ojo en Blender sobre la cabeza de Riva) para los cascos cuya geometría confunde al
# solver: el vikingo tiene una cúpula muy plana (se estira en altura) y el nórdico un forro grueso con hueco para la
# cara. Mismas unidades que el JSON; el resto sale del solver.
MANUAL_FIT = {
	"fantasia": {"scale": 1.20, "stretch": 1.0, "up": -0.18, "fwd": 0.06, "tilt": -2.0},   # el solver daba up 0.314: bajado a mano
	"cornudo": {"scale": 1.10, "stretch": 1.3, "up": 0.15, "fwd": -0.34, "tilt": 18.0},   # girado 180°; inclinado hacia delante
	"cruzado": {"scale": 1.12, "stretch": 1.0, "up": -0.22, "fwd": 0.0},   # ranura de la visera a la altura de los ojos
	"vikingo": {"scale": 1.30, "stretch": 1.7, "up": 0.85, "fwd": 0.0},   # cúpula plana estirada; el borde queda sobre las cejas
	"nordico": {"scale": 1.36, "stretch": 1.3, "up": -0.12, "fwd": -0.42, "tilt": 22.0, "yaw": 2.5},   # enderezado 8° en blender_riva_helmets.py; ranuras a la altura de los ojos
}
HIDES_HAIR = {"cruzado": True, "cornudo": True, "vikingo": True, "nordico": True, "fantasia": True, "coronado": True}
K_RANGE = (0.9, 2.6, 0.02)
FWD_RANGE = (-0.2, 0.2, 0.02)


def load_riva():
	for o in list(bpy.context.scene.objects):
		bpy.data.objects.remove(o)
	bpy.ops.import_scene.fbx(filepath=FBX)
	bpy.context.scene.frame_set(1)
	return next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("RivaBase"))


def head_points(mesh):
	names = [g.name for g in mesh.vertex_groups]
	mw = mesh.matrix_world
	pts = []
	for v in mesh.data.vertices:
		if v.groups and names[max(v.groups, key=lambda g: g.weight).group] == HEAD_BONE:
			pts.append(np.array(mw @ v.co) * SCALE_UP)
	return np.array(pts)


def hull_planes(pts):
	bm = bmesh.new()
	for p in pts[::3]:
		bm.verts.new(Vector(p))
	bmesh.ops.convex_hull(bm, input=bm.verts)
	n, d = [], []
	for f in bm.faces:
		c = np.array(f.calc_center_median())
		nn = np.array(f.normal)
		n.append(nn)
		d.append(float(nn @ c))
	bm.free()
	return np.array(n), np.array(d)


def helmet_verts(path, only=None, cavity_z=0.4):
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	objs = [o for o in bpy.context.scene.objects if o not in before]
	out = []
	ref = np.array([0.0, 0.0, cavity_z])
	for o in objs:
		if o.type == "MESH" and (only is None or o.name in only):
			mw = np.array(o.matrix_world)
			co = np.array([tuple(v.co) for v in o.data.vertices]) @ mw[:3, :3].T + mw[:3, 3]
			keep = set()
			for p in o.data.polygons:
				n = np.array(p.normal) @ mw[:3, :3].T
				c = co[list(p.vertices)].mean(axis=0)
				if float((c - ref) @ n) > 0.0:   # cara exterior (mira lejos de la cavidad)
					keep.update(p.vertices)
			out.append(co[sorted(keep)])
	for o in objs:
		bpy.data.objects.remove(o)
	return np.vstack(out)


def fit_one(hid, hv, head, planes, lo, hi):
	W = hi[0] - lo[0]
	H = hi[2] - lo[2]
	cx, cy = (lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5
	N, D = planes
	clear = CLEARANCE_BY.get(hid, CLEARANCE) * W
	crown = head[head[:, 2] >= lo[2] + 0.6 * H][::4]
	hv_s = hv[::max(1, len(hv) // 1800)]
	ks = np.arange(K_RANGE[0], K_RANGE[1] + 1e-9, K_RANGE[2])
	S = (ks * W)[:, None, None]
	rim0 = RIM_HEAD_FRACTION[hid]
	best = None
	for zs in STRETCH.get(hid, [1.0]):
		vs = hv_s * np.array([1.0, 1.0, zs])
		A = vs @ N.T                    # (V, P): n_p . v
		for up_f in np.arange(rim0 - RIM_SLACK, rim0 + RIM_SLACK + 1e-9, 0.02):
			oz = lo[2] + up_f * H
			for fwd in np.arange(FWD_RANGE[0], FWD_RANGE[1] + 1e-9, FWD_RANGE[2]):
				o = np.array([cx, cy - fwd * W, oz])
				B = N @ o - D                                  # (P,)
				dout = (S * A[None] + B[None, None, :]).max(axis=2)   # (K, V): distancia fuera de la envolvente
				ok = dout.min(axis=1) >= clear
				if not ok.any():
					continue
				ki = int(np.argmax(ok))                        # menor escala válida
				k = ks[ki]
				pts = vs * (k * W) + o
				dist = np.sqrt(((crown[:, None, :] - pts[None, :, :]) ** 2).sum(axis=2)).min(axis=1)
				gap = float(dist.mean() / W)
				cost = gap + STRETCH_PENALTY * (zs - 1.0)
				if best is None or cost < best["cost"]:
					best = {"cost": cost, "gap": gap, "k": float(k), "zs": zs, "up_f": float(up_f), "fwd": float(fwd), "o": o}
	if best is None:
		return None
	# afinar la escala entre la anterior inválida y la válida
	o, zs = best["o"], best["zs"]
	A = (hv_s * np.array([1.0, 1.0, zs])) @ N.T
	B = N @ o - D
	k = best["k"]
	for kk in np.arange(k - K_RANGE[2], k + 1e-9, 0.004):
		dmin = (kk * W * A + B[None, :]).max(axis=1).min()
		if dmin >= clear:
			k = float(kk)
			break
	up = (o[2] - lo[2]) / W
	return {"scale": round(k, 3), "stretch": round(float(zs), 2), "up": round(float(up), 3), "fwd": round(best["fwd"], 3),
		"rim": round(rim0, 2), "hides_hair": HIDES_HAIR[hid], "_gap": round(best["gap"], 3)}


def run():
	mesh = load_riva()
	head = head_points(mesh)
	lo, hi = head.min(axis=0), head.max(axis=0)
	planes = hull_planes(head)
	print("[fit] cabeza W=%.3f D=%.3f H=%.3f  (mm)  hull planos=%d" % (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], len(planes[1])))
	only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	result = {}
	if only and os.path.exists(OUT):
		with open(OUT, encoding="utf-8") as f:
			result = json.load(f)
	for hid in RIM_HEAD_FRACTION:
		if only and hid not in only:
			continue
		if hid in MANUAL_FIT:
			result[hid] = dict(MANUAL_FIT[hid], rim=RIM_HEAD_FRACTION[hid], hides_hair=HIDES_HAIR[hid])
			print("[fit]", hid, "(manual)", result[hid])
			continue
		hv = helmet_verts(os.path.join(HELM_DIR, hid + ".glb"), SHELL_MESHES.get(hid), CAVITY_Z.get(hid, CAVITY_Z["default"]))
		r = fit_one(hid, hv, head, planes, lo, hi)
		print("[fit]", hid, r)
		if r:
			result[hid] = r
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	with open(OUT, "w", encoding="utf-8") as f:
		json.dump({k: {a: b for a, b in v.items() if not a.startswith("_")} for k, v in result.items()}, f, indent=1)
		f.write("\n")
	return result


if __name__ == "__main__":
	run()
