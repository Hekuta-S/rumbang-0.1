class_name EquipmentForge
extends RefCounted

## Fase 4 del plan de loot: la forja de Tatán (DungeonShop) trabaja tus piezas con el oro de la partida.
##  - MEJORAR: sube una rareza (hasta MAX_RARITY) y vuelve a sortear los stats a la nueva rareza;
##    si la pieza no tenía efecto o rasgo, puede ganarlos. Las legendarias fijas no se mejoran.
##  - RE-TIRAR: nuevos stats a la misma rareza (y nuevo rasgo condicional si tenía uno).
##  - DESGUAZAR: una pieza de la mochila se convierte en oro.
## Las funciones cambian el diccionario de la pieza en el sitio; PlayerEquipment avisa con _changed().

const MAX_RARITY := ItemDB.Rarity.LEGENDARY
const COLOR := Color(1.0, 0.55, 0.2)

static func is_fixed(item: Dictionary) -> bool:
	return item.has("legendary")

static func can_upgrade(item: Dictionary) -> bool:
	return not item.is_empty() and not is_fixed(item) and int(item.get("rarity", 0)) < MAX_RARITY

static func can_reroll(item: Dictionary) -> bool:
	return not item.is_empty() and not is_fixed(item)

static func upgrade_price(item: Dictionary, level: int) -> int:
	return 70 + 50 * int(item.get("rarity", 0)) + 10 * level

static func reroll_price(item: Dictionary, level: int) -> int:
	return 30 + 20 * int(item.get("rarity", 0)) + 5 * level

static func scrap_value(item: Dictionary) -> int:
	return 12 + 18 * int(item.get("rarity", 0)) + (20 if is_fixed(item) else 0)

## Sube una rareza. Devuelve false si no se puede.
static func upgrade(item: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if not can_upgrade(item):
		return false
	var r := int(item["rarity"]) + 1
	var kind := String(item["slot"])
	item["rarity"] = r
	item["stats"] = EquipmentDB.roll_stats(r, rng, kind)
	if not item.has("perk"):
		var perk := EquipmentDB.roll_perk(kind, r, rng)
		if perk != "":
			item["perk"] = perk
	if not item.has("cond"):
		var cond := EquipmentDB.roll_cond(kind, r, rng)
		if cond != "":
			item["cond"] = cond
	return true

## Nuevos stats a la misma rareza (y nuevo rasgo si ya tenía uno).
static func reroll(item: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if not can_reroll(item):
		return false
	var r := int(item.get("rarity", 0))
	var kind := String(item["slot"])
	item["stats"] = EquipmentDB.roll_stats(r, rng, kind)
	if item.has("cond"):
		var old := String(item["cond"])
		for i in 6:
			var c := EquipmentDB.roll_cond(kind, ItemDB.Rarity.MYTHIC, rng)   # MYTHIC: siempre sale uno
			if c != "" and c != old:
				item["cond"] = c
				break
	return true

## Piezas que se pueden trabajar: [{slot_key, item}] con slot_key "arma" para la de la mano.
static func workable(eq: PlayerEquipment) -> Array:
	var out: Array = []
	for slot in PlayerEquipment.SLOTS:
		if eq.equipped.has(slot):
			out.append({"key": slot, "item": eq.equipped[slot]})
	var w := eq.weapon_in_hand()
	if not w.is_empty():
		out.append({"key": "arma", "item": w})
	return out

## Texto corto de una pieza para las tarjetas de la forja.
static func card_desc(item: Dictionary) -> String:
	var lines: Array = ["%s %s" % [EquipmentDB.KIND_NAMES.get(item["slot"], ""), EquipmentDB.rarity_name(item).to_lower()]]
	lines.append_array(EquipmentDB.describe_stats(item.get("stats", {})))
	lines.append_array(EquipmentDB.trait_lines(item))
	return "\n".join(lines)
