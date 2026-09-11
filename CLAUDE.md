# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**Shuffle Mk II** is a server-side **Shine plugin** for **Natural Selection 2**. It changes how a
commander's skill value is calculated when Shine's shuffle (`voterandom`) plugin balances teams,
adding a per-team setting and a one-directional blending rule.

It is an **add-on, not a fork**. Shine's shuffle plugin keeps doing all the balancing; this replaces
one function it calls. `README.md` is the server-admin facing doc; this file is for development.

The blending logic is adapted from **Shine** by **Person8880** —
<https://github.com/Person8880/Shine>.

## Layout

Standard NS2 Launch Pad project layout, matching the author's other mods: `mod.settings` and
`preview.jpg` sit one level **above** the mod content, which lives under `source/`.

```
mod.settings                                        workshop metadata
preview.jpg                                         workshop preview
source/lua/shine/extensions/shufflemkii/shared.lua  declares the plugin (both realms)
source/lua/shine/extensions/shufflemkii/server.lua  all of the logic
test/blend.lua                                      standalone logic tests, not shipped
output/                                             Launch Pad build output, gitignored
```

`source/` is stripped at build time, so the runtime path is `lua/shine/extensions/shufflemkii/` —
which is what Shine scans for extensions. **Do not** add `source/` to any path referenced from Lua.

There is no bootstrap/`.entry` file and none is needed: Shine discovers extensions by scanning
`lua/shine/extensions/`.

### Keep the shared.lua + server.lua layout

v1.0 shipped as a **single file**, `lua/shine/extensions/shufflemkii.lua`. On NS2 Sudamerica 8v8
(2026-09-10), mounting that build disconnected every client with `Invalid data` — the client logged
"Different number of network messages on the Client from the Server" — even with the plugin
**disabled**. Unmounting it fixed it. The server process never crashed and no Lua error was logged.

The exact mechanism was **not** identified: the plugin registers no network messages, and Shine's
own plugin sync treats a single-file plugin symmetrically. v1.1 moved to `shared.lua` + `server.lua`
because that is exactly the layout of the author's other Shine plugins (`lifeformpicker`,
`lockteamsv2`) running on that same server without problems — converging on a known-good shape
rather than fixing a confirmed root cause. **Do not collapse it back into a single file** without
re-testing on a live server with clients connected.

`shared.lua` creates the plugin with `Shine.Plugin( ... )` and returns it; `server.lua` receives it
as `local Plugin = ...` and returns nothing. `shared.lua` also sets `DefaultState = false` — without
a default state Shine never records the plugin in `ActiveExtensions`, and re-loads it on every map
change just to check.

Keep `shared.lua` free of server-only concepts. It runs on clients too, so config, the validator
and `DependsOnPlugins` stay in `server.lua`.

**`output/` is gitignored and must be built before publishing.** The build is
`rm -rf output && mkdir -p output && cp -r source/. output/`, leaving `lua/` at the root of
`output/`. Because it is ignored it does **not** follow branch switches — rebuild after any
checkout before publishing.

`test/` sits outside `source/`, so it is never shipped.

## How it hooks into Shine

`Plugin:OnFirstThink` does two things, both against `Shine.Plugins.voterandom`:

1. Replaces `SkillGetters.GetHiveSkill`. That table is shared by reference with the shuffle
   plugin's balance module and is looked up at call time, so replacing the field covers every path
   that ranks players.
2. Wraps `Shine.Commands[ "sh_teamstats" ].Func` to append which blending rule is active.

`Plugin.DependsOnPlugins = { "voterandom" }` makes Shine refuse to enable this without the shuffle
plugin. `Plugin:Cleanup` restores both, so the plugin can be unloaded cleanly.

### Two helpers are copied from upstream

`GetPlayerTeamSkill` and `GetFieldPlayerSkill` are file-locals in Shine's
`voterandom/team_balance.lua` and cannot be reached from outside, so they are duplicated verbatim.
**If upstream changes how skill offsets are applied, these must be updated to match** or this
plugin will silently disagree with Shine about what a player's field skill is.

### The sh_teamstats output is deliberate

Shine detects an altered shuffle by checking whether `ShufflingModes[ Mode ]` still originates from
`team_balance.lua`. This plugin does not replace that function, so **Shine's built-in warning never
fires** — without the explicit output, a server would report stock behaviour while shuffling
differently. Shine's source asks mods not to suppress that warning. Do not remove this output.

## Testing

```
lua test/blend.lua
```

Stubs the few Shine globals the plugin touches at load time, then `loadfile`s the real plugin file
and calls `Plugin:GetHiveSkill` directly — so it tests the shipped code, not a copy. 12 assertions
covering all three modes, per-team isolation, and the fall-through paths.

The `AVERAGE` case asserts 450 against the same fixture Shine's own unit test uses, which confirms
the legacy behaviour is preserved.

A standalone Lua interpreter is installed at `C:\Users\maost\AppData\Local\Programs\Lua\bin\`. Note
it is **Lua 5.4 while NS2 runs LuaJIT/5.1**, and the harness does not exercise real player objects
or Shine's loader — it verifies arithmetic and control flow only. Use `luac -p <file>` for a syntax
check. A live round remains the real test.

## Status

Published to the Workshop as `3798409220` (`publish_id` in `mod.settings`, written by Launch Pad).
v1.0 broke client connections as described above; v1.1 has not yet been tested on a live server.

When testing a build, check **both** states: mounted with the plugin disabled (where v1.0 failed)
and enabled. A client must actually connect after the map loads — the failure only shows up at the
connection handshake, never in the server's own log as a Lua error.
