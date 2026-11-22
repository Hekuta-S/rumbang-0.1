class_name FateOutcome extends RefCounted

## PATRÓN STRATEGY (comportamiento) — rol: Strategy (la interfaz)
## Problema previo: FateDice.apply() y FateDice.apply12() eran dos `match v` enormes (6 y 12 ramas) con
## código copiado entre ellos (maldición ×3, furia ×4, curar, oro, regalo). Añadir un resultado = editar el match.
## Ahora cada resultado es un objeto con el mismo método; FateDice solo busca el objeto y lo ejecuta:
##     FateOutcomes.table(faces, survival)[valor].apply(ctx)
##   Context  : FateDice            (resuelve la tirada, no sabe qué hace cada resultado)
##   Strategy : FateOutcome         (este archivo)
##   Concrete : FateOutcomes.*      (una clase por comportamiento, reutilizable en varias caras)
## Mismo estilo que WeaponStrategy (scripts/components/weapon_strategy.gd).

func apply(_ctx: FateContext) -> void:
	pass
