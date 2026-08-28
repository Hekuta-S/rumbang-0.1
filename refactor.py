import os
import re

path = r'D:\GodotProjects\tesis\scripts\core\main.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove spawn_terrain_slopes
content = re.sub(r'^func spawn_terrain_slopes\(\) -> void:.*?(?=\n^func |\Z)', '', content, flags=re.MULTILINE | re.DOTALL)

# Remove spawn_medieval_props
content = re.sub(r'^func spawn_medieval_props\(\) -> void:.*?(?=\n^func |\Z)', '', content, flags=re.MULTILINE | re.DOTALL)

# Replace get_floor_y
new_get_floor_y = """func get_floor_y(x: float, z: float) -> float:
	if has_node("EnvironmentManager"):
		return $EnvironmentManager.get_floor_y(x, z)
	return 0.0
"""
content = re.sub(r'^func get_floor_y\(x: float, z: float\) -> float:.*?(?=\n^func |\Z)', new_get_floor_y, content, flags=re.MULTILINE | re.DOTALL)

# cleanup double blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done!')
