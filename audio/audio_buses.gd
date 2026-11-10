extends RefCounted
## audio_buses.gd — Constantes canónicas de nombres de buses (ADR 094)
## Ningún script debe referenciar un bus por string literal.

const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const AMBIENCE: StringName = &"Ambience"
const AMBIENCE_HAZARD: StringName = &"Ambience_Hazard"

const SFX: StringName = &"SFX"
const SFX_WORLD: StringName = &"SFX_World"
const SFX_PLAYER: StringName = &"SFX_Player"
const SFX_CRITICAL: StringName = &"SFX_Critical"

const UI: StringName = &"UI"
const VOICE: StringName = &"Voice"

enum Priority {
	AMBIENCE = 0,
	WORLD = 1,
	PLAYER = 2,
	CRITICAL = 3
}

enum HitmarkerType {
	CONFIRM,  # Impacto normal confirmado
	CRIT,     # Golpe crítico
	KILL,     # Abatimiento
	SHIELD,   # Absorción por barrera arcana
	HURT_SELF # Daño recibido por el jugador
}

