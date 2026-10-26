class_name TouchMovementAdapter extends MovementSource

## Adapter: adapta el joystick virtual (autoload VirtualInput) a la interfaz MovementSource.

const DEADZONE_SQ := 0.01

func get_movement_vector() -> Vector2:
	var v: Vector2 = VirtualInput.movement_vector
	return v if v.length_squared() > DEADZONE_SQ else Vector2.ZERO
