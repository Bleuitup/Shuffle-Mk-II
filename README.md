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
	"MarineCommanderSkillBlend": "COMMANDER_ONLY",
	"AlienCommanderSkillBlend": "COMMANDER_ONLY"
}
```

Both default to `COMMANDER_ONLY`, so installing the mod without configuring it does not change how
your server shuffles.

These settings only apply when the shuffle plug-in's `BalanceMode` is `HIVE` and its
`UseCommanderSkill` option is enabled — commander skill is not consulted otherwise. The shuffle
plug-in's own `BlendAlienCommanderAndFieldSkills` setting is **ignored** while this plug-in is
enabled; use `AlienCommanderSkillBlend` instead.

## Reporting

`sh_teamstats` reports the algorithm in use whenever this plug-in is active:

```
Shuffle Mk II v1.0 is active and has replaced Shine's commander skill calculation.
Commander skill blending - Marines: AVERAGE_IF_FIELD_SKILL_HIGHER. Aliens: AVERAGE.
Shuffle results may differ from other servers. Report shuffle issues to the Shuffle Mk II author, not to Shine.
```

This is deliberate. Shine's built-in "another mod has altered the shuffle algorithm" warning only
triggers when the top-level shuffling function is replaced, which this plug-in does not do — so
without the output above, a server would report stock behaviour while shuffling differently.
Shine's source asks mods not to hide this, and the intent there is clearly that players can tell
where to send problem reports.

**Please do not remove or suppress that output.** If you are running this mod, shuffle results on
your server are not stock Shine's, and problems with them are not Person8880's to answer for.

## Status

Experimental and unreleased. Not yet verified in a live round — this plug-in exists specifically to
gather that evidence.

## Credits

The commander skill calculation is adapted from
[Shine](https://github.com/Person8880/Shine) by Person8880, whose `voterandom` plug-in does all the
actual team balancing. This mod only changes one number it feeds on.
