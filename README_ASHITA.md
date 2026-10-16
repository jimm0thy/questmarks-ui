# questmarks-ui — Ashita v4 port

Ashita v4 port **v0.3.1** by **Semil** of **questmarks-ui 1.0.0** by **DrNefarius** (Windower 4).
Your accepted quests as a browsable in-game list, grouped by the game's own quest-log regions,
built on the data of the questmarks addon (see the sibling Ashita port).

## Install
1. Install the Ashita port of **questmarks** first, at `Ashita/addons/questmarks/` (it does not need to be loaded).
2. Copy this folder to `Ashita/addons/questmarks-ui/` so that `questmarks-ui.lua` sits directly inside it.
3. `/addon load questmarks-ui`

A closed book appears. Click it to open the log, click again to close, drag it where you like.
`/qmui` (or `/questlog`) also opens and closes it, so it can go on a macro. `/qmui help` lists every command
(the commands are the original's, with `//qmui` written `/qmui`).

If questmarks is somewhere else: `/qmui path <folder>`. By default it looks for the sibling folder `../questmarks/`.

## How it was ported
The original draws through one file (`ui/draw.lua`) and talks to Windower through a handful of calls, so only those changed:

| Piece | Windower original | Ashita port |
|---|---|---|
| Drawing | named client prims + text objects | ImGui: a transparent click-through full-screen window; rectangles/images on its draw list in creation order, text on top |
| Text size | Segoe UI via the client | ImGui's own font, scaled; layout metrics are re-measured from it at runtime (`ui/metrics.lua: set_platform`) |
| Mouse | Windower `mouse` event | Ashita `mouse` event mapped to the same type codes; clicks over the panel are blocked from the game |
| Settings | `config` library | own small store, `qmui_settings_data.lua` next to the addon (no dependency on Ashita's `settings` lib) |
| Packets | `packets` library | `qm_packets.lua` (shared with the questmarks port) |
| Names | `res/*.lua` files | Ashita's resource manager (zones, items, key items) |

## NOT verified in game
Run headlessly against mocks only (packets → quest model → panel → draw calls → simulated clicks). Most likely to need
adjusting; `/qmui diag` reports what was found:

- **Drawing path** — the ImGui calls (`Begin`, `GetWindowDrawList`, `SetWindowFontScale`, `PushStyleColor`, `TextUnformatted`). `/qmui diag` shows `draw backend`, per-type counts and the last draw error.
- **Fonts** — text uses ImGui's font, so it will not look like the Windower screenshot, and bold/italic are approximated (bold = second pass). Vertical alignment in rows is approximate. A proportional custom ImGui font may wrap words slightly early.
- **Size** — Windower's UI space was scaled; here positions are real pixels. If it looks small on a large monitor: `/qmui scale 1.5` (range 0.6–2.5).
- **Textures** — same loader as the questmarks port (D3DX via ffi); the book/page artwork needs it.
- **Mouse** — wheel direction and coordinates assumed to match the other mapping above; if clicking lands in the wrong place, send `/qmui diag`.
- **Item / key-item names** in step detail use `GetItemById(...).Name[1]` and `keyitems.names`; if they show as ids, that is the lookup.
- The optional **descriptions and step notes** read questmarks' `build/` folders if present; the Ashita questmarks port does not ship them, so they are normally absent (nothing breaks).
- First click after loading may pause briefly (same as the original's known issue).

## Tests
`texlua tests/smoke_headless.lua` (and `tests/smoke_late_load.lua`) from this folder (any Lua with `//` operators, 5.3+) runs a mock-Ashita smoke test.

## License
MIT (see `LICENSE`), original by DrNefarius. Art provenance in `NOTICE`. Quest data comes from the questmarks addon (its own licences apply).
