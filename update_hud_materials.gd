extends SceneTree

func _init():
	var scene = load("res://scenes/ui/hud.tscn")
	var root = scene.instantiate()
	
	var vbox = root.get_node("Control/StatsPanel/Margin/VBox")
	var hbox = vbox.get_node("HBox")
	
	var hp_bar = hbox.get_node("HPBox/HPBar")
	var shield_bar = hbox.get_node("ShieldBox/ShieldBar")
	var energy_bar = hbox.get_node("EnergyBox/EnergyBar")
	
	var shader = load("res://scripts/ui/trapezoid.gdshader")
	
	# HP Bar (Straight on left, slanted on right)
	var mat_hp = ShaderMaterial.new()
	mat_hp.shader = shader
	mat_hp.set_shader_parameter("top_left", 0.0)
	mat_hp.set_shader_parameter("bottom_left", 0.0)
	mat_hp.set_shader_parameter("top_right", 1.0)
	mat_hp.set_shader_parameter("bottom_right", 0.4)
	hp_bar.material = mat_hp
	
	# Shield Bar (Straight on both sides -> Normal Rectangle)
	# No material needed, or set to 0.0 -> 1.0
	shield_bar.material = null
	
	# Energy Bar (Slanted on left, straight on right)
	var mat_energy = ShaderMaterial.new()
	mat_energy.shader = shader
	mat_energy.set_shader_parameter("top_left", 0.0)
	mat_energy.set_shader_parameter("bottom_left", 0.6)
	mat_energy.set_shader_parameter("top_right", 1.0)
	mat_energy.set_shader_parameter("bottom_right", 1.0)
	energy_bar.material = mat_energy
	
	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/ui/hud.tscn")
	print("HUD materials updated for asymmetric cuts.")
	
	quit()
