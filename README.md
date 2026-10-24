# Cyber Siege v0.1.1 — Aeon Prototype

A controller-first 3D twin-stick arena shooter built as the first playable test title for Aeon.

## Engine
- Godot 4.7.2 recommended
- GDScript
- Linux/Windows friendly
- No external assets required

## v0.1.1 changes
- Forward+ (Vulkan) renderer -- Aeon is a Vulkan console
- Fullscreen, 1920x1080 design resolution
- All input via the InputMap (move / aim / fire / restart / resume) -- remappable
- Pauses on focus loss (the Aeon guide overlay); A resumes

## Current gameplay
- 3D arena
- Keyboard/mouse and gamepad controls
- Left-stick/WASD movement
- Right-stick/mouse aiming
- RT/right bumper/left-click firing
- Enemy wave spawning
- Health, damage, score, death, restart
- Increasing enemy pressure each wave

## Run it
1. Install Godot 4.7.2 or a compatible Godot 4.7.x build.
2. Open Godot Project Manager.
3. Import this folder by selecting `project.godot`.
4. Press F6/F5 or click Run Project.

## Controls
### Controller
- Left stick: move
- Right stick: aim
- Right trigger or right bumper: fire
- A: restart after death

### Keyboard/mouse
- WASD: move
- Mouse: aim
- Left click: fire
- R: restart after death

## v0.2 target
- Dash ability
- Enemy archetypes
- Weapon heat/reload mechanic
- Arena hazards
- Proper pause/settings flow
- Aeon button glyphs and UI language
- Audio and haptics
- First Cyber Siege art pass

## Project intent
This prototype is deliberately built from primitive geometry. The goal of v0.1 is to prove the combat loop and input model before investing in production art.
