import os
import re

path = r'D:\GodotProjects\tesis\scripts\core\main.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove old variables
content = re.sub(r'var enemy_scene = preload\("res://scenes/entities/enemy\.tscn"\)\n', '', content)
content = re.sub(r'var boss_scene = preload\("res://scenes/entities/boss\.tscn"\)\n', '', content)
content = re.sub(r'var spawn_timer: Timer\nvar enemies_to_spawn_this_floor: int = 0\nvar enemies_spawned: int = 0\n', '', content)

# Inject WaveManager in _ready
wave_init = """
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.enemy_died.connect(_on_enemy_died)
	wave_manager.boss_died.connect(_on_boss_died)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
"""
content = re.sub(r'(var env_manager = EnvironmentManager\.new\(\).*?env_manager\.generate_environment\(\))', r'\1\n' + wave_init, content, flags=re.DOTALL)

# Modify start_game to call start_wave
new_start_game = """	$WaveManager.start_wave(sub_level, player)
	spawn_weapon_pickup()
	spawn_item_pickup()"""
content = re.sub(r'spawn_floor_enemies\(sub_level\)', new_start_game, content)

# Remove old wave functions
content = re.sub(r'^func spawn_floor_enemies\(.*?^func spawn_weapon_pickup', 'func spawn_weapon_pickup', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^func scale_boss\(.*?^var xp_orb_scene', 'var xp_orb_scene', content, flags=re.MULTILINE | re.DOTALL)

# Replace _on_enemy_died and _on_boss_died, and add _on_wave_cleared
new_events = """func _on_enemy_died(pos: Vector3, gold_val: int) -> void:
	gold += gold_val
	hud.update_gold(gold)
	SaveManager.add_gold(gold_val)
	
	if xp_orb_scene:
		var orb = xp_orb_scene.instantiate()
		add_child(orb)
		orb.global_position = pos + Vector3(0, 0.5, 0)

func _on_wave_cleared() -> void:
	sub_level += 1
	hud.update_floor(sub_level)
	SaveManager.set_best_floor(_char_id(), sub_level)
	$WaveManager.start_wave(sub_level, player)
	spawn_weapon_pickup()
	spawn_item_pickup()

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	gold += gold_val
	hud.update_gold(gold)
	SaveManager.add_gold(gold_val)
	SaveManager.set_best_floor(_char_id(), sub_level)

	if sub_level >= 9:
		AudioManager.play("victory")
		hud.show_victory()
	else:
		AudioManager.play("coin")
		sub_level += 1
		hud.update_floor(sub_level)
		$WaveManager.start_wave(sub_level, player)
		spawn_weapon_pickup()
		spawn_item_pickup()
"""
content = re.sub(r'^func _on_enemy_died\(.*?^func _char_id', new_events + '\nfunc _char_id', content, flags=re.MULTILINE | re.DOTALL)

# cleanup double blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done!')
