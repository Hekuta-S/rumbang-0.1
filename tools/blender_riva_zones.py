"""Hornea la máscara de zonas de Riva (assets/textures/entities/riva/riva_zones.png).

Cada cara de la malla se asigna a una REGIÓN del cuerpo (hueso dominante + color de textura +
posición). La región se escribe en el canal R (id / 15) de una imagen en espacio UV; el shader
riva_custom.gdshader la lee (filtro nearest) y, junto con la clase de color del texel (oscuro,
naranja, blanco, piel), decide qué color personalizable aplicar.

Uso (Blender 5.2, sin MCP):
  blender.exe -b --python tools/blender_riva_zones.py
o desde el MCP: exec(open(r"<repo>/tools/blender_riva_zones.py").read())
"""
import bpy, numpy as np, colorsys, collections, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else \
	r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
FBX = os.path.join(REPO, "assets", "models", "riva", "riva-idle.fbx")
TEX = os.path.join(REPO, "assets", "textures", "entities", "riva", "texture_riva.png")
OUT = os.path.join(REPO, "assets", "textures", "entities", "riva", "riva_zones.png")
RES = 1024

# Regiones (deben coincidir con riva_custom.gdshader / CharacterLook)
HAIR, FACE, MASK, TORSO, HANDS, UPLEG, LOWLEG, FEET, FOREARM = 1, 2, 3, 4, 5, 6, 7, 8, 9
DEBUG_COLORS = {HAIR: (0.1, 0.1, 0.1), FACE: (1, 0.8, 0.6), MASK: (1, 0, 1), TORSO: (0, 0, 1),
	HANDS: (1, 1, 0), FOREARM: (0, 1, 1), UPLEG: (0, 1, 0), LOWLEG: (0, 0.5, 0), FEET: (1, 0, 0)}

BONE_REGION = {}
for side in ("Left", "Right"):
	BONE_REGION["mixamorig:%sHand" % side] = HANDS
	BONE_REGION["mixamorig:%sForeArm" % side] = FOREARM
	for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
		for i in (1, 2, 3):
			BONE_REGION["mixamorig:%sHand%s%d" % (side, f, i)] = HANDS
	BONE_REGION["mixamorig:%sUpLeg" % side] = UPLEG
	BONE_REGION["mixamorig:%sLeg" % side] = LOWLEG
	BONE_REGION["mixamorig:%sFoot" % side] = FEET
	BONE_REGION["mixamorig:%sToeBase" % side] = FEET
BONE_REGION["mixamorig:Head"] = FACE


def load_riva():
	if bpy.context.window:   # Blender con interfaz (MCP): escena aparte para no tocar la del usuario
		sc = bpy.data.scenes.get("RivaZones") or bpy.data.scenes.new("RivaZones")
		bpy.context.window.scene = sc
	else:                    # blender -b --factory-startup
		sc = bpy.context.scene
	for ob in list(sc.objects):
		bpy.data.objects.remove(ob)
	bpy.ops.import_scene.fbx(filepath=FBX)
	sc.frame_set(1)
	mesh = next(ob for ob in sc.objects if ob.type == "MESH")
	arm = next(ob for ob in sc.objects if ob.type == "ARMATURE")
	return sc, mesh, arm


def texture_pixels():
	img = bpy.data.images.load(TEX, check_existing=True)
	small = img.copy()
	small.scale(RES, RES)
	px = np.empty(RES * RES * 4, np.float32)
	small.pixels.foreach_get(px)
	bpy.data.images.remove(small)
	return img, px.reshape(RES, RES, 4)


def classify(mesh, arm, px):
	me = mesh.data
	uv = me.uv_layers.active.data
	mw = mesh.matrix_world
	names = [g.name for g in mesh.vertex_groups]
	dom = []
	for v in me.vertices:
		best = max(v.groups, key=lambda g: g.weight) if v.groups else None
		dom.append(names[best.group] if best else "")
	head = arm.matrix_world @ arm.pose.bones["mixamorig:Head"].head
	top = arm.matrix_world @ arm.pose.bones["mixamorig:HeadTop_End"].head
	hh = top.z - head.z                       # altura cabeza (cuello -> coronilla)
	mask_lo, mask_hi = head.z + 0.06 * hh, head.z + 0.33 * hh
	regions = []
	for p in me.polygons:
		bone = collections.Counter(dom[v] for v in p.vertices).most_common(1)[0][0]
		r = BONE_REGION.get(bone, TORSO)
		if r == FACE:
			us = [uv[li].uv for li in p.loop_indices]
			u = sum(x[0] for x in us) / len(us); w = sum(x[1] for x in us) / len(us)
			col = px[min(RES - 1, int(w * RES)), min(RES - 1, int(u * RES)), :3]
			_h, s, val = colorsys.rgb_to_hsv(*col)
			cen = mw @ p.center
			in_mask = mask_lo < cen.z < mask_hi and cen.y < head.y + 0.1 * hh
			skin = 0.12 < s < 0.55 and val > 0.45
			if in_mask and not skin:
				r = MASK
			elif cen.z < mask_lo:
				r = TORSO                          # cuello / camiseta bajo la capucha
			elif val < 0.32 and not in_mask:
				r = HAIR
		regions.append(r)
	return regions


def bake(mesh, regions, debug=False):
	me = mesh.data
	attr = me.color_attributes.get("region") or me.color_attributes.new("region", "BYTE_COLOR", "CORNER")
	data = attr.data
	for p, r in zip(me.polygons, regions):
		c = DEBUG_COLORS[r] if debug else (r / 15.0, 0.0, 0.0)
		for li in p.loop_indices:
			data[li].color = (c[0], c[1], c[2], 1.0)
	mat = bpy.data.materials.get("RivaZoneBake") or bpy.data.materials.new("RivaZoneBake")
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	em = nt.nodes.new("ShaderNodeEmission")
	ca = nt.nodes.new("ShaderNodeVertexColor"); ca.layer_name = "region"
	nt.links.new(ca.outputs[0], em.inputs[0])
	nt.links.new(em.outputs[0], out.inputs[0])
	me.materials.clear(); me.materials.append(mat)
	return mat


def bake_to_image(sc, mesh, mat):
	img = bpy.data.images.get("riva_zones") or bpy.data.images.new("riva_zones", RES, RES, alpha=False)
	img.colorspace_settings.name = "Non-Color"
	tn = mat.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = img
	mat.node_tree.nodes.active = tn
	try:
		sc.render.engine = "CYCLES"
	except TypeError as e:
		print(e)
	sc.cycles.device = "CPU"
	sc.cycles.samples = 1
	sc.render.bake.margin = 8
	sc.render.bake.use_clear = True
	bpy.ops.object.select_all(action="DESELECT")
	mesh.hide_set(False); mesh.select_set(True)
	bpy.context.view_layer.objects.active = mesh
	bpy.ops.object.bake(type="EMIT")
	img.filepath_raw = OUT
	img.file_format = "PNG"
	img.save()
	print("saved", OUT)


def run(debug=False):
	sc, mesh, arm = load_riva()
	_img, px = texture_pixels()
	regions = classify(mesh, arm, px)
	print("regiones:", collections.Counter(regions))
	mat = bake(mesh, regions, debug)
	if not debug:
		bake_to_image(sc, mesh, mat)
	return sc, mesh, arm


if __name__ == "__main__":
	run(debug=bool(os.environ.get("RIVA_ZONES_DEBUG")))
