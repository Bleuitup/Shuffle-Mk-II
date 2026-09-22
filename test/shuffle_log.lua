--[[
	Tests for Shuffle Mk II's shuffle log.

	Loads the REAL plugin files against stubs for the handful of Shine and NS2 globals they touch,
	then drives Plugin:LogShuffle and the ShuffleTeams wrapper directly.

	Run from anywhere with a standalone Lua interpreter:

		lua test/shuffle_log.lua

	Note this is not NS2's runtime (LuaJIT/5.1) and there are no real player entities. It verifies
	which lines get logged, with which numbers, and that the wrapper restores cleanly.
]]

-- Minimal Shine stubs -------------------------------------------------------
local function DefaultTransformer( Index, Value ) return Value end

function table.AsEnum( Table, KeyTransformer )
	KeyTransformer = KeyTransformer or DefaultTransformer
	local Ret = {}
	for i = 1, #Table do
		Ret[ i ] = Table[ i ]
		Ret[ Table[ i ] ] = KeyTransformer( i, Table[ i ] )
	end
	return Ret
end

Shared = { Message = function() end }

local MockClient = { GetIsVirtual = function() return false end }

Shine = {
	Plugin = function() return { BaseClass = { Cleanup = function() end } } end,
	GetClientForPlayer = function() return MockClient end,
	GetClientInfo = function() return "Bleuitup<123>" end,
	GetTeamName = function( self, TeamNumber ) return TeamNumber == 1 and "Marines" or "Aliens" end,
	LoadPluginModule = function() end,
	Plugins = {},
	Commands = {},
	Validator = function()
		local V = {}
		V.InEnum = function() return function() end end
		V.AddFieldRules = function() end
		return V
	end
}

local ScriptDir = debug.getinfo( 1, "S" ).source:match( "^@(.*[/\\])" ) or "./"
local PluginDir = ScriptDir.."../source/lua/shine/extensions/shufflemkii/"

local Plugin = assert( loadfile( PluginDir.."shared.lua" ) )( "shufflemkii" )
assert( loadfile( PluginDir.."server.lua" ) )( Plugin, "shufflemkii" )

local Blend = Plugin.CommanderSkillBlendType

-- Test helpers --------------------------------------------------------------
local Passed, Failed = 0, 0
local function Check( Name, Expected, Actual )
	if Expected == Actual then
		Passed = Passed + 1
		print( string.format( "  PASS  %-56s = %s", Name, tostring( Actual ) ) )
	else
		Failed = Failed + 1
		print( string.format( "  FAIL  %-56s expected %s, got %s",
			Name, tostring( Expected ), tostring( Actual ) ) )
	end
end

