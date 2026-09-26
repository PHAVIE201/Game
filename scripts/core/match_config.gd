class_name MatchConfig
extends RefCounted
## Options for one match, filled by the main menu.

enum Difficulty { EASY, NORMAL, HARD }

## Number of bots (phase 1 target: 5-10; the architecture supports 63).
var bot_count := 8
## Map seed. The same seed always generates the same island.
var map_seed := 1337
## Bots spawn within this radius (meters) of the player so fights happen quickly.
## Phase 2 replaces this with the plane drop.
var spawn_radius := 380.0
var min_spawn_distance := 70.0
## Free-for-all: bots also fight each other (battle royale rules).
var bots_fight_each_other := true
var difficulty: int = Difficulty.NORMAL
## Zone timings multiplier (< 1 = faster matches).
var zone_time_scale := 1.0
## Everyone starts in the plane and parachutes down (false = spawn on the
## ground around the player, used by some automated tests).
var use_plane := true
