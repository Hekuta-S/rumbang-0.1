extends SceneTree

func _init():
	var scene = load("res://scenes/ui/hud.tscn")
	var root = scene.instantiate()
	
	var vbox = root.get_node("Control/StatsPanel/Margin/VBox")
	
	var hp_bar = vbox.get_node("HPBar")
	var hp_label = hp_bar.get_node("HPLabel")
	
	var shield_bar = vbox.get_node("ShieldBar")
	var shield_label = shield_bar.get_node("ShieldLabel")
	
	var energy_bar = vbox.get_node("EnergyBar")
	var energy_label = energy_bar.get_node("EnergyLabel")
	
	# Create HBox
	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)
	hbox.owner = root
	
	# Configure bars and move them
	var shader = load("res://scripts/ui/trapezoid.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("top_width_ratio", 1.0)
	mat.set_shader_parameter("bottom_width_ratio", 0.6)
	
	var bars = [
		{"name": "HP", "bar": hp_bar, "label": hp_label},
		{"name": "Shield", "bar": shield_bar, "label": shield_label},
		{"name": "Energy", "bar": energy_bar, "label": energy_label}
	]
	
	for b in bars:
		# Create VBox for this bar
		var col = VBoxContainer.new()
		col.name = b.name + "Box"
		col.alignment = BoxContainer.ALIGNMENT_END
		col.add_theme_constant_override("separation", 4)
		hbox.add_child(col)
		col.owner = root
		
		# Detach bar and label
		var bar = b.bar
		var label = b.label
		bar.get_parent().remove_child(bar)
		label.get_parent().remove_child(label)
		
		# Reattach
		col.add_child(bar)
		bar.owner = root
		col.add_child(label)
		label.owner = root
		
		# Update properties
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.custom_minimum_size = Vector2(40, 120)
		bar.material = mat
		
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(60, 20)
		
	var stats_panel = root.get_node("Control/StatsPanel")
	stats_panel.size = Vector2(280, 220)
	stats_panel.custom_minimum_size = Vector2(280, 220)
	
	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/ui/hud.tscn")
	print("HUD updated with vertical trapezoid bars.")
	
	quit()
