# Age of Amazon — Godot Port Design

## Overview

Port the existing TypeScript/Three.js Age of Amazon RTS game (~23K lines) to Godot 4.5 with GDScript, targeting mobile-friendly 2D isometric gameplay.

## Tech Stack

- **Engine**: Godot 4.5
- **Language**: GDScript
- **Rendering**: 2D Isometric (TileMapLayer, 64x32 px tiles)
- **Target**: Desktop + Android + iOS

## Architecture

### Scene-Node Composition

Godot's native node tree replaces the custom ECS. Each game entity is a scene with child nodes providing functionality.

| TS Pattern | Godot Equivalent |
|---|---|
| ECS World + Entities | Scene tree + Groups |
| Components | Child nodes (Sprite2D, Area2D, etc.) |
| Systems | Node scripts + Autoload singletons |
| EventBus | Signals |
| Factory pattern | `PackedScene.instantiate()` |

### Autoload Singletons

- **GameManager.gd** — Game state, phase transitions, player data
- **EventBus.gd** — Global signals for cross-system communication
- **Constants.gd** — Unit/building definitions, terrain data

### Project Structure

```
age-of-amazon/
├── scenes/
│   ├── main/Main.tscn
│   ├── game/GameWorld.tscn
│   ├── map/IsometricMap.tscn
│   ├── units/Unit.tscn, Villager.tscn
│   ├── buildings/Building.tscn
│   ├── camera/GameCamera.tscn
│   └── ui/HUD.tscn, Minimap.tscn
├── scripts/
│   ├── autoloads/GameManager.gd, EventBus.gd, Constants.gd
│   ├── map/MapGenerator.gd
│   ├── units/Unit.gd, Villager.gd
│   ├── camera/GameCamera.gd
│   └── ui/HUD.gd
├── assets/tiles/, units/, buildings/
└── resources/unit_data/, building_data/
```

## Phase 1: MVP — Map + Units

### 1. Procedural Isometric Map

- `TileMapLayer` with 64x32 isometric tiles
- 128x128 map size (mobile-friendly)
- `FastNoiseLite` for procedural generation (ports Simplex noise approach)
- 7 terrain types: grass, dense forest, light forest, water deep, water shallow, swamp, cliff
- Rivers and lakes via meandering paths + Poisson disk
- Player spawn zones with guaranteed cleared area
- `NavigationRegion2D` baked from tilemap for pathfinding
- Terrain tiles generated via PixelLab MCP

### 2. Camera System

- `Camera2D` with smooth pan/zoom
- Input: arrow keys, WASD, mouse drag, touch drag, pinch zoom
- Edge scrolling on desktop (disabled on mobile)
- Bounds clamped to map limits
- Zoom range: 0.5 (close) to 2.0 (far), default 1.0

### 3. Base Unit System

Scene structure:
```
Unit (CharacterBody2D)
  ├── Sprite2D
  ├── CollisionShape2D
  ├── NavigationAgent2D
  ├── SelectionIndicator (Sprite2D)
  ├── HealthBar (ProgressBar)
  └── VisionArea (Area2D)
      └── CollisionShape2D
```

- State machine: IDLE, MOVING, ATTACKING, GATHERING, BUILDING
- `NavigationAgent2D` for pathfinding (replaces custom A*)
- Groups for querying: "units", "player_0", "player_1", etc.

### 4. Selection & Commands

- Tap unit → select
- Drag box → multi-select
- Tap ground → deselect
- Tap ground with selection → move command
- All touch-native

### 5. Art Approach

- PixelLab-generated isometric terrain tiles
- Colored placeholder sprites for units/buildings
- Real unit art generated later as designs stabilize

## Future Phases

- **Phase 2**: Resources (food, wood, jade, ancestral power) + gathering + buildings
- **Phase 3**: Combat + military units + tower defense
- **Phase 4**: AI opponent (behavior tree / state machine)
- **Phase 5**: Fog of war, HUD, minimap
- **Phase 6**: Save/load, polish, mobile optimization, store export
