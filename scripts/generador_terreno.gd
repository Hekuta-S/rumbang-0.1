@tool
extends EditorScript

# Script para generar un mapa procedimental con biomas.
# Ejecuta este script desde el editor (Archivo -> Ejecutar / Run) en el panel de scripts.

func _run():
	print("Iniciando generación de mapas de terreno...")
	
	# Tamaño del mapa (2048x2048 vértices)
	var map_size = 2048 
	
	# Creamos imágenes para guardar los datos
	var height_img = Image.create(map_size, map_size, false, Image.FORMAT_RF)
	var control_img = Image.create(map_size, map_size, false, Image.FORMAT_RGB8) 
	
	# Ruido para la altura (montañas y valles)
	var noise_height = FastNoiseLite.new()
	noise_height.seed = randi()
	noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_height.frequency = 0.0015
	noise_height.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_height.fractal_octaves = 6
	
	# Ruido para la humedad (determina los biomas)
	var noise_moisture = FastNoiseLite.new()
	noise_moisture.seed = randi() + 1
	noise_moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moisture.frequency = 0.003
	
	var max_height = 150.0 # Altura máxima en metros
	
	for x in range(map_size):
		for y in range(map_size):
			# Generar altura
			var h_val = noise_height.get_noise_2d(x, y)
			h_val = (h_val + 1.0) * 0.5 # Normalizar de 0 a 1
			h_val = pow(h_val, 1.8) # Suavizar valles, picos más pronunciados
			
			var real_height = h_val * max_height
			height_img.set_pixel(x, y, Color(real_height, 0, 0, 1))
			
			# Generar humedad
			var m_val = noise_moisture.get_noise_2d(x, y)
			m_val = (m_val + 1.0) * 0.5 # Normalizar de 0 a 1
			
			# Lógica de Biomas (Control Map)
			# Asumimos que los IDs de las texturas en Terrain3D serán:
			# 0: Roca
			# 1: Nieve
			# 2: Pasto (Bosque)
			# 3: Pantano
			# 4: Arena (Desierto)
			
			var tex_id = 2 # Pasto por defecto
			
			if real_height > 110.0:
				tex_id = 1 # Nieve en las zonas más altas
			elif real_height > 70.0:
				tex_id = 0 # Roca en montañas
			else:
				if m_val < 0.35:
					tex_id = 4 # Arena si es muy seco
				elif m_val > 0.65 and real_height < 25.0:
					tex_id = 3 # Pantano si es húmedo y bajo
				else:
					tex_id = 2 # Bosque / Pasto
					
			# En el control map de Terrain3D usualmente el ID base va en el canal Rojo.
			control_img.set_pixel(x, y, Color(tex_id / 255.0, 0, 0, 1))
	
	# Guardamos los mapas generados
	height_img.save_exr("res://terrain_height.exr")
	control_img.save_png("res://terrain_control.png")
	
	print("=======================================")
	print("Generación completada con éxito.")
	print("Se han creado dos archivos en la raíz de tu proyecto (res://):")
	print("- terrain_height.exr (Mapa de altura)")
	print("- terrain_control.png (Mapa de biomas)")
	print("=======================================")
