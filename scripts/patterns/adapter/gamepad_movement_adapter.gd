class_name GamepadMovementAdapter extends MovementSource

## Adapter: adapta el stick izquierdo del mando (ejes de Input) a la interfaz MovementSource.

const DEADZONE := 0.2

func get_movement_vector() -> Vector2:
	var v := Vector2.ZERO
	var joy_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(joy_x) > DEADZONE: v.x = joy_x
	if abs(joy_y) > DEADZONE: v.y = joy_y
	return v
