# questmarks-ui

Your **accepted** quests as a browsable in-game list, grouped by the game's own
quest-log regions, built on [questmarks](https://github.com/DrNefarius/questmarks/)' data.

Two versions live in this repository:

| | Platform | Version | Author |
|---|---|---|---|
| **Ashita v4 port** | Ashita v4, Windows or Linux/Proton | port **0.3.9** | **Semil** |
| Original | Windower 4 | 1.0.0 | **DrNefarius** |

The port keeps the original's quest model, layout and data and replaces only the platform layer.
Everything below applies to both unless a heading says otherwise. Commands are written the Ashita way
(`/qmui`); on Windower, type `//qmui`.

**Contents**

- [Install](#install)
- [Requires](#requires)
- [What it does](#what-it-does)
- [Commands](#commands)
- [Ashita port notes](#ashita-port-notes)
  - [Which server? `/qm expansions`](#which-server-qm-expansions)
  - [Late load and the saved quest log](#late-load-and-the-saved-quest-log)
  - [How it was ported](#how-it-was-ported)
  - [Verified in game, and what is not](#verified-in-game-and-what-is-not)
- [Tracking down a freeze, crash or slowdown](#tracking-down-a-freeze-crash-or-slowdown)
- [Port changelog](#port-changelog)
- [Testing](#testing)
- [Credits and licence](#credits-and-licence)

## Install

### Ashita v4

1. Install the Ashita port of **questmarks** first (clone `main`, or download the latest [release](https://github.com/jimm0thy/questmarks/releases)), at `Ashita/addons/questmarks/` (it does not need to be loaded,
   but loading it keeps the saved quest log fresh, see [Late load](#late-load-and-the-saved-quest-log)).
2. Put this addon at `Ashita/addons/questmarks-ui/`, so that `questmarks-ui.lua` sits directly inside it. Either clone `main`:
   ```
   git clone https://github.com/jimm0thy/questmarks-ui Ashita/addons/questmarks-ui
   ```
   or download the latest zip from the [Releases](https://github.com/jimm0thy/questmarks-ui/releases) page and rename the folder (GitHub adds a suffix such as `-main`).
3. `/addon load questmarks-ui`

A closed book appears. Click it to open the log, click it again to close, drag it wherever you like and it
stays there. `/qmui` (or `/questlog`) also opens and closes it, so it can go on a macro. `/qmui help` lists every
command. If you would rather have nothing on screen until you ask, `/qmui icon off` hides the book entirely; the
addon then makes no drawing calls at all until you open the log with `/qmui`.

If questmarks is somewhere else: `/qmui path <folder>`. By default the addon looks for the sibling folder `../questmarks/`.

### Windower 4 (original)

Download or clone this repository into your Windower `addons` folder, so that
it sits at `Windower4/addons/questmarks-ui/` (you might need to remove the suffixes that GitHub adds when downloading (`-1.0.0`) or cloning (`-main`)), then in game:

```
//lua load questmarks-ui
```

A closed book appears. Click it to open the quest log, click it again to close.
Drag it wherever you like and it stays there. `//qmui` still opens and closes the
log, so it can go on a macro.

**!! KNOWN ISSUE: The first click into the UI after loading could take a couple of seconds during which time the game does not seem to respond. Just give it a couple of seconds and it'll return back to normal and every subsequent click will be fast. !!**
On Ashita the same first-open pause is the one-time scan of the step notes and descriptions (about half a second
each on the author's machine); it happens once per load.

## Requires

**questmarks, installed**, though not necessarily loaded. It is found
automatically as the sibling folder: `<Windower>/addons/questmarks/` on Windower,
`Ashita/addons/questmarks/` on Ashita. Override with `/qmui path <folder>`. This addon reads questmarks'
data and runs its `core/` modules in its own Lua state. It never writes to questmarks and never modifies it
(the one exception is that the Ashita questmarks port writes its own saved quest log, which this addon only reads).

Two features read questmarks' `build/` off your own disk rather than shipping any
of it: each quest's **description**, which is the text of your own in-game quest
log, from `build/rendered/`; and each step's **player-facing note** from
`build/authored/`. Without them the two features are simply absent: no
description, no notes, and a step with no note stops being expandable. Nothing
else changes and nothing breaks.

**On Ashita the `build/` folders come with a `main` checkout or a release download of questmarks.**
If `/qmui diag` says `step notes: unavailable` or `descriptions: ... not present`, copy questmarks' `build/` folder
into `Ashita/addons/questmarks/` (it holds `build/authored/` and `build/rendered/`, about 16 MB). The notes also
read `tools/pipeline/lib/player_voice.json` from questmarks. With them present, `/qmui diag` reports, for example,
`reading build/authored (6459 notes over 1542 quests, 523 ms)` and `reading build/rendered (1723 quests, 319 ms)`.
The addon never starts a command shell to look for them.

If questmarks is missing, is the wrong version, or the game has not sent your
quest log yet, the panel says which in a sentence and does nothing else. It never
throws. `/qmui diag` reports exactly what it found, including which of these
optional pieces are present.

## What it does

![questmarks-ui working in game](assets/preview.png "showing the 'mixed' style")
*(showing the 'mixed' style)*

- **Grouped by region**, using the client's own quest-log sections. Collapsible,
  in a fixed order, each with its own badge from BG Wiki's category artwork.
- **A coloured mark per row**, its hue taken from questmarks' own
  `render/markers.lua` at runtime so it cannot drift from the world: yellow
  quest, green mission, red Campaign, blue for a repeatable this character has
  been seen to finish before. `!` means you are still working on it, `?` means it
  is ready to hand in. Beside it, where to go: NPC, zone, map grid, and a bar
  showing how much of the ladder is confirmed rather than guessed.
- **A detail pane on demand**, opening only when you select something. It carries
  the step ladder with a verdict on each step, what the step needs you to be
  carrying, where those items drop from, the game's own quest description, and a
  player-facing note. The last two come from questmarks' `build/`, see
  [Requires](#requires).
- **Honest about what it cannot see.** 5631 of the index's 6866 steps carry no
  evidence the client will report, so the ladder often cannot tell which of
  several steps you are on. It says so, and shows what each one involves rather
  than pointing at one of them.
- **Four backgrounds** switchable with `/qmui bg <name>`, each held to a
  measured contrast floor by the test suite, and `/qmui opacity <n>` to see
  the world through the panel. Opacity moves the panel surfaces only: the text
  keeps its own alpha, so those contrast floors still describe what is drawn.


## Commands

Written as on Ashita (`/qmui`); on Windower type `//qmui`.

| | |
|---|---|
| `/qmui` | open / close |
| `/qmui accepted` / `handin` / `here` | everything accepted (default) / only what is ready to hand in / only what is in this zone |
| `/qmui search <text>` | filter by quest or region name; no argument clears |
| `/qmui next` / `prev` / `pick <n>` | move the selection |
| `/qmui scroll <n>` / `top` / `bottom` | scroll the list |
| `/qmui steps <n>` | scroll the detail pane |
| `/qmui fold <region>` / `foldall` / `unfoldall` | collapse regions |
| `/qmui list` | print the whole list to chat instead |
| `/qmui pos <x> <y>` / `scale <0.6-2.5>` | move / resize |
| `/qmui icon` / `icon on` / `icon off` | show or hide the book |
| `/qmui icon pos <x> <y>` | move the book without the mouse |
| `/qmui bg <name>` | pane background: navy, leather, parchment or mixed |
| `/qmui opacity <0.15-1>` | how solid the panel is; no argument reports it |
| `/qmui path <folder>` | where questmarks is installed |
| `/qmui reload` / `diag` | re-read the index / what is loaded |
| `/qmui outline light` / `full` / `off` | *(Ashita)* text outline: `light` (default) is one drop shadow, `full` the original four-way outline, `off` none. Fewer copies means far fewer vertices drawn |
| `/qmui expansions` | *(Ashita)* shows the questmarks expansions setting this addon follows |
| `/qmui blackbox on` / `off` | *(Ashita)* writes one status line every 10 s to `blackbox.log`, for tracking down freezes |
| `/questlog` | *(Ashita)* same as `/qmui` |

Mouse: click the book to open or close the log and drag it to move it; click a row
to open its detail, a header to fold, the `x` to close, and use the wheel to
scroll. Where the book overlaps the open window the window takes the click,
because this platform gives an addon no z-order control.

## Ashita port notes

### Which server? `/qm expansions`

Whether the first mission of the later-expansion lines (Wings of the Goddess, Campaign, The Voracious Resurgence, ...)
is listed depends on a **questmarks** setting, `/qm expansions on|off` (default **off**, which is right for
HorizonXI). The game reports 0 both for "never started" and for "on the first mission", so with the setting off
those lines show nothing until you have really progressed. This addon only follows the setting: change it in
questmarks, then run `/qmui reload`. `/qmui expansions` shows the value in use. questmarks' README explains when
to turn it on.

### Late load and the saved quest log

The server only sends your quest log when you zone, so an addon loaded mid-session would otherwise sit on
"Reading your quest log..." until the next zone. questmarks keeps a copy of the last quest-log packets it saw per
character (`questmarks/qm_log_cache.lua`), and this addon replays it once when nothing has arrived yet. A real packet
replaces the copy the moment one arrives. Keep questmarks loaded, ideally at login, so the copy stays fresh.
`/qmui diag` shows which source is in use.

### How it was ported

The original draws through one file (`ui/draw.lua`) and talks to Windower through a handful of calls, so only those
changed:

| Piece | Windower original | Ashita port |
|---|---|---|
| Drawing | named client prims + text objects | ImGui: a transparent click-through full-screen window; rectangles/images on its draw list in creation order, text on top. When nothing is visible no ImGui calls are made |
| Text size | Segoe UI via the client | ImGui's own font, scaled; layout metrics are re-measured from it at runtime (`ui/metrics.lua: set_platform`) |
| Text outline | stroked text | one drop shadow by default (`/qmui outline`) |
| Zoning | n/a | nothing is drawn from the "leaving zone" packet (0x00B) until 3 s after the "arrived" packet (0x00A), and textures are re-created afterwards; a 30 s limit makes sure the UI can never stay hidden |
| Mouse | Windower `mouse` event | Ashita `mouse` event mapped to the same type codes; clicks over the panel are blocked from the game |
| Settings | `config` library | own small store, `qmui_settings_data.lua` next to the addon (no dependency on Ashita's `settings` lib) |
| Packets | `packets` library | `qm_packets.lua` (shared with the questmarks port) |
| Names | `res/*.lua` files | Ashita's resource manager (zones, items, key items) |
| Folder listing | `windower.get_dir` | `ashita.fs.get_dir`; the original's shell fallback (`dir /b`, for its offline tests) is disabled in the game |

### Verified in game, and what is not

Reported working in game on HorizonXI (Ashita v4, on Windows and on Linux/Proton): the book and panel draw, clicking
and dragging, the quest list, the saved-quest-log replay, the expansions setting, step notes and descriptions from
`build/`, and repeated zoning with the icon on and with the panel open.

Not specifically checked, so the first suspects if something looks off (`/qmui diag` reports what it found):

- **Fonts.** Text uses ImGui's font, so it does not look like the Windower screenshot, and bold/italic are
  approximated (bold is a second pass). Vertical alignment in rows is approximate.
- **Size.** Windower's UI space was scaled; here positions are real pixels. If it looks small on a large monitor:
  `/qmui scale 1.5` (range 0.6-2.5).
- **Mouse wheel direction** and coordinates are assumed to match the mapping above. If clicking lands in the wrong place, send `/qmui diag`.
- **Item and key-item names** in the step detail use `GetItemById(...).Name[1]` and `keyitems.names`; if they show as ids, that is the lookup.

## Tracking down a freeze, crash or slowdown

If the game freezes or crashes while this addon is loaded, these help to tell whether the addon is involved. All
are off unless you turn them on.

- **`/qmui blackbox on`** appends one status line every 10 seconds to `blackbox.log` in the addon folder: time, Lua
  memory, draw counts, draw errors, the draw mode (`paused (zoning)`, `idle`, `overlay window`, ...) and whether the
  panel is open. After a freeze the last line shows what the addon was doing. It is not remembered across reloads.
- **`notex.flag`**: an empty file with this name in the addon folder stops it loading or drawing any texture;
  images become grey squares. Reload the addon after adding or removing it.
- **`nodraw.flag`**: an empty file with this name makes the addon run but draw nothing and make no ImGui calls.
  If a problem disappears with this file present, it is in the drawing; if not, it is somewhere else.
- **`/qmui icon off`** with the panel closed: the addon makes no drawing calls at all.

What was found while tracking down freezes on Linux/Proton (CachyOS, Proton CachyOS 10.0, DXVK):

- Crashes to the desktop right after zoning, while the book icon was on screen, stopped once the zoning pause above
  was added (an invalid-pointer read inside DXVK's `d3d9.dll`); this was checked over roughly twenty zones and an
  extended session, not exhaustively.
- Freezes that happened when opening the **RetroAchievements** addon's UI, or interacting with the **Minimap**
  plugin, were traced to stack overflows in `Ashita.dll` itself, at the same address in two separate logs, with
  this addon idle at the time. They are not caused by this addon.
- Debugging on Linux: launch with `PROTON_LOG=1`; the log is `steam-<appid>.log` in your home folder and is
  very large. The useful lines are `Exception 0x...` ones, e.g.
  `grep -n 'backtrace: --- Exception' steam-*.log | grep -v '0x800706ba\|0x6be'`. The `0x800706ba` and `0x6be`
  errors are only Wine shutting down after the real crash.

## Port changelog

| Port | Change |
|---|---|
| 0.1.0 | Ashita v4 port: ImGui drawing, Ashita mouse and packet events, own settings store |
| 0.2.0 | Replays the quest log questmarks saved, so a late load no longer waits for a zone |
| 0.3.1 | Follows questmarks' `/qm expansions` setting; `/qmui expansions` |
| 0.3.2 | A failing handler is logged 3 times and then every 5000th, so it can never flood disk and chat |
| 0.3.3 | `/qmui blackbox` |
| 0.3.4 | `notex.flag` |
| 0.3.5 | `nodraw.flag` |
| 0.3.6 | No ImGui calls at all while nothing is visible (panel closed and icon off) |
| 0.3.7 | Lighter text outline by default; `/qmui outline` |
| 0.3.8 | Drawing paused while zoning; textures re-created after |
| 0.3.9 | The addon never starts a command shell in the game |

## Testing

**Ashita port.** `texlua tests/smoke_headless.lua` and `texlua tests/smoke_late_load.lua` (any Lua 5.3+) from this
folder run a mock-Ashita smoke test: packets, quest model, panel, draw calls and simulated clicks. The late-load
test expects questmarks as the sibling folder. The tests are not needed to run the addon.

**Original (Windower).**

```bash
luajit tools/smoke.lua
```

Loads the addon against a stub client, drives every command, feeds real `0x056`
packets through the real handler, exercises every degradation path, and rasterises
the recorded draw calls to ASCII so layout can be checked without the game. It
asserts, among other things, that unload leaves **zero** named prims behind,
because an orphan stays on screen until Windower restarts.

```bash
luajit tools/check_dialect.lua
```

Refuses constructs the in-game Lua 5.1 cannot parse. The harness runs LuaJIT,
which accepts Lua 5.2 `goto`, so a green suite is not by itself evidence that the
addon loads. It runs first inside `smoke.lua` too.

Both scripts want **LuaJIT**, and both work out where they are from their own
invocation path rather than the working directory, so they run from a clone
anywhere and from an absolute path out of another directory.

The Python scripts in `tools/` regenerate assets and are not part of testing:
`genmetrics.py` rebuilds the font width table, `make_category_icons.py` the
region badges, and `make_pages.py` re-derives the two page sheets from
`papyrus.png`. Run the last one if you replace the papyrus or change either
pane's width. They need Python 3 with Pillow, and `genmetrics.py` reads the
Segoe UI files out of the system font directory.

`make_category_icons.py` also needs the BG Wiki originals, which are not in the
repository because they are the wiki's files rather than this addon's.
`tools/category-sources/fetch_icons.py` downloads them again, re-deriving each
URL from questmarks' cached category pages and rewriting the manifest as it
goes; that directory's README explains the whole chain.

`.gitignore` says what is not published and why. Everything else here ships.

## Credits and licence

**Ashita v4 port by Semil.** The original addon, its model layer and its art are DrNefarius'. The port is MIT
licensed like the original (see `LICENSE`); `NOTICE` records the provenance of every asset and the Ashita port.


Quest data, and the entire model layer, are questmarks'. Its `NOTICE` records the
provenance of that data, BG Wiki under CC BY-NC-SA 3.0 and FFXI game content
(C) SQUARE ENIX, and applies unchanged to anything this addon puts on screen.
This is an unofficial, non-commercial fan tool with no affiliation to Square
Enix.

**`assets/papyrus.png` is DrNefarius' own work**, made for this addon, and
`assets/page_left.png` / `page_right.png` are derived from it by
`tools/make_pages.py`. The two book icons are commissioned originals, drawn for
this addon.

**`assets/category/` is third-party and is the only part that is.** The 17 region
badges are derived from BG Wiki's own category images under CC BY-NC-SA 3.0:
attributed, non-commercial, and offered on under the same licence.

`chronicle/ui/` was **read**, to learn how a quest browser is built on this
platform. No code or data comes from it.

`NOTICE` is the full account: every asset, where it came from, the three
CC obligations and how each is met, and why this addon ships no note or
description text of its own.
