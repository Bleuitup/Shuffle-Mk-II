# Shuffle Mk II

An experimental Shine plug-in that changes how **commander skill** is used when the shuffle
(`voterandom`) plug-in balances teams.

It exists to test a proposed change to Shine on real servers before suggesting it upstream. It does
not replace the shuffle plug-in — it depends on it, and only alters the way a commander's skill
value is calculated.

## What it changes

Stock Shine has a single option, `BlendAlienCommanderAndFieldSkills`, which averages an alien
commander's commander and field skills to account for them leaving the hive during a round. It is
alien-only, and it is a plain average.

Shuffle Mk II replaces that with a **per-team** setting offering three modes each:

| Mode | Behaviour |
| --- | --- |
| `COMMANDER_ONLY` | Uses the commander skill as-is. Matches stock Shine with blending disabled. |
| `AVERAGE` | Mean of the commander and field skills. Matches stock Shine's alien blending. |
| `AVERAGE_IF_FIELD_SKILL_HIGHER` | Mean only when the field skill is higher, otherwise the commander skill as-is. |

`AVERAGE` is symmetric, so it drags a strong commander's rating *down* when their field skill is
weaker — which under-rates a player who commands well but rarely leaves the chair.
`AVERAGE_IF_FIELD_SKILL_HIGHER` blends only in the direction that reflects time actually spent in
the field.

## Installation

