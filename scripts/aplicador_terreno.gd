@tool
extends EditorScript

func _run():
	print("Iniciando aplicación automática al Terreno...")
	
	var scene = get_editor_interface().get_edited_scene_root()
	if not scene:
		print("Error: No hay una escena abierta.")
		return
		
	var terrain = scene.get_node_or_null("Terrain3D")
	if not terrain:
		print("Error: No se encontró un nodo llamado 'Terrain3D'.")
		return
		
	# 1. Asegurarnos de que el Terreno tenga un Material
	var material = terrain.get("material")
	if not material:
		material = Terrain3DMaterial.new()
		terrain.set("material", material)
		
	# 2. Configurar Assets (Texturas)
	var assets = terrain.get("assets")
	if not assets:
		print("Creando nuevos Assets...")
		assets = Terrain3DAssets.new()
		terrain.set("assets", assets)
		
	print("Configurando texturas de biomas...")
	var tex_paths = [
		"res://assets/textures/entorno/roca.jpg",
		"res://assets/textures/entorno/nieve.jpg",
		"res://assets/textures/entorno/pasto.jpg",
		"res://assets/textures/entorno/pantano.jpg",
		"res://assets/textures/entorno/arena.jpg"
	]
	
	for i in range(tex_paths.size()):
		var img_tex = load(tex_paths[i])
		if img_tex:
			var ta = Terrain3DTextureAsset.new()
			ta.name = tex_paths[i].get_file().get_basename()
			ta.albedo_texture = img_tex
			assets.set_texture(i, ta)
		else:
			print("Error: No se encontró " + tex_paths[i])
			
	# 3. Cargar Mapas e Importar
	var data = terrain.get("data")
	if not data:
		data = Terrain3DData.new()
		terrain.set("data", data)
		
	print("Cargando mapas de altura y control...")
	var height_img = Image.load_from_file("res://terrain_height.exr")
	var control_img = Image.load_from_file("res://terrain_control.png")
	
	if height_img and control_img:
		var imported_images: Array[Image] = []
		imported_images.resize(3) 
		imported_images[0] = height_img
		imported_images[1] = control_img
		
		print("Importando mapas al Terrain3D...")
		data.import_images(imported_images, Vector3.ZERO, 0.0, 1.0)
		
		# Forzar actualización
		terrain.force_update_aabb()
		print("¡Terreno aplicado correctamente! Revisa la vista 3D.")
	else:
		print("Error: No se encontraron los archivos EXR o PNG.")
