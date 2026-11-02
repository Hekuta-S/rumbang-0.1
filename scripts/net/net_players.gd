class_name NetPlayers
extends RefCounted

## Consulta de jugadores para la IA enemiga y los proyectiles. En solitario devuelve solo al jugador local;
## en red, al local y a los RemotePlayer (todos en el grupo "net_players"). Un jugador caído (metadato
## "downed") no cuenta como objetivo.

static func all() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var out: Array = []
	for n in tree.get_nodes_in_group("net_players"):
		if is_instance_valid(n):
			out.append(n)
	if out.is_empty() and not Net.is_dedicated():
		var p := tree.get_first_node_in_group("player")
		if p:
			out.append(p)
	return out

static func is_alive(p: Node) -> bool:
	return is_instance_valid(p) and not bool(p.get_meta("downed", false))

static func alive() -> Array:
	return all().filter(func(p): return is_alive(p))

## El jugador vivo más cercano (o cualquiera si todos están caídos, para que la IA no pierda la referencia).
static func nearest(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in alive():
		var d := (p as Node3D).global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		var any := all()
		if not any.is_empty():
			best = any[0]
	return best
