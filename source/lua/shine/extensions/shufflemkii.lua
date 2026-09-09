--[[
	Shuffle Mk II

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

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.PrintName = "Shuffle Mk II"

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
	Reports which algorithm is actually in use, so server operators and players can tell that
	shuffle results will not match a stock Shine server, and who to report problems to.
]]
function Plugin:PrintAlgorithm( Client )
	local Lines = {
		StringFormat(
			"%s v%s is active and has replaced Shine's commander skill calculation.",
			self.PrintName,
			self.Version
		),
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
	self.OriginalGetHiveSkill = nil

	if self.TeamStatsCommand and self.OriginalTeamStatsFunc then
		self.TeamStatsCommand.Func = self.OriginalTeamStatsFunc
	end
	self.TeamStatsCommand = nil
	self.OriginalTeamStatsFunc = nil

	self.BaseClass.Cleanup( self )
end

return Plugin
