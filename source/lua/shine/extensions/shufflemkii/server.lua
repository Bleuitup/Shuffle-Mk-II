--[[
	Shuffle Mk II server code.

	An experimental replacement for Shine's commander skill handling in the shuffle (voterandom)
	plugin, intended for testing on opted-in servers before proposing the behaviour upstream.

	Stock Shine offers a single boolean, BlendAlienCommanderAndFieldSkills, which averages an alien
	commander's commander and field skills. This plugin replaces that with a per-team setting that
	also offers a one-directional blend, so a commander is never rated below their commander skill.

	This plugin deliberately announces itself in sh_teamstats. Shine's own algorithm-change warning
	only triggers when the top-level shuffling function is replaced, which this plugin does not do,
	so without the explicit output below a server would report stock behaviour while shuffling
	differently. See the note in Shine's voterandom/server.lua asking mods not to hide this.
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format
local TableConcat = table.concat

local GetClientForPlayer = Shine.GetClientForPlayer

local Plugin = ...

Plugin.HasConfig = true
Plugin.ConfigName = "ShuffleMkII.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

-- Commander skill handling only exists in the shuffle plugin, so there is nothing to do without it.
Plugin.DependsOnPlugins = {
	"voterandom"
}

Plugin.CommanderSkillBlendType = table.AsEnum{
	"COMMANDER_ONLY", "AVERAGE", "AVERAGE_IF_FIELD_SKILL_HIGHER"
}

Plugin.DefaultConfig = {
	-- How to blend a commander's commander and field skill values, to account for them being out of
	-- the command structure for a significant amount of time during a round. May be one of:
	-- - COMMANDER_ONLY uses the commander skill as-is (matches stock Shine with blending disabled).
	-- - AVERAGE uses the mean of the commander and field skills (matches stock Shine's alien blending).
	-- - AVERAGE_IF_FIELD_SKILL_HIGHER uses the mean only when the field skill is higher, otherwise
	--   uses the commander skill as-is.
	MarineCommanderSkillBlend = Plugin.CommanderSkillBlendType.COMMANDER_ONLY,
	AlienCommanderSkillBlend = Plugin.CommanderSkillBlendType.COMMANDER_ONLY
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRules( {
		"MarineCommanderSkillBlend",
		"AlienCommanderSkillBlend"
	}, Validator.InEnum( Plugin.CommanderSkillBlendType, Plugin.CommanderSkillBlendType.COMMANDER_ONLY ) )

	Plugin.ConfigValidator = Validator
end

-- Copied verbatim from Shine's voterandom/team_balance.lua, where both are file-locals and so are
-- not reachable from here. Keep in sync with upstream.
local function GetPlayerTeamSkill( TeamNumber, Skill, Offset )
	if TeamNumber == 1 or TeamNumber == 2 then
		-- Skill offset provides the actual per-team skill.
		return TeamNumber == 1 and ( Skill + Offset ) or ( Skill - Offset )
	end
	return Skill
end

local function GetFieldPlayerSkill( Ply, TeamNumber, TeamSkillEnabled )
	if Ply.GetPlayerSkill then
		local Skill = Ply:GetPlayerSkill() or 0
		local Offset = Ply.GetPlayerSkillOffset and Ply:GetPlayerSkillOffset() or 0

		return GetPlayerTeamSkill( TeamSkillEnabled and TeamNumber or 0, Skill, Offset )
	end

	return nil
end

-- Blending types that are absent here (i.e. COMMANDER_ONLY) use the commander skill as-is.
local CommanderSkillBlenders = {
	[ Plugin.CommanderSkillBlendType.AVERAGE ] = function( CommanderSkill, FieldSkill )
		return ( CommanderSkill + FieldSkill ) * 0.5
	end,
	-- Blend only when doing so raises the value, to avoid rating a commander below their commander
	-- skill when they rarely leave the command structure.
	[ Plugin.CommanderSkillBlendType.AVERAGE_IF_FIELD_SKILL_HIGHER ] = function( CommanderSkill, FieldSkill )
		if FieldSkill <= CommanderSkill then
			return CommanderSkill
		end
		return ( CommanderSkill + FieldSkill ) * 0.5
	end
}
local CommanderSkillBlendFields = {
	"MarineCommanderSkillBlend",
	"AlienCommanderSkillBlend"
}

function Plugin:Initialise()
	self.Enabled = true
	return true
end

--[[
	Mirrors voterandom's SkillGetters.GetHiveSkill, but resolves the blending type from this
	plugin's own config rather than the shuffle plugin's balance mode config.
]]
function Plugin:GetHiveSkill( Ply, TeamNumber, TeamSkillEnabled, CommanderSkillEnabled )
	local Client = GetClientForPlayer( Ply )
	if Client and Client:GetIsVirtual() then
		-- Bots are all equal so there's no reason to consider them.
		return nil
	end

	if
		CommanderSkillEnabled and Ply.GetCommanderSkill and Ply:isa( "Commander" ) and
		Ply:GetTeamNumber() == TeamNumber
	then
		local CommanderSkill = Ply:GetCommanderSkill() or -1
		if CommanderSkill >= 0 then
			local Offset = Ply:GetCommanderSkillOffset() or 0
			local ResolvedCommanderSkill = GetPlayerTeamSkill(
				TeamSkillEnabled and TeamNumber or 0,
				CommanderSkill,
				Offset
			)

			local BlendType = self.Config[ CommanderSkillBlendFields[ TeamNumber ] ]
			local Blender = CommanderSkillBlenders[ BlendType ]
			if Blender then
				local FieldSkill = GetFieldPlayerSkill( Ply, TeamNumber, TeamSkillEnabled )
				if FieldSkill then
					return Blender( ResolvedCommanderSkill, FieldSkill )
				end
			end

			return ResolvedCommanderSkill
		end
	end

	return GetFieldPlayerSkill( Ply, TeamNumber, TeamSkillEnabled )
end

--[[
	Breaks down how a commander's skill value was arrived at, for the shuffle log below.

	Returns nil for anyone who is not a commander of the team being evaluated, which is also how
	GetHiveSkill decides whether to blend at all, so the two agree by construction.
]]
function Plugin:GetCommanderSkillBreakdown( Ply, TeamNumber, TeamSkillEnabled )
	if not ( Ply.GetCommanderSkill and Ply.isa and Ply:isa( "Commander" ) and Ply:GetTeamNumber() == TeamNumber ) then
		return nil
	end

	local CommanderSkill = Ply:GetCommanderSkill() or -1
	if CommanderSkill < 0 then return nil end

	local BlendType = self.Config[ CommanderSkillBlendFields[ TeamNumber ] ]
	local Breakdown = {
		CommanderSkill = GetPlayerTeamSkill(
			TeamSkillEnabled and TeamNumber or 0,
			CommanderSkill,
			Ply:GetCommanderSkillOffset() or 0
		),
		FieldSkill = GetFieldPlayerSkill( Ply, TeamNumber, TeamSkillEnabled ),
		BlendType = BlendType
	}

	local Blender = CommanderSkillBlenders[ BlendType ]
	if Blender and Breakdown.FieldSkill then
		Breakdown.Counted = Blender( Breakdown.CommanderSkill, Breakdown.FieldSkill )
	else
		Breakdown.Counted = Breakdown.CommanderSkill
	end

	return Breakdown
end

--[[
	Logs what each shuffle produced: one line per team, plus one per commander where there is one.

	Neither the scoreboard nor sh_teamstats can show this. The scoreboard has no per-player values,
	and sh_teamstats serves cached numbers that nothing refreshes when a player takes or leaves the
	command chair. This is computed fresh at the moment of the shuffle, from the same ranking
	function the shuffle itself used, so it is what the algorithm actually decided on.

	Logged at INFO, so sh_setloglevel shufflemkii WARN silences it.
]]
function Plugin:LogShuffle()
	local Logger = self.Logger
	if not Logger or not Logger:IsInfoEnabled() then return end

	local VoteShuffle = Shine.Plugins.voterandom
	if not VoteShuffle then return end

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local RankFunc = VoteShuffle:ApplyConfigToRankingFunction( VoteShuffle.SkillGetters.GetHiveSkill )
	local TeamSkillEnabled = VoteShuffle:IsPerTeamSkillEnabled()

	-- Team:GetPlayers() hands back the same table every call, so finish with one team before
	-- asking for the next.
	for TeamNumber = 1, 2 do
		local Team = TeamNumber == 1 and Gamerules.team1 or Gamerules.team2
		local Players = Team and Team.GetPlayers and Team:GetPlayers()

		if Players then
			local Stats = VoteShuffle:GetAverageSkill( Players, TeamNumber, RankFunc )
			local TeamName = Shine:GetTeamName( TeamNumber, true )

			Logger:Info( "Shuffled teams - %s: average skill %.0f across %d player%s (%d counted).",
				TeamName, Stats.Average, #Players, #Players == 1 and "" or "s", Stats.Count )

			for i = 1, #Players do
				local Ply = Players[ i ]
				local Breakdown = Ply and self:GetCommanderSkillBreakdown( Ply, TeamNumber, TeamSkillEnabled )

				if Breakdown then
					local Client = GetClientForPlayer( Ply )
					-- Name only, never Shine.GetClientInfo: that appends the Steam ID, and these lines
					-- are collected for analysis and shared. NS2 names are not account names.
					local Name = ( Client and Shine.GetClientName( Client ) )
						or ( Ply.GetName and Ply:GetName() ) or "<unknown>"

					Logger:Info( "Shuffled teams - %s commander %s counted as %.0f (commander skill %.0f, field skill %s, blend %s).",
						TeamName, Name, Breakdown.Counted, Breakdown.CommanderSkill,
						Breakdown.FieldSkill and StringFormat( "%.0f", Breakdown.FieldSkill ) or "unavailable",
						Breakdown.BlendType )

					break
				end
			end
		end
	end
end

--[[
	Reports which algorithm is actually in use, so server operators and players can tell that
	shuffle results will not match a stock Shine server, and who to report problems to.

	Every blending mode is a function of the commander skill, so this plugin forces the shuffle
	plugin to consult it. That is a change to another plugin's configured behaviour and is stated
	here, not left for someone to discover.
]]
function Plugin:GetCommanderSkillLine()
	local VoteShuffle = Shine.Plugins.voterandom
	local WasEnabled = true
	if VoteShuffle and self.OriginalIsCommanderSkillEnabled then
		WasEnabled = not not self.OriginalIsCommanderSkillEnabled( VoteShuffle )
	end

	if WasEnabled then
		return "Commander skill is forced on by this plug-in. The shuffle plug-in already had UseCommanderSkill enabled."
	end

	return "Commander skill is forced on by this plug-in, overriding the shuffle plug-in's UseCommanderSkill setting of false."
end

function Plugin:PrintAlgorithm( Client )
	local Lines = {
		StringFormat(
			"%s v%s is active and has replaced Shine's commander skill calculation.",
			self.PrintName,
			self.Version
		),
		self:GetCommanderSkillLine(),
		StringFormat(
			"Commander skill blending - Marines: %s. Aliens: %s.",
			self.Config.MarineCommanderSkillBlend,
			self.Config.AlienCommanderSkillBlend
		),
		StringFormat(
			"Shuffle results may differ from other servers. Report shuffle issues to the %s author, not to Shine.",
			self.PrintName
		)
	}

	if not Client then
		Notify( TableConcat( Lines, "\n" ) )
	else
		for i = 1, #Lines do
			ServerAdminPrint( Client, Lines[ i ] )
		end
	end
end

function Plugin:OnFirstThink()
	local VoteShuffle = Shine.Plugins.voterandom
	if not VoteShuffle then return end

	-- SkillGetters is shared by reference with the shuffle plugin's balance module, and is looked up
	-- at call time, so replacing the field here covers every path that ranks players.
	self.OriginalGetHiveSkill = VoteShuffle.SkillGetters.GetHiveSkill
	VoteShuffle.SkillGetters.GetHiveSkill = function( Ply, TeamNumber, TeamSkillEnabled, CommanderSkillEnabled )
		return self:GetHiveSkill( Ply, TeamNumber, TeamSkillEnabled, CommanderSkillEnabled )
	end

	-- Every blending mode is a function of the commander skill, so with the shuffle plugin's
	-- UseCommanderSkill off this plugin would sit there doing nothing. Force it on instead.
	--
	-- Override the method rather than the config value: Shine writes a plugin's config back to
	-- disk whenever validation changes something, so writing to voterandom's config could persist
	-- this change and outlive the plugin. IsCommanderSkillEnabled is the only reader of the
	-- setting, so overriding it covers every consumer of it.
	if VoteShuffle.IsCommanderSkillEnabled then
		self.OriginalIsCommanderSkillEnabled = VoteShuffle.IsCommanderSkillEnabled
		VoteShuffle.IsCommanderSkillEnabled = function() return true end
	end

	-- Log the result of each Hive shuffle. Nothing else shows the values it used: the scoreboard
	-- has no per-player figures and sh_teamstats serves cached ones.
	self.OriginalShuffleTeams = VoteShuffle.ShuffleTeams
	VoteShuffle.ShuffleTeams = function( ShufflePlugin, ... )
		local Result = self.OriginalShuffleTeams( ShufflePlugin, ... )

		-- LastShuffleMode is set by the call above, and accounts for a forced mode.
		if ShufflePlugin.LastShuffleMode == ShufflePlugin.ShuffleMode.HIVE then
			self:LogShuffle()
		end

		return Result
	end

	local Command = Shine.Commands[ "sh_teamstats" ]
	if not Command then return end

	self.TeamStatsCommand = Command
	self.OriginalTeamStatsFunc = Command.Func

	local OriginalFunc = Command.Func
	Command.Func = function( CommandClient, ... )
		OriginalFunc( CommandClient, ... )

		-- sh_teamstats bails out early when Hive balancing is not in use, and commander skill is
		-- only consulted in that mode, so there is nothing meaningful to report otherwise.
		if VoteShuffle.Config.BalanceMode ~= VoteShuffle.ShuffleMode.HIVE then return end

		self:PrintAlgorithm( CommandClient )
	end
end

function Plugin:Cleanup()
	local VoteShuffle = Shine.Plugins.voterandom
	if VoteShuffle and self.OriginalGetHiveSkill then
		VoteShuffle.SkillGetters.GetHiveSkill = self.OriginalGetHiveSkill
	end
	if VoteShuffle and self.OriginalIsCommanderSkillEnabled then
		VoteShuffle.IsCommanderSkillEnabled = self.OriginalIsCommanderSkillEnabled
	end
	if VoteShuffle and self.OriginalShuffleTeams then
		VoteShuffle.ShuffleTeams = self.OriginalShuffleTeams
	end
	self.OriginalShuffleTeams = nil
	self.OriginalIsCommanderSkillEnabled = nil
	self.OriginalGetHiveSkill = nil

	if self.TeamStatsCommand and self.OriginalTeamStatsFunc then
		self.TeamStatsCommand.Func = self.OriginalTeamStatsFunc
	end
	self.TeamStatsCommand = nil
	self.OriginalTeamStatsFunc = nil

	self.BaseClass.Cleanup( self )
end

-- Provides self.Logger, a LogLevel config setting and sh_setloglevel shufflemkii.
Shine.LoadPluginModule( "logger.lua", Plugin )
