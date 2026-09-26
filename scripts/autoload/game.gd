extends Node
## Service locator for the currently running game session (autoload "Game").
##
## GameSession registers its subsystems here in _ready() and clears them when it
## leaves the tree. Any script can then reach shared services with e.g.
## `Game.world.get_height(x, z)` or `Game.projectiles.fire(...)` without long
## node paths. Always check `Game.is_active()` in code that can run outside a match.

var session: Node = null
var world: GameWorld = null
var projectiles: ProjectileSystem = null
var fx: FxManager = null
var match_manager: MatchManager = null
## The local human player (null when dead characters are cleaned up / no match).
var player: GameCharacter = null
## Active camera used for LOD decisions (animation, audio, etc.).
var camera: Camera3D = null


func is_active() -> bool:
	return session != null and is_instance_valid(session)


func clear() -> void:
	session = null
	world = null
	projectiles = null
	fx = null
	match_manager = null
	player = null
	camera = null


## Position used for level-of-detail distance checks (camera, or origin).
func get_view_position() -> Vector3:
	if camera != null and is_instance_valid(camera):
		return camera.global_position
	return Vector3.ZERO
