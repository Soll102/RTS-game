# Three Kingdoms | Unification

A traditional real-time strategy game built with **Godot 4.7.2** (GL Compatibility renderer).
Single installed campaign: `v8-hills-region`, 360×280 m, save schema 14.

## Run

- Windows: double-click `Launch-Game.cmd`. It finds Godot in PATH or the WinGet installation; you can also set `GODOT_BIN` to the executable. It imports assets on the first launch.
- Any platform: run `godot --headless --path . --import` once, then `godot --path .` with Godot 4.7.2.

Main scene: `res://main.tscn`.

## Controls

- Arrows / WASD: pan camera; mouse wheel: zoom; middle mouse: drag the map.
- Left click or drag: select squads; right click: move / attack / siege.
- `M` move, `A` attack-move, `Space` pause, `H` hold, `R` retreat,
  `Q` commander skill, `F5` quick save, `F9` quick load, `Esc` menu.

## Saves

Saves live in the user directory `RTS-Three-Kingdoms-Campaign-v1`.
Schema 14 is current; schema 11–13 slots are kept separate and retain their
original rulesets when loaded. Old saves are never relabelled or overwritten.

## Project notes

- `release-integrity.json` lists the SHA-256 hashes of every installed dependency;
  the game verifies these at launch. Keep it in sync if you edit any listed file.
- `campaign-acceptance.json` records the historical acceptance of the baseline build.
- Three factions (Wei, Shu, Wu), eight settlements, four unit roles and commanders.
- River crossings use three persistent boats; gates can be assaulted independently.

## Verify

After importing once, run the built-in campaign smoke check:

```text
godot --headless --path . --import
godot --headless --path . -- --campaign-smoke
godot --headless --path . --script res://tests/review_smoke.gd
```

The smoke process exits non-zero if integrity, recruitment, orders, pause,
save/load, faction startup, victory, or continue-campaign checks fail.

## License

Project code uses Apache License 2.0 — see `LICENSE`. Third-party source meshes,
textures, portraits, fonts, rigs and animations retain their respective owners'
rights; the code license does not grant rights to those assets.
