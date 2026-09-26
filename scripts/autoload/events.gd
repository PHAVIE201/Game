extends Node
## Global signal bus (autoload "Events").
##
## Gameplay systems talk to each other through these signals instead of holding
## direct references. This keeps HUD, AI, audio and match logic decoupled, which
## matters once later phases add zone, loot, vehicles and 63 bots.
##
## Signal arguments use base types (Node / RefCounted) to avoid cyclic
## class dependencies inside the autoload; receivers cast to GameCharacter /
## DamageInfo as needed.

# The signals are emitted by other classes, which the analyzer cannot see.
@warning_ignore_start("unused_signal")

## A character entered the match (player or bot).
signal character_spawned(character: Node)
## A character received damage. `info` is a DamageInfo.
signal character_damaged(victim: Node, info: RefCounted)
## A character died. `info` is the killing DamageInfo (attacker may be null).
signal character_died(victim: Node, info: RefCounted)
## A weapon was fired. Bots use this to "hear" gunshots.
signal shot_fired(shooter: Node, position: Vector3, loudness_radius: float)

## Match flow.
signal match_started()
signal match_state_changed(state: int)
signal alive_count_changed(alive: int, total: int)
## Emitted once the local player is out (dead) or has won. `result` is a Dictionary
## with keys: won, placement, total, kills, damage, time_alive, killer_name, weapon, headshot.
signal player_match_result(result: Dictionary)

## World generation progress for the loading screen (0..1).
signal world_generation_progress(step: String, progress: float)

## Short message in the center of the HUD (e.g. "Còn 5 người").
signal hud_message(text: String, duration: float)
## Small feedback line above the health bar for the local player's looting.
signal loot_message(text: String)
