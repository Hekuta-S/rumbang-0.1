extends Node3D

func _ready():
	var img = Image.new()
	var err = img.load("res://tests/mapa.jpg")
	if err != OK:
		print("Failed to load map image")
		return
	
	img.convert(Image.FORMAT_RGB8)
	
	var mesh = ArrayMesh.new()
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	var w = img.get_width()
	var h = img.get_height()
	var width_scale = 1.0
	var height_scale = 30.0
	
	var step = max(1, int(max(w, h) / 128.0))
	var grid_w = w / step
	var grid_h = h / step
	
	for z in range(grid_h):
		for x in range(grid_w):
			var px = x * step
			var py = z * step
			var color = img.get_pixel(px, py)
			var y = color.v * height_scale
			var vx = (x - grid_w/2.0) * width_scale
			var vz = (z - grid_h/2.0) * width_scale
			vertices.push_back(Vector3(vx, y, vz))
			normals.push_back(Vector3.UP)
			uvs.push_back(Vector2(float(x)/grid_w, float(z)/grid_h))
			
			if x < grid_w - 1 and z < grid_h - 1:
				var i = z * grid_w + x
				indices.push_back(i)
				indices.push_back(i + grid_w)
				indices.push_back(i + 1)
				
				indices.push_back(i + 1)
				indices.push_back(i + grid_w)
				indices.push_back(i + grid_w + 1)
	
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.45, 0.25)
	mi.material_override = mat
	add_child(mi)
	
	mi.create_trimesh_collision()
	
	for i in range(GameData.CHARACTERS.size()):
		if GameData.CHARACTERS[i]["id"] == "riva":
			GameData.selected_index = i
			break
	
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	GameData.apply_to_player(player)
	
	var center_color = img.get_pixel(w/2, h/2)
	player.global_position = Vector3(0, (center_color.v * height_scale) + 5.0, 0)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	add_child(light)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
