@tool
extends EditorScript

# Asegura que todas las texturas sean exactamente de 2048x2048 y tengan el mismo formato (RGB8).

func _run():
	print("Homogeneizando texturas para Terrain3D (Tamaño y Formato)...")
	var tex_paths = [
		"res://assets/textures/entorno/roca.jpg",
		"res://assets/textures/entorno/nieve.jpg",
		"res://assets/textures/entorno/pasto.jpg",
		"res://assets/textures/entorno/pantano.jpg",
		"res://assets/textures/entorno/arena.jpg"
	]
	
	var target_size = Vector2i(2048, 2048)
	
	for path in tex_paths:
		var img = Image.load_from_file(path)
		if img:
			var changed = false
			
			# 1. Asegurar Formato Idéntico
			if img.get_format() != Image.FORMAT_RGB8:
				print("Cambiando formato de: " + path)
				img.convert(Image.FORMAT_RGB8)
				changed = true
			
			# 2. Asegurar Tamaño Idéntico
			if img.get_size() != target_size:
				print("Redimensionando: " + path)
				img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
				changed = true
			
			if changed:
				img.save_jpg(path, 0.95)
			else:
				print("Ya está perfecto: " + path)
		else:
			print("Error al cargar: " + path)
			
	print("¡Todas las texturas estandarizadas! Terrain3D ya no debería dar problemas.")
