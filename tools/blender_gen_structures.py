"""Genera los modelos low poly de las estructuras goblin (totem, poste de calaveras, choza, tienda, empalizada, fogata, hongo y estalagmita).

Uso (en Blender, con la escena vacía o no): exec(open(".../tools/blender_gen_structures.py").read())
Exporta a assets/models/mapa/*.glb. Cada material lleva el color en el albedo y, si brilla, emisión
(ProceduralMap._flatten_mesh pasa ambos al color de vértice). Origen en el suelo, +Z arriba en Blender.
"""
import bpy, math, random, mathutils

OUT = r"C:/Users/cabeu/Downloads/rumbang-0.1-main/rumbang-0.1-main/assets/models/mapa/"
V = mathutils.Vector

COL = {
    "g_wood": (0.36, 0.22, 0.12), "g_wood_dark": (0.2, 0.12, 0.07), "g_wood_light": (0.5, 0.34, 0.19),
    "g_stone": (0.3, 0.29, 0.28), "g_stone_dark": (0.18, 0.17, 0.17), "g_moss": (0.22, 0.34, 0.16),
    "g_bone": (0.86, 0.82, 0.68), "g_hide": (0.52, 0.4, 0.28), "g_hide_red": (0.62, 0.16, 0.1),
    "g_straw": (0.62, 0.52, 0.28), "g_straw_dark": (0.42, 0.34, 0.18), "g_paint": (0.75, 0.15, 0.12),
    "g_paint_white": (0.9, 0.88, 0.8), "g_dark": (0.05, 0.04, 0.04), "g_iron": (0.22, 0.22, 0.25),
    "g_rope": (0.55, 0.45, 0.3), "g_cap": (0.2, 0.26, 0.36), "g_cap_spot": (0.55, 0.7, 0.75), "g_stem": (0.82, 0.78, 0.7),
    "g_rock": (0.27, 0.25, 0.3), "g_rock_light": (0.36, 0.34, 0.38),
}
GLOW = {"g_glow_green": (0.3, 1.0, 0.45), "g_glow_orange": (1.0, 0.55, 0.15), "g_glow_yellow": (1.0, 0.85, 0.35), "g_glow_cyan": (0.3, 0.9, 1.0)}


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    c = COL.get(name) or GLOW[name]
    b.inputs["Base Color"].default_value = (*c, 1.0)
    b.inputs["Roughness"].default_value = 0.9
    if name in GLOW:
        b.inputs["Emission Color"].default_value = (*c, 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    return m


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


_parts = []


def _fin(o, m, loc, rot, scale):
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    o.scale = scale
    o.data.materials.clear()
    o.data.materials.append(mat(m))
    _parts.append(o)
    return o


def cyl(m, loc, r, h, seg=8, rot=(0, 0, 0), r2=None, scale=(1, 1, 1)):
    """Cilindro/cono truncado con la base en loc (no centrado)."""
    seg = max(seg * 2, 12)          # formas redondeadas (minimalistas), no facetadas
    bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    o = bpy.context.active_object
    o.location = V(loc) + V((0, 0, h / 2))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=False)
    o.location = loc
    # desplazar la geometría para que el origen quede en la base
    for v in o.data.vertices:
        v.co.z += h / 2
    return _fin(o, m, loc, rot, scale)


