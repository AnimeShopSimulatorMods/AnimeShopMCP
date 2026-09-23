# Anime Shop Bridge

A dev-only MelonLoader mod. It opens a TCP socket in the running game so the [MCP server](../Server)
can inspect and drive it — read shelves and employees, take screenshots, move the player, spawn boxes,
change the clock, even poke arbitrary fields and methods through reflection. **Never ship this to
players.** It has no gameplay purpose and no safety rails against a careless command wrecking a save.

For what this is, how to install it, and what Claude can do with it, see the [root README](../README.md).
This file is the mod's own reference: the protocol, the port, the full command list, and the specifics
behind input, camera, teleport, and screenshots.

## How it works

`Main.cs` opens a newline-delimited JSON line server on `127.0.0.1:47831` and pumps up to 8 queued
commands per frame from `OnUpdate`, so every command runs on Unity's main thread like the rest of the
game's own code. The MCP server is the only client: it holds the socket open for the life of a Claude
Code session and sends one JSON object per line, gets one back.

## Port

Default `47831`. To change it, both sides need to agree:

- In the game: `UserData/MelonPreferences.cfg`, `[AnimeShopBridge]` category, `Port` entry.
- For Claude Code: `GAME_BRIDGE_PORT` in the root `.mcp.json` (or in Claude Code's `env` settings — see
  the root README).

## Commands

The command list is generated, not hand-maintained here — call the `ping` tool (or send `{"cmd":
"ping"}` on the socket) and read `commands` in the reply; it is `dispatcher.Commands` sorted
alphabetically, which is authoritative. As of this mod's version 0.1.0 that list is:

`boxes`, `box_catalog`, `buyers`, `call`, `clear_boxes`, `employee`, `employees`, `empty_shelf`,
`find_objects`, `game_status`, `get`, `key_down`, `key_press`, `key_release_all`, `key_up`, `look_at`,
`mod_call`, `mod_prefs`, `mouse_click`, `mouse_move`, `ping`, `progress`, `screenshot`, `set`, `shelves`,
`spawn_boxes`, `teleport`, `time`, `time_scale`, `type_text`, `wait`.

The MCP server wraps each of these as an MCP tool with the same name and adds one more, `read_log`, that
reads `MelonLoader/Latest.log` straight off disk and works even with the game closed.

## Input

Key and mouse commands (`key_press`, `key_down`/`key_up`, `type_text`, `mouse_move`, `mouse_click`) go
through Win32 `SendInput` with hardware scan codes (`Bridge/Input/Win32Input.cs`), not by writing into
the game's input system. Confirmed working in game 1.0.6: `key_press` held `W` for 1.5 s and moved the
player 4.1 units. The game reads Rewired, Unity's Input System and legacy `Input` all at once, and scan
codes reach all three, so the bridge does not need to know which one is active.

`SendInput` delivers to whatever window is in front, so before sending anything the bridge brings the
game window to the foreground itself: a synthetic Alt tap (the documented way to earn the right to
change the foreground window on Windows) followed by `SetForegroundWindow`. That has been enough every
time so far; the `AttachThreadInput` fallback some guides suggest was never needed. `game_status` and
other read-only commands do not touch focus at all — because `Application.runInBackground` is set
true (in `Main.cs`), the bridge can read and change state while the game window is not focused, and only
input commands need the window brought forward.

**Focus caveat:** input goes to whichever window is in front at the time, which is the game once
`EnsureFocus` succeeds. If you are typing or clicking somewhere else on the same machine right when a
key or mouse command runs, that gets interrupted instead. Don't run input commands while you need the
keyboard or mouse yourself.

## Look and teleport

**`look_at`** does not write the player's or camera's transform. Anything written there is overwritten
on the very next `LateUpdate`, because the game's `PlayerCameraController` recomputes both from its own
`ViewAngles` every frame. The bridge instead sets `ViewAngles` (x = pitch, y = yaw) directly, clamped to
the controller's own `_lookLimits` (measured in game 1.0.6: pitch from about -60 to 90). When aiming at
a handle, it looks at the union of that object's renderer bounds, not its transform position — a
shelf's transform sits on the floor it stands on, so aiming at the transform points the camera at the
boards, not the shelf.

**`teleport`** places the player a `distance` (default 1.5) out from the target along its BACK, not its
front. Measured in game 1.0.6: a shelf's `forward` points into the wall it's mounted against, so the
usable side — where a player actually stands to shop it — is the back. `distance` is how far
out from that side the player lands.

## Screenshots

`screenshot` writes a PNG to `<game>\UserData\AnimeShopBridge\shots\` and waits for the file to stop
growing before replying (Unity writes it at the end of a later frame). The MCP server's `screenshot`
tool reads that file, returns it as an image, and deletes it — the `shots` folder is a hand-off point,
not storage.

## Safety: use a test save

These commands change the save, directly or through the game's own systems: `progress`, `spawn_boxes`,
`clear_boxes`, `time`, `employee`, `empty_shelf`, `set`, `call`, `mod_call`. Load a save you don't mind
breaking before using any of them. Everything else (`shelves`, `game_status`, `screenshot`,
`find_objects`, `get`, and so on) only reads state.
