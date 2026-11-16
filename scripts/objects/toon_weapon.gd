class_name ToonWeapon
extends RefCounted

## Pasa los materiales de un arma (los StandardMaterial3D que trae su .glb) al estilo cartoon barato:
## la textura de color se cambia por su versión con la tinta y el relieve HORNEADOS
## (res://assets/textures/toon/weapons/<mismo nombre>.png, de tools/toonify_weapon_textures.py) y se apagan
## normal map, metal/rugosidad, oclusión y especular: una sola lectura de textura por material.
## El recurso del material es compartido por todas las instancias del arma: se convierte una sola vez.

const TEX_DIR := "res://assets/textures/toon/weapons/"

## false: armas con sus materiales PBR originales (comparar con tests/shot_toon_weapons.tscn)
static var enabled := true

static func apply(root: Node) -> void:
	if not enabled or root == null:
		return
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null and not m.has_meta("toon"):
				_convert(m)

static func _convert(m: BaseMaterial3D) -> void:
	m.set_meta("toon", true)
	var tex := m.albedo_texture
	if tex != null and tex.resource_path != "":
		var path := TEX_DIR + tex.resource_path.get_file().get_basename() + ".png"
		if ResourceLoader.exists(path):
			m.albedo_texture = load(path)
	m.normal_enabled = false
	m.ao_enabled = false
	m.heightmap_enabled = false
	m.clearcoat_enabled = false
	m.anisotropy_enabled = false
	m.rim_enabled = false
	m.metallic = 0.0
	m.metallic_texture = null
	m.roughness = 1.0
	m.roughness_texture = null
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
