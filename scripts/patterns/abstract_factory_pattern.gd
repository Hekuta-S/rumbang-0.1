class_name PlatformFactory extends RefCounted

## FALENCIA DETECTADA EN EL PROYECTO (RESUELTA):
## Lógica condicional esparcida por el código (ej. if OS.get_name() in ["Android", "iOS"] 
## en main.gd) para cambiar configuraciones de la plataforma. Esto mezcla 
## reglas de negocio con detalles de plataforma, rompiendo Open/Closed.

## Abstract Factory
## Provee una interfaz para crear y configurar familias de objetos (gráficos, controles)
## sin especificar sus clases concretas en la lógica principal.

# --- Interfaz Base ---
func configure_environment(env: Environment) -> void:
	pass

func configure_viewport(viewport: Viewport) -> void:
	pass

func configure_light(light: DirectionalLight3D) -> void:
	pass

func create_controls() -> Node:
	return null

func create_map(parent_node: Node3D) -> void:
	pass

# --- Método estático para obtener la fábrica correcta ---
static func get_factory() -> PlatformFactory:
	if OS.get_name() in ["Android", "iOS"]:
		return MobilePlatformFactory.new()
	else:
		return DesktopPlatformFactory.new()

# --- Familias Concretas ---

class MobilePlatformFactory extends PlatformFactory:
	func configure_environment(env: Environment) -> void:
		env.volumetric_fog_enabled = false
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		env.glow_enabled = false # Evita crashes en Vulkan móvil
		env.fog_enabled = true
		env.fog_density = 0.015
		
	func configure_viewport(viewport: Viewport) -> void:
		# Reduce resolución 3D al 65% para mejor rendimiento en móvil
		viewport.scaling_3d_scale = 0.65
		
	func configure_light(light: DirectionalLight3D) -> void:
		light.shadow_enabled = false # Sombras 3D causan picos en móvil

	func create_controls() -> Node:
		var mobile_script = load("res://scripts/ui/mobile_controls.gd")
		if mobile_script:
			return mobile_script.new()
		return null
		
	func create_map(parent_node: Node3D) -> void:
		# Móvil sigue usando el mapa predeterminado (no lo tocamos)
		pass


class DesktopPlatformFactory extends PlatformFactory:
	func configure_environment(env: Environment) -> void:
		env.volumetric_fog_enabled = ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus"
		env.fog_enabled = false
		
	func configure_viewport(viewport: Viewport) -> void:
		viewport.scaling_3d_scale = 1.0
		
	func configure_light(light: DirectionalLight3D) -> void:
		light.shadow_enabled = true
		
	func create_controls() -> Node:
		# En PC no creamos controles táctiles, devolvemos null
		return null

	func create_map(parent_node: Node3D) -> void:
		# En PC borramos el mapa gigante inestable y lo cambiamos por uno plano de 200x200
		var old_terrain = parent_node.get_node_or_null("TerrainCSG")
		if old_terrain:
			old_terrain.queue_free()
			
		var flat_map = CSGBox3D.new()
		flat_map.name = "DesktopFlatMap"
		flat_map.use_collision = true
		flat_map.collision_layer = 1
		flat_map.size = Vector3(200, 1, 200)
		flat_map.position = Vector3(0, -0.5, 0) # La superficie queda en y=0
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.35, 0.18) # Verde pasto genérico
		flat_map.material = mat
		
		parent_node.add_child(flat_map)
