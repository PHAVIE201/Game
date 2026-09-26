class_name Layers
## Physics layer bit masks (names are also set in Project Settings > Layer Names).

const WORLD := 1 << 0        ## Terrain, buildings, rocks, tree trunks.
const CHARACTERS := 1 << 1   ## Character movement capsules (not used for bullets).
const WATER := 1 << 2        ## Reserved: water volumes.
const ITEMS := 1 << 3        ## Reserved (phase 2): loot pickups.
const VEHICLES := 1 << 4     ## Reserved (phase 3): vehicles.
const BOUNDARY := 1 << 5     ## Invisible map-edge walls (only block characters).

## What a character's movement collides with.
const CHARACTER_MASK := WORLD | CHARACTERS | VEHICLES | BOUNDARY

## What stops bullets and blocks line of sight.
const BULLET_BLOCKERS := WORLD | VEHICLES

## Visual (render) layers.
const RENDER_WORLD := 1 << 0
const RENDER_CHARACTERS := 1 << 1
