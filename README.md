# AnimeShopMCP

A dev tool for people writing MelonLoader mods for **Anime Shop Simulator**. It lets Claude Code
inspect and drive a running copy of the game: read shelves and employees, take screenshots, move the
player, spawn boxes, change the clock, and poke arbitrary fields and methods through reflection.

**This is a dev tool, not a mod for players.** It changes saves, it has no safety rails against a
careless command wrecking one, and it opens a local socket with no auth. Use a save you don't mind
breaking, and never ship the bridge mod (`AnimeShopBridge.dll`) to players.

Two halves:

- **`Bridge/`** — `AnimeShopBridge`, a MelonLoader mod (net48) you build and drop into the game's
  `Mods` folder. It opens a newline-delimited JSON line server on `127.0.0.1:47831` and runs each
  command on Unity's main thread. See [`Bridge/README.md`](Bridge/README.md) for the protocol.
- **`Server/`** — `AnimeShopMcp`, a .NET 10 console MCP server (stdio) that Claude Code launches. It
  forwards each tool call to the bridge over that socket. `Tests/` covers it with 17 xUnit tests that
  run without the game.

It also ships as a Claude Code plugin marketplace, so installing it is two slash commands.

## Install

You need the game and Windows; the server and the mod both build with Visual Studio-class tooling but
this has only been exercised on Windows so far.

**1. Install the plugin in Claude Code:**

```
/plugin marketplace add AnimeShopSimulatorMods/AnimeShopMCP
/plugin install anime-shop-mcp@animeshop-mcp
```

**Requirements:**

