class_name TutorialDirector
extends RefCounted

## Pasos del tutorial del patio (TutorialPatio): moverse, golpear, esquivar, parry y un combate final.
## Máquina de estados pura (sin nodos): quien juega llama a report(evento, cantidad) y el director avanza
## cuando se llega a la meta del paso. Eventos: "move" (metros), "hit", "dodge", "parry", "kill".

signal step_changed(index: int)
signal progressed(progress: float, goal: float)
signal finished

const STEPS := [
	{"id": "mover", "title": "1/5 · MOVERSE", "event": "move", "goal": 6.0, "unit": "m",
		"text": "Muévete con W A S D (o el joystick).\nLa cámara apunta hacia donde mueves el ratón.",
		"text_touch": "Muévete con el joystick (mitad izquierda de la pantalla).\nDesliza otro dedo por la pantalla para girar la cámara."},
	{"id": "golpear", "title": "2/5 · GOLPEAR", "event": "hit", "goal": 6.0, "unit": "",
		"text": "Golpea al muñeco con el clic izquierdo.\nEncadena golpes: el combo cierra con un remate más fuerte.",
		"text_touch": "Golpea al muñeco con el botón grande de ATAQUE.\nMantenlo para encadenar: el combo cierra con un remate más fuerte."},
	{"id": "esquivar", "title": "3/5 · ESQUIVAR", "event": "dodge", "goal": 3.0, "unit": "",
		"text": "Cuando el goblin se ponga ROJO, esquiva con ESPACIO.\nEl rodillo te hace intocable un instante.",
		"text_touch": "Cuando el goblin se ponga ROJO, pulsa RODAR (las flechas dobles).\nEl rodillo te hace intocable un instante."},
	{"id": "parry", "title": "4/5 · PARRY (BLOQUEO)", "event": "parry", "goal": 3.0, "unit": "",
		"text": "Pulsa F justo antes de que te golpee.\nSi aciertas, lo aturdes y tu siguiente golpe hace más daño.",
		"text_touch": "Pulsa PARAR (el escudo) justo antes de que te golpee.\nSi aciertas, lo aturdes y tu siguiente golpe hace más daño."},
	{"id": "combate", "title": "5/5 · TODO JUNTO", "event": "kill", "goal": 1.0, "unit": "",
		"text": "Usa lo aprendido y derrota al goblin.\nEsquiva sus golpes, bloquea los rápidos y contraataca.",
		"text_touch": "Usa lo aprendido y derrota al goblin.\nToca la MIRA para fijarlo; mantén y desliza para cambiar de objetivo."},
]

var index := -1
var progress := 0.0
var done := false

func start() -> void:
	done = false
	_goto(0)

func current() -> Dictionary:
	return STEPS[index] if index >= 0 and index < STEPS.size() else {}

func goal() -> float:
	return float(current().get("goal", 1.0))

## Un evento del juego; solo cuenta si es el del paso actual. Devuelve true si ese paso se completó.
func report(event: String, amount: float = 1.0) -> bool:
	if done or index < 0 or String(current()["event"]) != event:
		return false
	progress = minf(progress + amount, goal())
	progressed.emit(progress, goal())
	if progress >= goal():
		_goto(index + 1)
		return true
	return false

## Salta todo el tutorial (botón "Saltar").
func skip_all() -> void:
	if done:
		return
	index = STEPS.size()
	done = true
	finished.emit()

func _goto(i: int) -> void:
	index = i
	progress = 0.0
	if i >= STEPS.size():
		done = true
		finished.emit()
		return
	step_changed.emit(i)
