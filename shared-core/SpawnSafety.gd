extends RefCounted

## SpawnSafety.gd — Blindaje de spawn del jugador local (ADR 037 / ADR 081).
## Única fuente de verdad compartida por World.gd y Player.gd: convierte una
## posición persistida potencialmente inválida (sentinel, origen, fuera de mapa)
## en un punto de aparición seguro y visible junto a los arquetipos de Overworld.
## Sin dependencias de autoloads para poder precargarse desde cualquier script.

const SENTINEL := Vector3(-999, -999, -999)
const SAFE_SPAWN_POS := Vector3(0.0, 1.0, 0.0)
const MAX_DIST_SQ := 500000.0

static func resolve(raw_pos: Vector3) -> Vector3:
	var spawn_pos := raw_pos
	if spawn_pos == SENTINEL or spawn_pos.length_squared() > MAX_DIST_SQ or spawn_pos == Vector3.ZERO:
		spawn_pos = SAFE_SPAWN_POS
	elif is_zero_approx(spawn_pos.y):
		spawn_pos.y = 1.0
	return spawn_pos
