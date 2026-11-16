"""Props de supervivencia estilo cartoon con la TINTA HORNEADA en la textura (sin shader de contorno).

    blender -b --python tools/blender_toon_props.py [-- prop1,prop2]

Reutiliza los constructores de tools/blender/make_map_props.py (árboles, tumbas, ruinas...) y:
  - rehace las rocas como bloques tallados (casco convexo: ~40 triángulos en vez de 320);
  - desenvuelve UVs y hornea (Cycles, CPU) una textura por prop con: color del material, sombreado cel
    (oclusión + luz cenital en bandas), TINTA en las aristas (nodo Bevel: la normal redondeada se aparta
    de la real cerca de una arista), filo de luz, y detalle dibujado (grietas, vetas, motas);
  - exporta <prop>.glb (con UV, materiales solo para marcar lo emisivo) en assets/models/mapa y la
    textura en assets/textures/toon/props/<prop>.png (shader prop_toon, ver ProceduralMap._load_kind).
No toca barrel/crate (son los de dungeon_assets.blend).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_GLB = os.path.join(ROOT, "assets", "models", "mapa")
OUT_TEX = os.path.join(ROOT, "assets", "textures", "toon", "props")
os.makedirs(OUT_TEX, exist_ok=True)

INK = (0.006, 0.005, 0.009)
SAMPLES = 48

# ───────────────────────────── constructores originales ─────────────────────────────
_src = open(os.path.join(ROOT, "tools", "blender", "make_map_props.py"), encoding="utf-8").read()
_src = _src.split("# ---------------------------------------------------------------- generar y exportar")[0]
exec(compile(_src, "make_map_props.py", "exec"))

# Paleta algo más viva que la original (valores lineales)
for key, col in {"stone": (0.15, 0.16, 0.215), "stone_d": (0.085, 0.09, 0.135), "moss": (0.13, 0.27, 0.08),
                 "bark": (0.13, 0.085, 0.06), "bark2": (0.21, 0.155, 0.11), "iron": (0.085, 0.095, 0.13),
                 "cap": (0.42, 0.12, 0.5), "stem": (0.6, 0.55, 0.47)}.items():
    b = next(n for n in M[key].node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)


def toon_rock(name, seed, scale, double):
    """Roca tallada: casco convexo de puntos sobre un elipsoide, base plana y musgo en las caras de arriba."""
    rnd = random.Random(seed)
    bld = B(name, ["stone", "stone_d", "moss"])
    bm = bld.bm

    def lump(center, radii, count, mk):
        before = set(bm.faces)
        vs = []
        for i in range(count):
            d = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
            k = rnd.uniform(0.8, 1.0)
            p = Vector((d.x * radii[0] * k, d.y * radii[1] * k, abs(d.z) * radii[2] * k)) + Vector(center)
            vs.append(bm.verts.new(p))
        for i in range(7):                                  # corona de la base, en el suelo
            a = i * math.tau / 7 + rnd.uniform(-0.25, 0.25)
            vs.append(bm.verts.new(Vector((math.cos(a) * radii[0] * 0.95, math.sin(a) * radii[1] * 0.95, -0.12))
                                   + Vector((center[0], center[1], 0.0))))
        res = bmesh.ops.convex_hull(bm, input=vs)
        junk = list({e for e in res["geom_interior"] + res["geom_unused"] if isinstance(e, bmesh.types.BMVert)})
        if junk:
            bmesh.ops.delete(bm, geom=junk, context='VERTS')
        new = [f for f in bm.faces if f not in before]
        bmesh.ops.recalc_face_normals(bm, faces=new)
        top = max(v.co.z for f in new for v in f.verts)
        for f in new:
            f.material_index = bld.idx[mk]
            if f.normal.z > 0.72 and f.calc_center_median().z > top * 0.7:
                f.material_index = bld.idx["moss"]
        # sin tapa inferior (nunca se ve)
        bmesh.ops.delete(bm, geom=[f for f in new if f.normal.z < -0.9], context='FACES')

    lump((0, 0, 0), (scale * 1.1, scale * 0.9, scale * 1.25), 20, "stone")
    if double:
        lump((scale * 0.85, scale * 0.35, 0), (scale * 0.7, scale * 0.62, scale * 0.8), 14, "stone_d")
    return bld.build()


# ───────────────────────────── material de horneado ─────────────────────────────

def _kind(name):
    n = name.lower()
    if "rock" in n:
        return "stone"
    for k in ("bark", "wood", "stone", "moss", "iron", "bone", "cap", "stem"):
        if k in n:
            return k
    return "plain"


def bake_material(src, image, base=None, emit_color=None, vcol="", local_ao=False, th_default=0.985, imported=False):
    """Emisión = color × cel(oclusión) × cel(luz cenital) × tono, tapado por la tinta.
    imported: material de un .glb importado; su color (base) y su emisión (emit_color o None) vienen leídos
    del archivo, no de los nodos. vcol: atributo de color con oclusión ya horneada (se multiplica a medias).
    local_ao: la oclusión ignora al resto de objetos (piezas sueltas de un prop roto). th_default: umbral
    de tinta de los materiales sin uno propio."""
    bsdf = next(n for n in src.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    if imported:
        emissive = emit_color is not None
    else:
        base = tuple(bsdf.inputs["Base Color"].default_value)[:3]
        emissive = bsdf.inputs["Emission Strength"].default_value > 0.0
        emit_color = tuple(bsdf.inputs["Emission Color"].default_value)[:3]
    kind = _kind(src.name)
    m = bpy.data.materials.new("bake_" + src.name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new

    def math_node(op, a, b=None, clamp=False):
        n = N("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs[0]

    def steps(value, stops):
        """Rampa en escalones (cel): stops = [(pos, gris)]."""
        r = N("ShaderNodeValToRGB")
        r.color_ramp.interpolation = 'CONSTANT'
        els = r.color_ramp.elements
        els[0].position, els[0].color = stops[0][0], (stops[0][1],) * 3 + (1,)
        els[1].position, els[1].color = stops[1][0], (stops[1][1],) * 3 + (1,)
        for pos, g in stops[2:]:
            e = els.new(pos)
            e.color = (g, g, g, 1)
        L(value, r.inputs[0])
        return r.outputs[0]

    def smooth_mask(value, lo, hi):
        """1 por debajo de lo, 0 por encima de hi."""
        mr = N("ShaderNodeMapRange")
        mr.interpolation_type = 'SMOOTHSTEP'
        mr.inputs["From Min"].default_value = lo
        mr.inputs["From Max"].default_value = hi
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        L(value, mr.inputs["Value"])
        return mr.outputs[0]

    out = N("ShaderNodeOutputMaterial")
    emit = N("ShaderNodeEmission")
    L(emit.outputs[0], out.inputs["Surface"])
    img = N("ShaderNodeTexImage")
    img.image = image
    nt.nodes.active = img

    if emissive:
        e = emit_color
        emit.inputs["Color"].default_value = (e[0], e[1], e[2], 1.0)
        return m

    geo = N("ShaderNodeNewGeometry")
    coord = N("ShaderNodeTexCoord")

    # ── tinta en las aristas: normal redondeada (Bevel) frente a la normal real
    def edge_dot(radius):
        bv = N("ShaderNodeBevel")
        bv.samples = 12
        bv.inputs["Radius"].default_value = radius
        dot = N("ShaderNodeVectorMath")
        dot.operation = 'DOT_PRODUCT'
        L(bv.outputs[0], dot.inputs[0])
        L(geo.outputs["True Normal"], dot.inputs[1])
        return dot.outputs["Value"]

    # umbral por material: la corteza solo se entinta en las uniones, no en cada faceta del tronco
    th = {"bark": 0.80, "iron": 0.9, "bone": 0.88}.get(kind, th_default)
    ink = smooth_mask(edge_dot(0.07 if kind in ("stone", "moss") else 0.022), th - 0.035, th)
    sep = N("ShaderNodeSeparateXYZ")
    L(geo.outputs["True Normal"], sep.inputs[0])
    # filo de luz junto a la tinta, solo en caras que miran hacia arriba
    rim = math_node('MULTIPLY', smooth_mask(edge_dot(0.16 if kind in ("stone", "moss") else 0.075), th - 0.02, th + 0.012),
                    math_node('SUBTRACT', 1.0, smooth_mask(sep.outputs["Z"], 0.1, 0.35)))

    # ── sombreado cel horneado: oclusión (incluye el suelo) y luz cenital
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.only_local = local_ao
    ao.inputs["Distance"].default_value = 0.35 if local_ao else 1.1
    shade = math_node('MULTIPLY',
                      steps(ao.outputs["AO"], [(0.0, 0.5), (0.42, 0.74), (0.7, 1.0)]),
                      steps(math_node('ADD', math_node('MULTIPLY', sep.outputs["Z"], 0.5), 0.5),
                            [(0.0, 0.66), (0.36, 0.84), (0.62, 1.0)]))

    # ── detalle dibujado, en metros del objeto (sin costuras de UV)
    tone = None
    lines = None
    if kind in ("stone", "moss"):
        vor = N("ShaderNodeTexVoronoi")
        vor.feature = 'DISTANCE_TO_EDGE'
        vor.inputs["Scale"].default_value = 1.5
        L(coord.outputs["Object"], vor.inputs["Vector"])
        gate = N("ShaderNodeTexNoise")
        gate.inputs["Scale"].default_value = 1.1
        L(coord.outputs["Object"], gate.inputs["Vector"])
        lines = math_node('MULTIPLY', smooth_mask(vor.outputs["Distance"], 0.012, 0.03),
                          math_node('SUBTRACT', 1.0, smooth_mask(gate.outputs["Fac"], 0.56, 0.6)))
        cells = N("ShaderNodeTexVoronoi")
        cells.inputs["Scale"].default_value = 1.5
        L(coord.outputs["Object"], cells.inputs["Vector"])
        sepc = N("ShaderNodeSeparateColor")
        L(cells.outputs["Color"], sepc.inputs[0])
        tone = steps(sepc.outputs[0], [(0.0, 0.88), (0.35, 1.0), (0.72, 1.12)])
        if kind == "moss":
            lines = None
            spots = N("ShaderNodeTexVoronoi")
            spots.inputs["Scale"].default_value = 7.0
            L(coord.outputs["Object"], spots.inputs["Vector"])
            tone = steps(spots.outputs["Distance"], [(0.0, 1.35), (0.22, 1.0), (0.6, 0.86)])
    elif kind in ("bark", "wood"):
        mp = N("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (7.0, 7.0, 0.55)
        L(coord.outputs["Object"], mp.inputs["Vector"])
        grain = N("ShaderNodeTexNoise")
        grain.inputs["Scale"].default_value = 1.0
        grain.inputs["Detail"].default_value = 1.0
        L(mp.outputs[0], grain.inputs["Vector"])
        dist = math_node('ABSOLUTE', math_node('SUBTRACT', grain.outputs["Fac"], 0.5))
        lines = smooth_mask(dist, 0.006, 0.014)
        tone = steps(grain.outputs["Fac"], [(0.0, 0.86), (0.44, 1.0), (0.6, 1.14)])
    elif kind == "cap":
        spots = N("ShaderNodeTexVoronoi")
        spots.inputs["Scale"].default_value = 3.2
        L(coord.outputs["Object"], spots.inputs["Vector"])
        tone = steps(spots.outputs["Distance"], [(0.0, 2.1), (0.2, 1.0)])

    col = N("ShaderNodeRGB")
    col.outputs[0].default_value = (base[0], base[1], base[2], 1.0)
    v = shade
    if tone is not None:
        v = math_node('MULTIPLY', v, tone)
    v = math_node('MULTIPLY', v, math_node('ADD', 1.0, math_node('MULTIPLY', rim, 0.45)))
    if vcol:
        # oclusión que ya traía el modelo en el color de vértice (suelo, mugre): a medias, para no doblarla
        vc = N("ShaderNodeVertexColor")
        vc.layer_name = vcol
        sepv = N("ShaderNodeSeparateColor")
        L(vc.outputs["Color"], sepv.inputs[0])
        v = math_node('MULTIPLY', v, math_node('ADD', 0.5, math_node('MULTIPLY', sepv.outputs[1], 0.5)))
    lit = N("ShaderNodeVectorMath")
    lit.operation = 'SCALE'
    L(col.outputs[0], lit.inputs[0])
    L(v, lit.inputs["Scale"])
    if lines is not None:
        ink = math_node('MAXIMUM', ink, lines)
    mix = N("ShaderNodeMix")
    mix.data_type = 'RGBA'
    L(ink, mix.inputs["Factor"])
    L(lit.outputs[0], mix.inputs["A"])
    mix.inputs["B"].default_value = (INK[0], INK[1], INK[2], 1.0)
    L(mix.outputs["Result"], emit.inputs["Color"])
    return m


# ───────────────────────────── horneado y exportación ─────────────────────────────

def surface_area(ob):
    return sum(p.area for p in ob.data.polygons)


def process(ob, smooth, ground):
    name = ob.name.split(".")[0]
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if smooth:
        bpy.ops.object.shade_smooth()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.015)
    bpy.ops.object.mode_set(mode='OBJECT')

    area = surface_area(ob)
    size = 1024 if area > 28.0 else (512 if area > 5.0 else 256)
    image = bpy.data.images.new(name + "_toon", size, size, alpha=False)
    originals = [s.material for s in ob.material_slots]
    for slot in ob.material_slots:
        slot.material = bake_material(slot.material, image)
    ground.hide_render = False
    bpy.ops.object.bake(type='EMIT', margin=6, use_clear=True)
    for slot, mat_ in zip(ob.material_slots, originals):
        slot.material = mat_
    image.filepath_raw = os.path.join(OUT_TEX, name + ".png")
    image.file_format = 'PNG'
    image.save()
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_GLB, name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True,
                              export_cameras=False, export_lights=False)
    print("TOON", name, "tris", sum(len(p.vertices) - 2 for p in ob.data.polygons), "area %.1f" % area, "tex", size)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[0].split(",") if argv else None
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'                 # la GPU hornea en negro en Blender 5.2 (GTX 1050)
    scene.cycles.samples = SAMPLES
    scene.render.bake.use_selected_to_active = False

    builders = {
        "tree_dead_a": (lambda: dead_tree("tree_dead_a", 1, 6.5, 0.18), True),
        "tree_dead_b": (lambda: dead_tree("tree_dead_b", 7, 5.0, 0.35), True),
        "gravestone_round": (gravestone_round, False),
        "gravestone_cross": (gravestone_cross, False),
        "pillar_broken": (pillar_broken, False),
        "wall_ruin": (wall_ruin, False),
        "rock_a": (lambda: toon_rock("rock_a", 3, 1.3, False), False),
        "rock_b": (lambda: toon_rock("rock_b", 5, 2.0, True), False),
        "brazier": (brazier, False),
        "bone_pile": (bone_pile, False),
        "altar": (altar, False),
        "fence": (fence, False),
        "mushroom": (mushroom, True),
    }
    # suelo para que la oclusión oscurezca el pie de cada prop (no se exporta)
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "bake_ground"
    for name, (fn, smooth) in builders.items():
        if only and name not in only:
            continue
        ob = fn()
        process(ob, smooth, ground)
        bpy.data.objects.remove(ob, do_unlink=True)


if __name__ == "__main__":
    main()