1. Subscribe to the mod on the Steam Workshop.
2. Add the Workshop ID to the `mods` field of your `MapCycle.json`. See the
   [NS2 dedicated server wiki](http://wiki.unknownworlds.com/ns2/Dedicated_Server) for details.
3. Change map or restart the server.
4. Enable the plug-in and configure it (below).

Requires Shine, and requires the `voterandom` (shuffle) plug-in to be enabled. Shine will refuse to
enable Shuffle Mk II without it.

## Configuration

Settings live in `config://shine/plugins/ShuffleMkII.json`, alongside your other Shine plug-in
configs.

```json
{
	// COMMANDER_ONLY, AVERAGE, or AVERAGE_IF_FIELD_SKILL_HIGHER. Both default to COMMANDER_ONLY,
	// which is how Shine rates a commander when blending is off.
	"MarineCommanderSkillBlend": "COMMANDER_ONLY",
	"AlienCommanderSkillBlend": "COMMANDER_ONLY"

	// This mod also restores the server's file consistency checking when the server can't be ranked.
	// The bug: after a failed ranking request the game skips setting consistency up, so players'
	// own client-side mods load when they shouldn't and disconnect them with "Invalid data".
	// There is no setting for it. It is automatic, and does nothing on a server that is ranked.
}
```

Shine's config reader accepts `//` and `/* */` comments, so you can annotate the file. Shine only
rewrites it when it has to add a missing setting or correct an invalid one — a rewrite drops your
comments, so keep a copy if you care about them.

Both settings default to `COMMANDER_ONLY`, so installing the mod and leaving it alone rates
commanders exactly as Shine does with blending switched off.

### It forces commander skill on

Every mode above is a function of the commander's commander skill, so this plug-in turns the shuffle
plug-in's `UseCommanderSkill` on for as long as it is enabled, whatever your shuffle config says.
`sh_teamstats` states this, and disabling the plug-in hands the setting straight back.

**If you had `UseCommanderSkill` off deliberately, read this.** The usual reason to turn it off is
that a commander who leaves the chair early is still rated at commander skill all round. Enabling
this plug-in and leaving both settings at `COMMANDER_ONLY` gives you exactly that behaviour back.
Set at least one team to `AVERAGE_IF_FIELD_SKILL_HIGHER` or `AVERAGE`, which is the reason this
plug-in exists.

These settings only apply when the shuffle plug-in's `BalanceMode` is `HIVE`; commander skill is not
consulted in the other modes. The shuffle plug-in's own `BlendAlienCommanderAndFieldSkills` setting
is **ignored** while this plug-in is enabled; use `AlienCommanderSkillBlend` instead.

## Reporting

`sh_teamstats` reports the algorithm in use whenever this plug-in is active:

```
Shuffle Mk II v1.13 is active and has replaced Shine's commander skill calculation.
Commander skill is forced on by this plug-in, overriding the shuffle plug-in's UseCommanderSkill setting of false.
Commander skill blending - Marines: AVERAGE_IF_FIELD_SKILL_HIGHER. Aliens: AVERAGE.
Shuffle results may differ from other servers. Report shuffle issues to the Shuffle Mk II author, not to Shine.
```

If `UseCommanderSkill` was already on, the second line says so instead of claiming to override
anything.

This is deliberate. Shine's built-in "another mod has altered the shuffle algorithm" warning only
triggers when the top-level shuffling function is replaced, which this plug-in does not do — so
without the output above, a server would report stock behaviour while shuffling differently.
Shine's source asks mods not to hide this, and the intent there is clearly that players can tell
where to send problem reports.

**Please do not remove or suppress that output.** If you are running this mod, shuffle results on
your server are not stock Shine's, and problems with them are not Person8880's to answer for.

## Shuffle log

Every Hive shuffle is logged in two levels of detail: a short summary for the console, and a full
per-player breakdown in Shine's log file.

### The console summary

One line per team, and one more per team that had a commander. Four lines at most.

```
[Shuffle Mk II] Shuffled teams - Marines: average skill 2325 across 2 players (2 counted).
[Shuffle Mk II] Shuffled teams - Marines commander Someone counted as 2650 (commander skill 1600, field skill 3700, blend AVERAGE_IF_FIELD_SKILL_HIGHER).
[Shuffle Mk II] Shuffled teams - Aliens: average skill 1838 across 2 players (2 counted).
[Shuffle Mk II] Shuffled teams - Aliens commander AnotherComm counted as 2176 (commander skill 497, field skill 3855, blend AVERAGE_IF_FIELD_SKILL_HIGHER).
```

### The full breakdown

One row per player, written to `config://shine/logs/<date>.txt` and **not** to the console, so a
busy server keeps a readable console while the data is still collected. Rows are pipe-delimited for
later analysis and carry the same `[Shuffle Mk II]` prefix, so `grep` separates them cleanly.

```
[Shuffle Mk II] Shuffle detail - modes: Marines AVERAGE_IF_FIELD_SKILL_HIGHER, Aliens AVERAGE_IF_FIELD_SKILL_HIGHER. Per-team skill: disabled.
[Shuffle Mk II] Shuffle detail - Marines | Someone | counted 2650 | field 3700 | commander 1600 | blend AVERAGE_IF_FIELD_SKILL_HIGHER
[Shuffle Mk II] Shuffle detail - Marines | SomeoneElse | counted 2000 | field 2000 | commander - | blend -
[Shuffle Mk II] Shuffle detail - Aliens | AnotherComm | counted 2176 | field 3855 | commander 497 | blend AVERAGE_IF_FIELD_SKILL_HIGHER
[Shuffle Mk II] Shuffle detail - Aliens | Another | counted 1500 | field 1500 | commander - | blend -
```

`counted` is the value the shuffle actually used for that player. `commander` and `blend` show as
`-` for anyone who was not in the chair at the time.

The log file also receives a copy of the console summary, since Shine writes console output to it
as well. Lines appear in the order above.

**Player names are logged without Steam IDs**, so the log can be shared for analysis without
exposing accounts.

**The rows need Shine's own `EnableLogging`**, which is on by default. With it off you keep the
console summary and lose the rows; the plug-in says so once rather than failing quietly.

Shine buffers its log and flushes on round end, map change and every five minutes, so a round's
rows are on disk by the time the round is over. `sh_flushlog` forces it.

Only Hive shuffles are logged, since commander skill is not consulted in the other balance modes.
A team with no commander gets no commander line — commonly the case, since blending applies only to
a player sitting in the chair at the moment the shuffle runs.

Set the level to quieten it:

```
sh_setloglevel shufflemkii WARN
```

or `LogLevel` in `ShuffleMkII.json`. The default, `INFO`, logs.

**Adding this setting means Shine rewrites `ShuffleMkII.json` once** to insert `LogLevel`, which
discards any comments you had added to that file. Only happens on the upgrade.


## Development

The plug-in lives in `source/lua/shine/extensions/shufflemkii/`: `shared.lua` declares it and
`server.lua` holds all of the logic. `source/` is stripped at build time, so the runtime path is
`lua/shine/extensions/shufflemkii/`.

Logic tests run against the real plug-in file with a standalone Lua interpreter:

```
lua test/blend.lua
lua test/shuffle_log.lua
```

See `CLAUDE.md` for how the plug-in hooks into Shine and what must be kept in sync with upstream.

## Status

Experimental. Published to the Steam Workshop as `3798409220`.

**This mod is not on UWE's whitelist, so a server running it cannot be ranked.**

Because of a bug in the game, a server that can't be ranked also stops checking players' files
altogether. Players' own client-side mods then load when they shouldn't, and any that register
network messages (Devnull - Enhanced Hud, for example) get those players disconnected with
`Invalid data`. This affects any non-whitelisted mod, not this one in particular.

To avoid that, this mod restores the file checking the game skipped, using the game's own standard
settings, and says so in the server log. It only does this when the server couldn't be ranked anyway,
and it leaves your own consistency settings alone if you've set them. The bug itself has been
reported to UWE. See `CLAUDE.md` for the detail.

## Credits

The commander skill calculation is adapted from
[Shine](https://github.com/Person8880/Shine) by Person8880, whose `voterandom` plug-in does all the
actual team balancing. This mod only changes one number it feeds on.
