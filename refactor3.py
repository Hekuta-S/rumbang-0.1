import os
import re

path = r'D:\GodotProjects\tesis\scripts\core\main.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove constants and preloads
content = re.sub(r'var weapon_pickup_scene.*?\n', '', content)
content = re.sub(r'var xp_orb_scene.*?\n', '', content)
content = re.sub(r'const PLAYABLE_MIN_X.*?PLAYABLE_MAX_Z.*?2300\.0\n', '', content, flags=re.DOTALL)

# 2. Inject LootManager in _ready
loot_init = """
	var loot_manager = LootManager.new()
	loot_manager.name = "LootManager"
	add_child(loot_manager)
	loot_manager.initialize(player)
"""
content = re.sub(r'(var wave_manager = WaveManager\.new\(\).*?wave_manager\.wave_cleared\.connect\(_on_wave_cleared\))', r'\1\n' + loot_init, content, flags=re.DOTALL)

# 3. Replace spawn calls
content = re.sub(r'spawn_debug_orbs\(\)', r'$LootManager.spawn_debug_orbs()', content)
content = re.sub(r'\tspawn_weapon_pickup\(\)', r'	$LootManager.spawn_weapon_pickup()', content)
content = re.sub(r'\tspawn_item_pickup\(\)', r'	$LootManager.spawn_item_pickup()', content)

# 4. Remove original functions
content = re.sub(r'^func spawn_debug_orbs\(\).*?^func start_game', 'func start_game', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^func spawn_weapon_pickup\(\).*?^func show_item_choice', 'func show_item_choice', content, flags=re.MULTILINE | re.DOTALL)

# 5. Fix _on_enemy_died xp_orb logic
old_xp_orb = """	if xp_orb_scene:
		var orb = xp_orb_scene.instantiate()
		add_child(orb)
		orb.global_position = pos + Vector3(0, 0.5, 0)"""
new_xp_orb = "\t$LootManager.spawn_xp_orb(pos)"
content = content.replace(old_xp_orb, new_xp_orb)

# cleanup double blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done!')
