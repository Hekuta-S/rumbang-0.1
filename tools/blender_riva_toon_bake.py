"""Hornea el sombreado cartoon y la TINTA de la piel del personaje (riva-base.fbx) en su propia UV.

    blender -b --factory-startup --python tools/blender_riva_toon_bake.py [-- info]

Sale un mapa en gris (assets/textures/entities/riva/humano/_piel_bake.png, 2048 px) con:
  - sombra cel de la oclusión ancha (axilas, entrepierna, cuello) y de las caras que miran al suelo
    (bajo la barbilla, pectorales, glúteos);
  - tinta donde la oclusión CERRADA es fuerte (entre los dedos, labios, fosas nasales, párpados, orejas,
    ombligo): el canal G lleva la tinta y el R el sombreado.
tools/make_riva_toon_textures.py lo combina con piel.png y la máscara de cejas en piel_toon.png (una sola
lectura en riva_skin.gdshader). Con "info" solo lista mallas y materiales.
"""
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FBX = os.path.join(ROOT, "assets", "models", "riva", "riva-base.fbx")
OUT = os.path.join(ROOT, "assets", "textures", "entities", "riva", "humano", "_piel_bake.png")
SIZE = 2048
BAKED = ("rb_Piel", "rb_Calzones", "rb_Elastico")      # comparten la UV del cuerpo


def bake_material(image):
    m = bpy.data.materials.new("bake_piel")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new

    def steps(value, stops):
        r = N("ShaderNodeValToRGB")
        r.color_ramp.interpolation = 'EASE'
        els = r.color_ramp.elements
        els[0].position, els[0].color = stops[0][0], (stops[0][1],) * 3 + (1,)
        els[1].position, els[1].color = stops[1][0], (stops[1][1],) * 3 + (1,)
        for pos, g in stops[2:]:
            e = els.new(pos)
            e.color = (g, g, g, 1)
        L(value, r.inputs[0])
        return r.outputs[0]

    out = N("ShaderNodeOutputMaterial")
    emit = N("ShaderNodeEmission")
    L(emit.outputs[0], out.inputs["Surface"])
    img = N("ShaderNodeTexImage")
    img.image = image
    nt.nodes.active = img

    wide = N("ShaderNodeAmbientOcclusion")
    wide.samples = 16
    wide.only_local = True
    wide.inputs["Distance"].default_value = 0.22
    tight = N("ShaderNodeAmbientOcclusion")
    tight.samples = 16
    tight.only_local = True
    tight.inputs["Distance"].default_value = 0.028
    geo = N("ShaderNodeNewGeometry")
    sep = N("ShaderNodeSeparateXYZ")
    L(geo.outputs["Normal"], sep.inputs[0])

    # R: sombra en dos escalones (oclusión ancha) × sombra de las caras hacia abajo
    shade_ao = steps(wide.outputs["AO"], [(0.0, 0.62), (0.5, 0.62), (0.56, 0.82), (0.72, 0.82), (0.78, 1.0)])
    shade_dn = steps(sep.outputs["Z"], [(0.0, 0.8), (0.2, 0.8), (0.27, 1.0)])     # Z de -1..1 → rampa en 0..1
    mp = N("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -1.0
    mp.inputs["From Max"].default_value = 1.0
    L(sep.outputs["Z"], mp.inputs["Value"])
    nt.links.remove(shade_dn.node.inputs[0].links[0])
    L(mp.outputs[0], shade_dn.node.inputs[0])
    mul = N("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    L(shade_ao, mul.inputs[0])
    L(shade_dn, mul.inputs[1])
    # G: tinta de los pliegues cerrados
    ink = steps(tight.outputs["AO"], [(0.0, 1.0), (0.5, 1.0), (0.66, 0.0)])
    comb = N("ShaderNodeCombineColor")
    L(mul.outputs[0], comb.inputs[0])
    L(ink, comb.inputs[1])
    comb.inputs[2].default_value = 0.0
    L(comb.outputs[0], emit.inputs["Color"])
    return m


def dummy_material():
    """Los materiales con otra UV (ojos, cejas, pestañas) hornean a una imagen que se tira."""
    img = bpy.data.images.new("bake_dummy", 8, 8)
    m = bpy.data.materials.new("bake_dummy")
    m.use_nodes = True
    n = m.node_tree.nodes.new("ShaderNodeTexImage")
    n.image = img
    m.node_tree.nodes.active = n
    return m


def main():
    info = "info" in sys.argv
    bpy.ops.import_scene.fbx(filepath=FBX)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in meshes:
        print("MESH", o.name, len(o.data.polygons), [s.material.name if s.material else None for s in o.material_slots],
              [uv.name for uv in o.data.uv_layers])
    if info:
        return
    body = next(o for o in meshes if any(s.material and s.material.name.startswith("rb_Piel") for s in o.material_slots))
    arm = body.find_armature()
    if arm:
        arm.data.pose_position = 'REST'
    for o in meshes:
        o.hide_render = o is not body               # el pelo y los accesorios no dan sombra a la piel
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 96
    image = bpy.data.images.new("piel_bake", SIZE, SIZE, alpha=False)
    image.colorspace_settings.name = 'Non-Color'
    bm = bake_material(image)
    dm = dummy_material()
    for slot in body.material_slots:
        name = slot.material.name if slot.material else ""
        slot.material = bm if name.startswith(BAKED) else dm
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type='EMIT', margin=12, use_clear=True)
    image.filepath_raw = OUT
    image.file_format = 'PNG'
    image.save()
    print("BAKED", OUT)


main()
