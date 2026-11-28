"""Blender headless: exporta enemigos decimados y la R (entera y cortada) a JSON para el desdoblador."""
import bpy, bmesh, json, sys, os
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MODE = ARGS[0] if ARGS else "enemies"


def mat_color(m):
    if m is None:
        return [0.6, 0.6, 0.6]
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                inp = n.inputs[0]
                if not inp.is_linked:
                    return list(inp.default_value)[:3]
                src = inp.links[0].from_node
                if src.type == "RGB":
                    return list(src.outputs[0].default_value)[:3]
                if src.type == "VALTORGB":
                    return list(src.color_ramp.elements[-1].color)[:3]
        for n in m.node_tree.nodes:
            if n.type == "RGB":
                return list(n.outputs[0].default_value)[:3]
            if n.type in ("BSDF_DIFFUSE", "EMISSION"):
                return list(n.inputs[0].default_value)[:3]
    return list(m.diffuse_color)[:3]


def to_srgb(c):
    out = []
    for v in c:
        v = max(0.0, min(1.0, v))
        out.append(v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055)
    return out


def dump(name, bm, colors_of_face, scale):
    bm.verts.index_update()
    verts = [list(v.co * scale) for v in bm.verts]
    faces, cols = [], []
    for f in bm.faces:
        faces.append([v.index for v in f.verts])
        cols.append(colors_of_face(f))
    with open(os.path.join(OUT, name + ".json"), "w") as fh:
        json.dump({"verts": verts, "faces": faces, "colors": cols}, fh)
    print("SAVED", name, len(verts), len(faces))


def enemy(obj_name, target_faces, out_name, length_mm):
    obj = bpy.data.objects[obj_name]
    if obj.parent and obj.parent.type == "ARMATURE":
        obj.parent.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    me.transform(obj.matrix_world)
    mats = [mat_color(m) for m in obj.data.materials]
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    # partes sueltas
    bm.faces.ensure_lookup_table()
    seen, parts = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, comp = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        parts.append(comp)
    allv = [v.co for v in bm.verts]
    lo = Vector([min(c[i] for c in allv) for i in range(3)])
    hi = Vector([max(c[i] for c in allv) for i in range(3)])
    size = (hi - lo).length
    decals, keep = [], set()
    for comp in parts:
        vs = {v for f in comp for v in f.verts}
        c = sum((v.co for v in vs), Vector()) / len(vs)
        r = max((v.co - c).length for v in vs)
        # color dominante por área
        acc = {}
        for f in comp:
            acc[f.material_index] = acc.get(f.material_index, 0) + f.calc_area()
        mi = max(acc, key=acc.get)
        if r < size * 0.07:
            decals.append((r, list(c), mats[mi] if mi < len(mats) else [0, 0, 0]))
        else:
            keep.update(f.index for f in comp)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(me)
    bm.free()
    tmp = bpy.data.objects.new("tmp_" + out_name, me)
    bpy.context.scene.collection.objects.link(tmp)
    mod = tmp.modifiers.new("dec", "DECIMATE")
    mod.ratio = min(1.0, target_faces / max(1, len(me.polygons)) / 2.0 * 1.0)
    # triangula al decimar: ratio sobre triángulos
    tri_count = sum(len(p.vertices) - 2 for p in me.polygons)
    mod.ratio = min(1.0, target_faces / tri_count)
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me2)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    # pinta las calcomanías (ojos, dientes...) sobre las caras cercanas; grandes primero
    bm.faces.ensure_lookup_table()
    fcol = {f.index: (mats[f.material_index] if f.material_index < len(mats) else [0.5, 0.5, 0.5]) for f in bm.faces}
    for r, c, col in sorted(decals, key=lambda d: -d[0]):
        c = Vector(c)
        best = sorted(bm.faces, key=lambda f: (f.calc_center_median() - c).length)
        hit = [f for f in best if (f.calc_center_median() - c).length < max(r * 1.6, size * 0.025)]
        if not hit:
            hit = best[:1]
        for f in hit:
            fcol[f.index] = col
    # escala: longitud mayor = length_mm
    vs = [v.co for v in bm.verts]
    lo = Vector([min(c[i] for c in vs) for i in range(3)])
    hi = Vector([max(c[i] for c in vs) for i in range(3)])
    ext = hi - lo
    scale = length_mm / max(ext)
    for v in bm.verts:
        v.co = v.co - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    dump(out_name, bm, lambda f: to_srgb(fcol[f.index]), scale)
    print("EXT", out_name, [round(e * scale) for e in ext], "decals", len(decals), "parts", len(parts))


def letter_r(height_mm, depth_mm, cut_frac):
    cu = bpy.data.curves.new("R", "FONT")
    cu.body = "R"
    cu.font = bpy.data.fonts.load(r"C:\Windows\Fonts\impact.ttf")
    cu.extrude = 0.5
    cu.resolution_u = 3
    ob = bpy.data.objects.new("R", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    vs = [v.co for v in bm.verts]
    lo = Vector([min(c[i] for c in vs) for i in range(3)])
    hi = Vector([max(c[i] for c in vs) for i in range(3)])
    sy = height_mm / (hi.y - lo.y)
    sz = depth_mm / (hi.z - lo.z)
    for v in bm.verts:
        v.co = Vector(((v.co.x - lo.x) * sy, (v.co.z - lo.z) * sz - depth_mm / 2, (v.co.y - lo.y) * sy))
    # ahora: x ancho, y profundidad, z alto (frente mira a -y)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.02, verts=bm.verts, edges=bm.edges)
    width = (hi.x - lo.x) * sy
    print("R size", round(width), height_mm, depth_mm)

    def col(f):
        n = f.normal
        if abs(n.y) > 0.9:
            return [1.0, 0.82, 0.22]          # cara frontal / trasera: amarillo
        if getattr(f, "tag", False):
            return [0.15, 0.1, 0.2]
        return [0.93, 0.45, 0.12]             # costados: naranja

    whole = bm.copy()
    bmesh.ops.triangulate(whole, faces=whole.faces)
    dump("R_entera", whole, lambda f: [0.15, 0.1, 0.2] if False else col(f), 1.0)
    xcut = width * cut_frac
    for side in ("izq", "der"):
        b = bm.copy()
        geom = b.verts[:] + b.edges[:] + b.faces[:]
        res = bmesh.ops.bisect_plane(b, geom=geom, dist=1e-4, plane_co=(xcut, 0, 0), plane_no=(1, 0, 0),
                                     clear_outer=(side == "izq"), clear_inner=(side == "der"))
        cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        before = set(b.faces)
        bmesh.ops.edgenet_fill(b, edges=cut_edges) if False else bmesh.ops.holes_fill(b, edges=cut_edges, sides=0)
        for f in b.faces:
            f.tag = f not in before
        b.normal_update()
        capped = [f for f in b.faces if f.tag]
        bmesh.ops.triangulate(b, faces=b.faces)
        for f in b.faces:
            f.tag = abs(f.normal.x) > 0.99 and abs(f.calc_center_median().x - xcut) < 0.01
        dump("R_" + side, b, col, 1.0)
        print("cap faces", side, len(capped))


if MODE == "enemies":
    enemy("RatMesh", 300, "rata", 240.0)
    enemy("BloaterMesh", 260, "hinchado", 200.0)
else:
    letter_r(160.0, 35.0, float(ARGS[1]) if len(ARGS) > 1 else 0.42)