- [.NET 10 SDK](https://dotnet.microsoft.com/download) — the plugin's launcher builds the server itself
  on first run, so you don't need to build it by hand.
- Anime Shop Simulator with [MelonLoader 0.7.x](https://github.com/LavaGang/MelonLoader/releases)
  already installed.

**2. Point the server at your game folder.** Add `GAME_PATH` (and, only if you changed the bridge's
port, `GAME_BRIDGE_PORT`) to Claude Code's `env` settings, e.g. in `settings.json`:

```json
{
  "env": {
    "GAME_PATH": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Anime Shop Simulator",
    "GAME_BRIDGE_PORT": "47831"
  }
}
```

`GAME_PATH` is only needed for the `read_log` tool, which reads `MelonLoader/Latest.log` straight off
disk. Everything else talks to the bridge over the socket and doesn't need it.

**3. Build and install the bridge mod** (this repo, not the plugin install, does this part):

```bash
git clone https://github.com/AnimeShopSimulatorMods/AnimeShopMCP
cd AnimeShopMCP
```

If the game isn't installed at the default Steam path, write your own path into
`Directory.Build.local.props` in the repo root (gitignored, so it's yours to keep):

```xml
<Project><PropertyGroup><GamePath>D:\Games\Anime Shop Simulator</GamePath></PropertyGroup></Project>
```

Then, with the game **closed** (it locks the mod DLL while running):

```bash
dotnet build Bridge -c Release
```

This copies `AnimeShopBridge.dll` into `<game>\Mods` for you — no manual copy step. Start the game and
load a save.

**4. Check it worked.** The MelonLoader console/log should show:

```
Anime Shop Bridge 0.1.0 listening on 127.0.0.1:47831.
```

Then, in Claude Code, run the `ping` tool. It should report the bridge's version and its full command
list.

## What Claude can do with it

Each bridge command is exposed as an MCP tool of the same name. `ping` is the authoritative source for
what's actually available — it returns the bridge's live command list, which is worth trusting over any
list below if they ever disagree.

- **State** — `game_status`, `shelves`, `employees`, `boxes`: read-only queries over the shop's current
  state.
- **Cheats** — `progress`, `box_catalog`, `spawn_boxes`, `clear_boxes`, `time`, `time_scale`,
  `employee`, `empty_shelf`, `buyers`: shortcuts for testing, most of which write to the save.
- **Reflection** — `find_objects`, `get`, `set`, `call`, `mod_call`, `mod_prefs`: read or write any
  field, or call any method, on a live object, a static type, or a loaded mod — the escape hatch for
  everything the other tools don't cover.
- **Visual** — `screenshot`, `teleport`, `look_at`: see what the game shows, and move or aim the player.
- **Input** — `key_press`, `key_down`, `key_up`, `key_release_all`, `type_text`, `mouse_move`,
  `mouse_click`: drive the game like a keyboard and mouse would, through Win32.
- **Wait** — `wait`: let the game run for real seconds or in-game minutes before replying.
- **Log** — `read_log`: read MelonLoader's log from disk; the only tool that works with the game closed.

## Development

| Path | What's there |
|---|---|
| `Bridge/` | The `AnimeShopBridge` MelonLoader mod (net48) |
| `Bridge/Commands/` | One file per command group; `Registry.cs` wires them all into the dispatcher |
| `Bridge/Net/` | The line server and command dispatcher |
| `Bridge/Reflection/` | The `get`/`set`/`call`/`find_objects`/handle-table machinery |
| `Bridge/Input/` | The Win32 `SendInput` wrapper |
| `Bridge/Game/` | Shared game-access code (see below) |
| `Server/` | `AnimeShopMcp`, the .NET 10 MCP server |
| `Server/Tools/` | One file per tool group, mirroring `Bridge/Commands/` |
| `Tests/` | xUnit tests for the server and the bridge's networking, run without the game |
| `scripts/run-server.ps1` | The launcher Claude Code actually runs |
| `.claude-plugin/` | Marketplace and plugin manifests |

Rebuild the server after changing anything under `Server/`:

```bash
dotnet build Server -c Release
```

Then restart Claude Code — it only reads `.mcp.json` and starts the server at session start, so that's
the only way it picks up a new build. If Claude Code is already holding the session's copy of the exe
open, `dotnet build Server -c Release` into the normal output path will fail to overwrite it; build
straight into the live copy instead:

```bash
dotnet build Server -c Release -o Server/bin/live
```

(`scripts/run-server.ps1` is the reason this works: it runs from `Server/bin/live`, a copy it refreshes
from `Server/bin/Release` at startup, specifically so a running session doesn't lock the build output.)

Run the tests with:

```bash
dotnet test Tests
```

The game locks `Mods\AnimeShopBridge.dll` while it's running, so **close the game before rebuilding the
bridge** with `dotnet build Bridge -c Release`.

## Verified facts and caveats

A few behaviors here aren't obvious from the API surface, so they're recorded rather than left to be
rediscovered:

- **Input** (`key_press`, `key_down`/`key_up`, `type_text`, `mouse_move`, `mouse_click`) goes through
  Win32 `SendInput`, not the game's own input system, and the bridge brings the game window to the
  foreground before sending anything. That means an input command can interrupt whatever you're typing
  or clicking elsewhere on the same machine at the time — don't run one while you need the keyboard or
  mouse yourself.
- **`look_at`** writes the player camera controller's `ViewAngles` directly, not the camera's transform
  (the game recomputes the transform from `ViewAngles` every `LateUpdate`, so writing the transform
  would just be overwritten a frame later).
- **`teleport`** stands the player off from the target along its *back*, not its front — a shelf's
  `forward` points into the wall it's mounted against, so the back is the side a player actually stands
  on to shop it.
- **Screenshots** land in `<game>\UserData\AnimeShopBridge\shots\`; the `screenshot` tool reads the file
  back as an image and deletes it, so that folder is a hand-off point, not storage.
- **Save-changing tools**: `progress`, `spawn_boxes`, `clear_boxes`, `time`, `employee`, `empty_shelf`
  always change the save; `set`, `call`, and `mod_call` can, depending on what you point them at. Load a
  save you don't mind breaking before using any of these. Everything else (`shelves`, `game_status`,
  `screenshot`, `find_objects`, `get`, and so on) only reads state.

More protocol-level detail — the exact wire format, the port, and the full command list as the bridge
itself reports it — is in [`Bridge/README.md`](Bridge/README.md).

## Where the mods being tested live

The mods this tool was built to test — Smart Restock Employees, Cheat for Dev, and Employee Overtime —
live in a separate repo, [`animeshopmod`](https://github.com/1REDfriend/animeshopmod). `Bridge/Game/`
holds copies of game-access code shared with that repo (service lookups, shelf finding, the cheat
implementations); it's duplicated rather than referenced so this repo can stand alone.

## License

MIT — see [LICENSE](LICENSE).