def box(m, loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    return _fin(o, m, loc, rot, size)


def ico(m, loc, r, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r)
    o = bpy.context.active_object
    return _fin(o, m, loc, rot, scale)


def cone(m, loc, r, h, rot=(0, 0, 0), seg=6):
    return cyl(m, loc, r, h, seg, rot, r2=0.0)


def skull(loc, s=1.0, yaw=0.0):
    ico("g_bone", (loc[0], loc[1], loc[2]), 0.17 * s, (1, 1.05, 0.95), (0, 0, yaw))
    c = math.cos(math.radians(yaw)); sn = math.sin(math.radians(yaw))
    def off(dx, dy, dz):
        return (loc[0] + (dx * c - dy * sn) * s, loc[1] + (dx * sn + dy * c) * s, loc[2] + dz * s)
    box("g_bone", off(0, 0.1, -0.15), (0.16 * s, 0.14 * s, 0.1 * s), (0, 0, yaw))
    for sx in (-1, 1):
        box("g_dark", off(sx * 0.07, 0.15, 0.02), (0.07 * s, 0.05 * s, 0.07 * s), (0, 0, yaw))
    box("g_dark", off(0, 0.17, -0.06), (0.03 * s, 0.03 * s, 0.05 * s), (0, 0, yaw))
    for sx in (-1, 1):
        box("g_glow_orange", off(sx * 0.07, 0.17, 0.02), (0.035 * s, 0.02 * s, 0.035 * s), (0, 0, yaw))


def export(name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.location = (0, 0, 0)
    o.rotation_euler = (0, 0, math.pi)   # las caras miran a -Y (Godot +Z): _yaw_to() apunta ese eje al centro
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.ops.object.shade_smooth()
    em = o.modifiers.new("edge", "EDGE_SPLIT")   # aristas duras solo donde el ángulo es cerrado
    em.split_angle = math.radians(50)
    bpy.ops.export_scene.gltf(filepath=OUT + name + ".glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    print(name, "faces:", len(o.data.polygons))
    _parts.clear()


# ───────────────────────── Tótem (alto 3.4 m) ─────────────────────────
def totem():
    cyl("g_stone", (0, 0, 0), 0.62, 0.22, 8)
    cyl("g_stone_dark", (0, 0, 0.22), 0.5, 0.16, 8)
    for k in range(5):  # piedras sueltas del pie con musgo
        a = k * 1.26
        ico("g_moss" if k % 2 else "g_stone", (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.1), 0.13, (1, 1, 0.7))
    cyl("g_wood", (0, 0, 0.38), 0.3, 2.3, 8, r2=0.34)
    # tres caras talladas, cada una con ceño, ojos verdes brillantes y boca
    for i, z in enumerate((0.75, 1.5, 2.2)):
        s = 1.0 - i * 0.08
        box("g_wood_dark", (0, 0.27, z + 0.2), (0.5 * s, 0.14, 0.1))                 # ceño
        box("g_paint" if i != 1 else "g_paint_white", (0, 0.3, z - 0.05), (0.46 * s, 0.05, 0.12))  # pintura de guerra
        for sx in (-1, 1):
            box("g_dark", (sx * 0.11 * s, 0.3, z + 0.08), (0.12 * s, 0.07, 0.1))
            box("g_glow_green", (sx * 0.11 * s, 0.34, z + 0.08), (0.06, 0.03, 0.06))
        box("g_dark", (0, 0.3, z - 0.2), (0.22 * s, 0.07, 0.12))                    # boca
        for sx in (-0.08, 0, 0.08):
            box("g_bone", (sx * s, 0.34, z - 0.18), (0.04, 0.03, 0.07))           # colmillos
        box("g_wood_light", (0, 0.32, z + 0.0), (0.08, 0.1, 0.22))                  # nariz
    # alas (tablones laterales con plumas)
    box("g_wood_dark", (0, 0, 2.05), (2.2, 0.12, 0.14))
    for sx in (-1, 1):
        for k in range(5):
            x = sx * (0.35 + k * 0.2)
            cone("g_paint" if k % 2 == 0 else "g_paint_white", (x, 0, 2.05), 0.07, 0.5 - k * 0.03, (180, 0, 0), 4)
        ico("g_bone", (sx * 1.08, 0, 2.05), 0.1)
    # cabeza: calavera con cuernos y cristal verde flotante (las almas salen de aquí al romperse)
    ico("g_bone", (0, 0.02, 2.85), 0.3, (1, 0.95, 0.9))
    box("g_bone", (0, 0.24, 2.72), (0.24, 0.1, 0.14))
    for sx in (-1, 1):
        box("g_dark", (sx * 0.12, 0.24, 2.88), (0.12, 0.07, 0.12))
        box("g_glow_green", (sx * 0.12, 0.27, 2.88), (0.06, 0.03, 0.06))
        cone("g_bone", (sx * 0.24, 0, 3.0), 0.07, 0.42, (0, -sx * 28, 0), 5)
    cone("g_glow_green", (0, 0, 3.22), 0.14, 0.4, (0, 0, 0), 4)
    cone("g_glow_green", (0, 0, 3.22), 0.14, -0.25, (0, 0, 0), 4)
    # enredaderas brillantes colgando
    for k, (x, z) in enumerate(((0.3, 1.9), (-0.3, 1.2), (0.28, 0.9))):
        cyl("g_moss", (x, 0.1, z - 0.4), 0.025, 0.5, 4)
        ico("g_glow_green", (x, 0.1, z - 0.42), 0.06)
    export("goblin_totem")


# ───────────────────────── Poste de calaveras (2.8 m) ─────────────────────────
def skull_pole():
    cyl("g_stone_dark", (0, 0, 0), 0.22, 0.14, 6)
    cyl("g_wood", (0, 0, 0.1), 0.07, 2.35, 6, r2=0.06)
    box("g_wood_dark", (0, 0, 1.95), (0.9, 0.08, 0.08))
    box("g_wood_dark", (0, 0, 1.35), (0.55, 0.07, 0.07))
    skull((0, 0, 2.55), 1.15, 0)
    skull((-0.4, 0.0, 1.78), 0.8, 20)
    skull((0.4, 0.0, 1.78), 0.8, -20)
    skull((0, 0.0, 1.15), 0.7, 0)
    cone("g_wood", (0, 0, 2.75), 0.05, 0.3, (0, 0, 0), 4)
    for k, x in enumerate((-0.3, 0.0, 0.3)):                      # tiras de tela roja
        box("g_hide_red", (x, 0.05, 1.2), (0.09, 0.02, 0.4 + 0.08 * k), (0, 0, 0))
    for k in range(4):                                             # huesos atados
        a = k * 1.57 + 0.4
        box("g_bone", (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.7 + k * 0.1), (0.05, 0.05, 0.3), (20, 0, math.degrees(a)))
    box("g_rope", (0, 0, 1.97), (0.12, 0.12, 0.05))
    export("goblin_skull_pole")


# ───────────────────────── Choza (alto 4.2 m, radio 2.3) ─────────────────────────
def hut():
    cyl("g_stone_dark", (0, 0, 0), 2.05, 0.28, 10)                                   # zócalo
    cyl("g_wood", (0, 0, 0.28), 1.85, 1.6, 10, r2=1.78)                               # paredes
    for k in range(10):                                                              # postes verticales
        a = k * math.tau / 10 if hasattr(math, "tau") else k * 6.2832 / 10
        cyl("g_wood_dark", (math.cos(a) * 1.84, math.sin(a) * 1.84, 0.28), 0.1, 1.7, 5)
    cyl("g_wood_dark", (0, 0, 1.75), 1.9, 0.18, 10)                                   # viga superior
    cyl("g_straw_dark", (0, 0, 1.9), 2.35, 0.35, 10, r2=1.9)                          # alero
    cyl("g_straw", (0, 0, 2.2), 2.05, 1.2, 10, r2=1.0)                                # techo
    cyl("g_straw", (0, 0, 3.3), 1.05, 0.9, 10, r2=0.18)
    for k in range(6):                                                               # mechones de paja
        a = k * 1.05
        box("g_straw_dark", (math.cos(a) * 1.5, math.sin(a) * 1.5, 2.4), (0.5, 0.18, 0.1), (0, 0, math.degrees(a) + 90))
    # puerta
    box("g_dark", (0, 1.82, 1.0), (0.85, 0.12, 1.5))
    box("g_wood_dark", (-0.5, 1.88, 1.0), (0.12, 0.14, 1.6))
    box("g_wood_dark", (0.5, 1.88, 1.0), (0.12, 0.14, 1.6))
    box("g_wood_dark", (0, 1.88, 1.82), (1.2, 0.14, 0.12))
    box("g_hide_red", (0.0, 1.95, 1.7), (0.7, 0.04, 0.3))                             # cortina roja
    # ventanas con luz anaranjada
    for ang in (100, 220, 330):
        a = math.radians(ang)
        box("g_glow_orange", (math.cos(a) * 1.86, math.sin(a) * 1.86, 1.1), (0.34, 0.1, 0.34), (0, 0, ang - 90))
        box("g_wood_dark", (math.cos(a) * 1.9, math.sin(a) * 1.9, 1.1), (0.46, 0.08, 0.46), (0, 0, ang - 90))
    # cráneo sobre la puerta y cuernos en la cumbre
    skull((0, 2.0, 1.95), 1.4, 0)
    cyl("g_wood", (0, 0, 4.0), 0.06, 0.5, 5)
    for sx in (-1, 1):
        cone("g_bone", (sx * 0.15, 0, 4.1), 0.07, 0.6, (0, -sx * 35, 0), 5)
    ico("g_bone", (0, 0, 4.0), 0.13)
    # estacas y barriles del lateral
    for k in range(7):
        a = 0.6 + k * 0.38 + 1.9
        cone("g_wood_dark", (math.cos(a) * 2.4, math.sin(a) * 2.4, 0.0), 0.08, 0.9, (0, 0, 0), 4)
    export("goblin_hut")


# ───────────────────────── Tienda (alto 2.7 m) ─────────────────────────
def tent():
    def rad(z):
        return 1.45 - 0.665 * z
    cyl("g_hide", (0, 0, 0), 1.45, 2.0, 8, r2=0.12)
    cyl("g_hide_red", (0, 0, 0.5), rad(0.5) + 0.02, 0.3, 8, r2=rad(0.8) + 0.02)   # banda roja
    cyl("g_rope", (0, 0, 1.15), rad(1.15) + 0.03, 0.07, 8, r2=rad(1.22) + 0.03)
    for k in range(3):                                                           # postes que sobresalen
        a = math.radians(k * 120 + 20)
        cone("g_wood", (0, 0, 1.85), 0.05, 1.0, (14 * math.sin(a), -14 * math.cos(a), 0), 4)
    box("g_dark", (0, 1.0, 0.55), (0.62, 0.08, 1.05), (-22, 0, 0))                # entrada
    ico("g_glow_orange", (0.0, 0.95, 1.2), 0.08)                                  # farolillo
    export("goblin_tent")


# ───────────────────────── Empalizada (3.2 m de largo, 2.4 m alto) ─────────────────────────
def palisade():
    rnd = random.Random(7)
    n = 9
    for k in range(n):
        x = -1.5 + k * (3.0 / (n - 1))
        h = 1.9 + rnd.random() * 0.5
        tilt = (rnd.uniform(-4, 4), rnd.uniform(-3, 3), 0)
        cyl("g_wood" if k % 2 else "g_wood_light", (x, 0, 0), 0.16, h, 6, tilt, r2=0.15)
        cone("g_wood_dark", (x + math.sin(math.radians(tilt[1])) * h * 0.0, 0, h - 0.01), 0.16, 0.38, tilt, 6)
    for z in (0.55, 1.35):
        box("g_wood_dark", (0, 0.2, z), (3.3, 0.1, 0.14))
        box("g_wood_dark", (0, -0.2, z + 0.05), (3.3, 0.1, 0.12))
    for k in range(10):
        box("g_rope", (-1.5 + k * 0.33, 0.27, 0.55), (0.07, 0.05, 0.18))
    skull((0, 0.28, 1.9), 1.0, 0)
    for sx in (-1.5, 1.5):                                                           # contrafuertes
        box("g_wood_dark", (sx, 0.55, 0.5), (0.14, 0.14, 1.1), (-35, 0, 0))
    export("goblin_palisade")


# ───────────────────────── Fogata (0.5 m de alto, radio 0.75) ─────────────────────────
def campfire():
    for k in range(8):                                                 # piedras redondeadas en corona
        a = k * math.tau / 8 + 0.2
        ico("g_rock" if k % 2 else "g_rock_light", (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.12), 0.17, (1.1, 1.0, 0.75))
    for k in range(3):                                                 # troncos cruzados
        cyl("g_wood", (0, 0, 0.12), 0.07, 0.9, 6, (90, 0, k * 60 + 15))
        _parts[-1].location = (0, 0, 0.14)
    ico("g_glow_orange", (0, 0, 0.17), 0.36, (1.0, 1.0, 0.25))           # lecho de brasas (la llama es de partículas)
    export("goblin_campfire")


# ───────────────────────── Hongo luminoso (≈ 0.9 m) ─────────────────────────
def mushroom():
    cyl("g_stem", (0, 0, 0), 0.13, 0.55, 8, r2=0.09)
    ico("g_cap", (0, 0, 0.6), 0.42, (1.0, 1.0, 0.55))
    for k in range(5):                                                 # motas
        a = k * math.tau / 5
        ico("g_cap_spot", (math.cos(a) * 0.27, math.sin(a) * 0.27, 0.72), 0.06, (1, 1, 0.5))
    cyl("g_glow_cyan", (0, 0, 0.57), 0.4, 0.04, 8)                     # aro luminoso bajo el sombrero
    export("mushroom")


# ───────────────────────── Estalagmita (3.2 m) ─────────────────────────
def stalagmite():
    cyl("g_rock", (0, 0, 0), 0.55, 3.0, 8, r2=0.05)
    cyl("g_rock_light", (0.5, 0.25, 0), 0.28, 1.5, 8, r2=0.04)
    cyl("g_rock", (-0.4, -0.3, 0), 0.22, 1.1, 8, r2=0.03)
    ico("g_rock", (0, 0, 0.05), 0.75, (1, 1, 0.3))
    export("cave_stalagmite")


clear(); totem()
clear(); skull_pole()
clear(); hut()
clear(); tent()
clear(); palisade()
clear(); campfire()
clear(); mushroom()
clear(); stalagmite()
print("OK")
