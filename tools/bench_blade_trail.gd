extends SceneTree

## Mide el coste de CPU de BladeTrail (GDScript + construcción de la malla), activa y en reposo.
## Uso: godot --headless --path . --script res://tools/bench_blade_trail.gd

const FRAMES := 6000
const DT := 1.0 / 60.0

var _done := false

## Se mide en el primer frame: en _initialize el árbol aún no está activo (sin transformaciones globales).
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var base := Marker3D.new()
	base.position = Vector3(0, 0.3, 0)
	holder.add_child(base)
	var tip := Marker3D.new()
	tip.position = Vector3(0, 1.4, 0)
	holder.add_child(tip)
	var trail := BladeTrail.new()
	holder.add_child(trail)
	trail.setup(base, tip)
	trail.set_process(false)          # los frames los marca el banco de pruebas

	# Activa: la hoja gira sin parar (golpe continuo). Se mide con el detalle de calidad alta y el de baja.
	trail.emit(1.0e6)
	var t0 := 0
	var active := [0.0, 0.0]
	for q in 2:
		trail._subdiv = 4 if q == 0 else 2
		trail._relax_passes = 2 if q == 0 else 1
		t0 = Time.get_ticks_usec()
		for i in FRAMES:
			holder.rotation = Vector3(0.3 * sin(i * 0.05), i * 0.21, 0.0)
			trail._process(DT)
		active[q] = float(Time.get_ticks_usec() - t0) / FRAMES

	# En reposo: sin emitir y con la cinta ya apagada
	trail._emit_left = 0.0
	for i in 60:
		trail._process(DT)
	trail.set_process(true)
	for i in 5:
		trail._process(DT)
	var sleeps := not trail.is_processing()      # la versión nueva se apaga sola cuando no hay nada que dibujar
	t0 = Time.get_ticks_usec()
	for i in FRAMES:
		trail._process(DT)
	var idle := float(Time.get_ticks_usec() - t0) / FRAMES

	print("BLADE TRAIL BENCH: activa %.1f us/frame (alta) / %.1f (baja) | llamada en reposo %.2f us | se apaga sola: %s" % [
		active[0], active[1], idle, sleeps])
	quit(0)
