# Release review — 2026-11-17

Reviewed the installed single-map campaign with Godot 4.7.2 before public release.

## Fixes

- Minimap recreates a missing backdrop and skips stale selections or missing city nodes.
- Gate picking and city HUD projection tolerate missing cached node positions. City anchor fallbacks no longer eagerly index a missing dictionary key.
- Campaign smoke uses the current commander recruitment API, role-based Food cost, and victory condition including enemy village garrisons.
- Windows launcher finds Godot through GODOT_BIN, PATH or WinGet and imports a fresh checkout on its first launch.
- Git preserves exact file bytes so line-ending conversion cannot break runtime integrity after a clone. Generated caches, logs, captures and save fixtures are excluded.

The earlier camera zoom and incomplete gate-footprint fixes in this release were retained and reviewed. Gameplay balance, map geometry, source meshes, textures, rigs and attack clips were not modified in this pass. Historical human acceptance remains in campaign-acceptance.json.

## Verification

- Fresh import: exit 0.
- Campaign smoke: 11 passed.
- Review regression smoke: 8 passed.
- Existing playability checks: 20 passed.
- Existing combat/movement transition checks: 22 passed.
- Runtime manifest: 414 dependencies, no missing files or mismatched hashes.

Run the two bundled smoke commands from README.md to repeat release checks.
This review covers automated checks and a short rendered run; it is not a new full-campaign human acceptance.
