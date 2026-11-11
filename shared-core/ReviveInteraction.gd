extends RefCounted

## ReviveInteraction.gd — Resolución de prioridad de la tecla [F] (Fase 9.7, ADR 100).
##
## Prioridad 1 ABSOLUTA: un aliado abatido a <= 2.5 m (grupo "downed_allies").
## Solo si no hay ninguno, [F] cae a la interacción contextual normal (cofres,
## DeathEcho, portales: grupo "interactable", alcance 3.5 m). El llamador consume
## el evento con get_viewport().set_input_as_handled() cuando gana la reanimación,
## para que ningún otro nodo (cofre / DeathEcho) reciba la misma pulsación.

const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")

const DOWNED_GROUP := "downed_allies"
const INTERACT_GROUP := "interactable"
const INTERACT_RANGE_M := 3.5

const KIND_NONE := "none"
const KIND_REVIVE := "revive"
const KIND_INTERACT := "interact"


## Pura y testeable: decide qué hace [F] desde `player_pos`.
## `downed` e `interactables` son arrays de Node3D. Devuelve {kind, node, distance}.
static func resolve(player_pos: Vector3, downed: Array, interactables: Array) -> Dictionary:
	var best_revive: Node3D = null
	var best_revive_d := INF
	for n in downed:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var d: float = player_pos.distance_to((n as Node3D).global_position)
		if d <= Codec.REVIVE_RANGE_M and d < best_revive_d:
			best_revive = n
			best_revive_d = d
	if best_revive:
		return {"kind": KIND_REVIVE, "node": best_revive, "distance": best_revive_d}

	var best: Node3D = null
	var best_d := INF
	for n in interactables:
		if not is_instance_valid(n) or not (n is Node3D) or not n.has_method("interact"):
			continue
		var d: float = player_pos.distance_to((n as Node3D).global_position)
		if d <= INTERACT_RANGE_M and d < best_d:
			best = n
			best_d = d
	if best:
		return {"kind": KIND_INTERACT, "node": best, "distance": best_d}
	return {"kind": KIND_NONE, "node": null, "distance": INF}


static func resolve_in_tree(tree: SceneTree, player_pos: Vector3) -> Dictionary:
	return resolve(player_pos, tree.get_nodes_in_group(DOWNED_GROUP), tree.get_nodes_in_group(INTERACT_GROUP))


## Session id del aliado abatido (meta "session_id" o propiedad "session_id").
static func session_id_of(node: Node) -> int:
	if node == null:
		return 0
	if node.has_meta("session_id"):
		return int(node.get_meta("session_id"))
	if "session_id" in node:
		return int(node.get("session_id"))
	return 0
