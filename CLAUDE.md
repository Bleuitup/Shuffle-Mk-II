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
source/lua/entry/ShuffleMkII.entry                  registers the file hook below
source/lua/ShuffleMkII/FileHooks.lua                queues the consistency fallback (server only)
source/lua/ShuffleMkII/ConsistencyFallback.lua      runs after the game's consistency setup
test/blend.lua                                      standalone logic tests, not shipped
test/shuffle_log.lua                                standalone tests for the shuffle log, not shipped
test/consistency_fallback.lua                       standalone tests for the fallback, not shipped
output/                                             Launch Pad build output, gitignored
```

`source/` is stripped at build time, so the runtime path is `lua/shine/extensions/shufflemkii/` —
which is what Shine scans for extensions. **Do not** add `source/` to any path referenced from Lua.

Shine discovers the plugin itself by scanning `lua/shine/extensions/`, with no bootstrap needed. The
`.entry` file exists only for the consistency fallback below, which is not a Shine plugin and has to
run before the game's own scripts.

### Layout

`shared.lua` creates the plugin with `Shine.Plugin( ... )` and returns it; `server.lua` receives it
as `local Plugin = ...` and returns nothing. `shared.lua` also sets `DefaultState = false` — without
a default state Shine never records the plugin in `ActiveExtensions`, and re-loads it on every map
change just to check.

Keep `shared.lua` free of server-only concepts. It runs on clients too, so config, the validator
and `DependsOnPlugins` stay in `server.lua`.

v1.0 was a single file, `lua/shine/extensions/shufflemkii.lua`. v1.1 moved to this layout while
chasing the client disconnects below, matching the author's other Shine plugins. **The layout was
not the cause** — v1.1 failed identically — but it is kept because it is conventional and because
`DefaultState` is a real improvement.

## Client disconnects while not whitelisted (solved)

Mounting this mod on NS2 Sudamerica 8v8 disconnected clients on map load with `Invalid data`
("Different number of network messages on the Client from the Server"), even with the plugin
disabled, in both v1.0 and v1.1. **The plugin's code is not involved.** Traced on 2026-09-11 from
the server's and a client's logs:

1. The mod is not yet on UWE's whitelist, so the server logs `Server has non whitelisted mods`,
   disables ranking, and **skips its entry-file consistency hashing** — on a clean load it logs an
   `EntryHash` line for every `lua/entry/*.entry`; with this mod mounted it logs none.
2. Consistency checking is what normally stops players' own client-side mods loading. On a clean
   connection the client logs, for example,
   `Mod Devnull - Enhanced Hud failed consistency checking and will be disabled`. With checking
   off, those mods mount (the failing connection mounted 31 mods against 28 on a clean one).
3. `Devnull - Enhanced Hud` (Workshop `3765927260`) registers the network message
   `BiomassNotificationLocation` from its FileHooks, which run on the client. The server does not
   run that mod, so the client has one more network message than the server and is dropped.

So **any** non-whitelisted mod mounted on that server will disconnect players who run a
client-side mod that registers network messages. Players without such mods are unaffected.

### The fallback (added 2026-09-22)

The root cause is in the game, not in any mod: `core/lua/ConsistencyConfig.lua` asks for ranking and
then returns whether or not the request succeeded, so when a non-whitelisted mod makes it fail, the
code below that builds the consistency table never runs. Reported to UWE (see `UWE-Consistency-Report`
in the workspace; the suggested fix is to return only when `ok` is true).

`ConsistencyFallback.lua` finishes that job from the mod: a `post` file hook on
`lua/ConsistencyConfig.lua` (UWE's own bootcamp and challenge mods hook the same file) that, when
`Server.GetIsRankingActive()` is false, builds the table with the game's own default lists. This is
the same end state as setting `"hiveranking": false` in `ServerConfig.json`, which the author didn't
want to require of operators, but scoped so it only acts when ranking was unavailable anyway — it
never costs ranking on a server that could have had it.

It deliberately does nothing when ranking is active, when `consistency_enabled` is off, when
`use_own_consistency_config` is set, or when `hiveranking` is already false: in every one of those
cases the game has already done the right thing. It announces itself in the server log.

**The pattern lists are copied verbatim from the game's defaults and must be kept in step with them.**
They were verified identical to build 344 on 2026-09-22: 20 checked patterns, 1 restricted
(`lua/entry/*.entry`, which is what blocks players' own mods), and 36 ignored — 36, not 35, because
the game's own list contains `ui/alien_hud_health.dds` twice.

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

### It forces the shuffle plugin's commander skill on

Every blend mode is a function of the commander skill, so with voterandom's
`BalanceModeConfig.HIVE.UseCommanderSkill` off, `GetHiveSkill` never enters the commander branch
and this plugin is inert. `OnFirstThink` therefore forces it on and `Cleanup` restores it.

**Override `IsCommanderSkillEnabled`, never the config value.** Shine writes a plugin's config
back to disk whenever validation changes something ([base_plugin/config.lua] line 193), so writing
into voterandom's config table risks persisting the change and outliving this plugin — an operator
would be left with a setting they never chose. `IsCommanderSkillEnabled` is the only reader of the
setting in all of Shine, so overriding the method covers every consumer: ranking, the vote menu's
standard deviation display and happiness optimisation.

This overrides an operator's stated choice, so `PrintAlgorithm` says so, and says whether it is
actually overriding anything or the setting was already on. **Known sharp edge:** enabling this
with both blends left at the `COMMANDER_ONLY` default gives an operator who deliberately disabled
commander skill the exact behaviour they disabled it to avoid. The README warns about this; do not
quietly change the defaults to paper over it without asking the author.

### The shuffle log wraps ShuffleTeams

`OnFirstThink` wraps `VoteShuffle.ShuffleTeams` and calls `Plugin:LogShuffle` after the original
returns; `Cleanup` restores it. The wrapper checks `ShufflePlugin.LastShuffleMode`, which the call
it just made has set and which accounts for a forced mode, rather than reading `Config.BalanceMode`.

`TeamMembers` is a local inside `ShuffleTeams` and is not returned, so the log reads the teams back
from `Gamerules` instead. That reports where players actually ended up rather than where the
algorithm intended to put them, which is the more useful thing when a shuffle looks wrong. **It
assumes every shuffle mode has finished moving players before `ShuffleTeams` returns** — true of the
current modes; if a future mode defers its moves, the log would show the pre-shuffle teams.

`Team:GetPlayers()` hands back the same table on every call (upstream notes this in `GetTeamStats`),
so `LogShuffle` finishes with one team before asking for the next. Do not restructure it to fetch
both up front.

Skill values come from `VoteShuffle:ApplyConfigToRankingFunction( VoteShuffle.SkillGetters.GetHiveSkill )`
and `VoteShuffle:GetAverageSkill`, both public methods, so the log reports exactly what the shuffle
used. `GetAverageSkill` is uncached, unlike `GetTeamStats`, so the numbers cannot be stale.

**Log names with `Shine.GetClientName`, never `Shine.GetClientInfo`** — the latter appends the
Steam ID, and these lines are collected and shared for analysis. NS2 names are not account names.

`Shine.LoadPluginModule( "logger.lua", Plugin )` at the end of `server.lua` supplies `self.Logger`,
the `LogLevel` config setting and `sh_setloglevel`. Adding it changed the config schema, so Shine
rewrites `ShuffleMkII.json` once on upgrade, discarding operator comments — noted in the README.

### The sh_teamstats output is deliberate

Shine detects an altered shuffle by checking whether `ShufflingModes[ Mode ]` still originates from
`team_balance.lua`. This plugin does not replace that function, so **Shine's built-in warning never
fires** — without the explicit output, a server would report stock behaviour while shuffling
differently. Shine's source asks mods not to suppress that warning. Do not remove this output.

## Testing

```
lua test/blend.lua
lua test/consistency_fallback.lua
lua test/shuffle_log.lua
```

`shuffle_log.lua` drives `LogShuffle` and the `ShuffleTeams` wrapper against stubbed teams: 23
assertions covering the line count, the blended numbers, skill offsets, both commanders, the
wrapper restoring cleanly, and the log level.

`consistency_fallback.lua` loads the real `ConsistencyFallback.lua` against a stubbed `Server`: 12
assertions covering every case where it must stay out of the way, and the patterns, order and log
lines when it does act.

`blend.lua` stubs the few Shine globals the plugin touches at load time, then `loadfile`s the real plugin file
and calls `Plugin:GetHiveSkill` directly — so it tests the shipped code, not a copy. 22 assertions
covering all three modes, per-team isolation, the fall-through paths, forcing commander skill on and
restoring it, and what `sh_teamstats` reports.

The `AVERAGE` case asserts 450 against the same fixture Shine's own unit test uses, which confirms
the legacy behaviour is preserved.

These run under a standalone Lua interpreter. Note it is **Lua 5.4 while NS2 runs LuaJIT/5.1**, and
the harnesses do not exercise real player objects
or Shine's loader — it verifies arithmetic and control flow only. Use `luac -p <file>` for a syntax
check. A live round remains the real test.

## Status

Published to the Workshop as `3798409220` (`publish_id` in `mod.settings`, written by Launch Pad).
Not yet whitelisted by UWE, which is what caused the client disconnects described above. The
plugin itself has not yet run in a live round.

When testing a build, check **both** states: mounted with the plugin disabled (where v1.0 failed)
and enabled. A client must actually connect after the map loads — the failure only shows up at the
connection handshake, never in the server's own log as a Lua error.
