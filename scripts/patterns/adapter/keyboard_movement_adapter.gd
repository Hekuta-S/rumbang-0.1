class_name KeyboardMovementAdapter extends MovementSource

## Adapter: adapta las teclas WASD (API Input) a la interfaz MovementSource.

func get_movement_vector() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_W): y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_S): y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A): x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D): x += 1.0
	return Vector2(x, y)