local Logged = {}
local function MakeLogger( InfoEnabled )
	return {
		IsInfoEnabled = function() return InfoEnabled end,
		Info = function( self, Message, ... )
			Logged[ #Logged + 1 ] = select( "#", ... ) > 0 and string.format( Message, ... ) or Message
		end
	}
end

-- A player with a field skill, and a commander skill when IsCommander.
local function MakePlayer( Skill, Offset, CommanderSkill, CommanderOffset, TeamNumber, IsCommander )
	return {
		GetPlayerSkill = function() return Skill end,
		GetPlayerSkillOffset = function() return Offset end,
		GetCommanderSkill = function() return CommanderSkill end,
		GetCommanderSkillOffset = function() return CommanderOffset end,
		GetTeamNumber = function() return TeamNumber end,
		GetName = function() return "Someone" end,
		isa = function( self, Class ) return Class == "Commander" and IsCommander or false end
	}
end

local Teams = { {}, {} }

-- Stands in for Shine's voterandom, with only what the log and the wrapper touch.
local function MakeVoteShuffle( TeamSkillEnabled )
	return {
		-- Wired to the plugin the way OnFirstThink does it, so the averages are the real ones.
		SkillGetters = {
			GetHiveSkill = function( Ply, TeamNumber, TeamSkill, CommanderSkill )
				return Plugin:GetHiveSkill( Ply, TeamNumber, TeamSkill, CommanderSkill )
			end
		},
		Config = { BalanceMode = "HIVE" },
		ShuffleMode = { HIVE = "HIVE", RANDOM = "RANDOM" },
		LastShuffleMode = "HIVE",
		IsCommanderSkillEnabled = function() return true end,
		IsPerTeamSkillEnabled = function() return TeamSkillEnabled end,
		ApplyConfigToRankingFunction = function( self, RankFunc )
			return function( Ply, TeamNumber ) return RankFunc( Ply, TeamNumber, TeamSkillEnabled, true ) end
		end,
		GetAverageSkill = function( self, Players, TeamNumber, RankFunc )
			local Sum, Count = 0, 0
			for i = 1, #Players do
				local Skill = RankFunc( Players[ i ], TeamNumber )
				if Skill then
					Sum = Sum + Skill
					Count = Count + 1
				end
			end
			return { Average = Count > 0 and Sum / Count or 0, Count = Count }
		end,
		ShuffleTeams = function( self ) self.RanOriginal = true end
	}
end

GetGamerules = function()
	return {
		team1 = { GetPlayers = function() return Teams[ 1 ] end },
		team2 = { GetPlayers = function() return Teams[ 2 ] end }
	}
end

-- The commander the author described: 1600 commander skill against 3700 field skill.
local function SetUp( MarineBlend, TeamSkillEnabled )
	Teams[ 1 ] = {
		MakePlayer( 3700, 0, 1600, 0, 1, true ),
		MakePlayer( 2000, 0, -1, 0, 1, false )
	}
	Teams[ 2 ] = {
		MakePlayer( 2500, 0, -1, 0, 2, false ),
		MakePlayer( 1500, 0, -1, 0, 2, false )
	}

	Plugin.Config = {
		MarineCommanderSkillBlend = MarineBlend,
		AlienCommanderSkillBlend = Blend.COMMANDER_ONLY
	}
	Plugin.Logger = MakeLogger( true )
	Plugin.OriginalIsCommanderSkillEnabled = nil
	Plugin.OriginalShuffleTeams = nil

	local VoteShuffle = MakeVoteShuffle( TeamSkillEnabled )
	Shine.Plugins.voterandom = VoteShuffle
	Logged = {}
	return VoteShuffle
end

local function Says( Index, Phrase )
	return Logged[ Index ] ~= nil and Logged[ Index ]:find( Phrase, 1, true ) ~= nil
end

-- Line counts ---------------------------------------------------------------
print( "" )
print( "One line per team, one per commander:" )
SetUp( Blend.AVERAGE_IF_FIELD_SKILL_HIGHER, false )
Plugin:LogShuffle()
Check( "three lines: two teams plus the one commander", 3, #Logged )
Check( "marine team line first", true, Says( 1, "Marines: average skill" ) )
Check( "marine commander line follows its team", true, Says( 2, "Marines commander" ) )
Check( "alien team line last, with no commander", true, Says( 3, "Aliens: average skill" ) )

-- The numbers ---------------------------------------------------------------
print( "" )
print( "The values, for a 1600 commander / 3700 field commander:" )
Check( "commander counted as the blended 2650", true, Says( 2, "counted as 2650" ) )
Check( "commander skill shown as 1600", true, Says( 2, "commander skill 1600" ) )
Check( "field skill shown as 3700", true, Says( 2, "field skill 3700" ) )
Check( "blend mode named", true, Says( 2, "blend AVERAGE_IF_FIELD_SKILL_HIGHER" ) )
-- Marine average is (2650 + 2000) / 2 = 2325: the blended value, not the raw field skill.
Check( "team average uses the blended value", true, Says( 1, "average skill 2325 across 2 players" ) )

SetUp( Blend.COMMANDER_ONLY, false )
Plugin:LogShuffle()
Check( "COMMANDER_ONLY counts the commander skill alone", true, Says( 2, "counted as 1600" ) )
Check( "and the team average follows it", true, Says( 1, "average skill 1800" ) )

-- Per-team skill offsets ----------------------------------------------------
print( "" )
print( "With per-team skill enabled:" )
SetUp( Blend.AVERAGE, true )
Teams[ 1 ][ 1 ] = MakePlayer( 3700, 200, 1600, 100, 1, true )
Plugin:LogShuffle()
-- Marine offsets add: commander 1600 + 100 = 1700, field 3700 + 200 = 3900, mean 2800.
Check( "commander skill offset applied", true, Says( 2, "commander skill 1700" ) )
Check( "field skill offset applied", true, Says( 2, "field skill 3900" ) )
Check( "blended from the offset values", true, Says( 2, "counted as 2800" ) )

-- Two commanders ------------------------------------------------------------
print( "" )
print( "Both teams commanded:" )
SetUp( Blend.AVERAGE, false )
Teams[ 2 ][ 1 ] = MakePlayer( 1000, 0, 2000, 0, 2, true )
Plugin:LogShuffle()
Check( "four lines", 4, #Logged )
Check( "alien commander reported too", true, Says( 4, "Aliens commander" ) )
-- The alien team is COMMANDER_ONLY, so no blending despite the higher commander skill.
Check( "alien commander uses its own team's setting", true, Says( 4, "counted as 2000" ) )

-- The wrapper ---------------------------------------------------------------
print( "" )
print( "Hooking the shuffle:" )
local VoteShuffle = SetUp( Blend.AVERAGE, false )
Plugin:OnFirstThink()
VoteShuffle:ShuffleTeams()
Check( "the real shuffle still runs", true, VoteShuffle.RanOriginal )
Check( "and the result is logged", 3, #Logged )

VoteShuffle = SetUp( Blend.AVERAGE, false )
VoteShuffle.LastShuffleMode = "RANDOM"
Plugin:OnFirstThink()
VoteShuffle:ShuffleTeams()
Check( "a non-Hive shuffle logs nothing, as commander skill is unused", 0, #Logged )

VoteShuffle = SetUp( Blend.AVERAGE, false )
local Original = VoteShuffle.ShuffleTeams
Plugin:OnFirstThink()
Plugin:Cleanup()
Check( "Cleanup restores the shuffle function", Original, VoteShuffle.ShuffleTeams )

-- Log level -----------------------------------------------------------------
print( "" )
print( "Log level:" )
SetUp( Blend.AVERAGE, false )
Plugin.Logger = MakeLogger( false )
Plugin:LogShuffle()
Check( "silent when INFO is disabled", 0, #Logged )

SetUp( Blend.AVERAGE, false )
Plugin.Logger = nil
Plugin:LogShuffle()
Check( "no logger at all does not error", 0, #Logged )

print( string.format( "\n%d passed, %d failed\n", Passed, Failed ) )
os.exit( Failed == 0 and 0 or 1 )
