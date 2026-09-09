--[[
	Tests for Shuffle Mk II's commander skill blending.

	Shine's own test suite runs inside an NS2 server, which makes it awkward to check this plugin's
	arithmetic while iterating. This harness stubs the handful of Shine globals the plugin touches at
	load time, then loads the REAL plugin file and calls Plugin:GetHiveSkill directly, so it tests
	the shipped code rather than a copy of it.

	Run from anywhere with a standalone Lua interpreter:

		lua test/blend.lua

	Note this is not NS2's runtime (which is LuaJIT/5.1), and it does not exercise real player
	objects or Shine's plugin loader. It verifies the arithmetic and control flow only; a live round
	is still the real test.
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

Shared = { Message = print }

local MockClient = { GetIsVirtual = function() return false end }

Shine = {
	Plugin = function() return { BaseClass = { Cleanup = function() end } } end,
	GetClientForPlayer = function() return MockClient end,
	Validator = function()
		local V = {}
		V.InEnum = function() return function() end end
		V.AddFieldRules = function() end
		return V
	end
}

-- Load the real plugin, relative to this file so the cwd does not matter.
local ScriptDir = debug.getinfo( 1, "S" ).source:match( "^@(.*[/\\])" ) or "./"
local Chunk = assert( loadfile( ScriptDir.."../source/lua/shine/extensions/shufflemkii.lua" ) )
local Plugin = Chunk( "shufflemkii" )

local Blend = Plugin.CommanderSkillBlendType

-- Test helpers --------------------------------------------------------------
local Passed, Failed = 0, 0
local function Check( Name, Expected, Actual )
	if Expected == Actual then
		Passed = Passed + 1
		print( string.format( "  PASS  %-58s = %s", Name, tostring( Actual ) ) )
	else
		Failed = Failed + 1
		print( string.format( "  FAIL  %-58s expected %s, got %s",
			Name, tostring( Expected ), tostring( Actual ) ) )
	end
end

local function MakePlayer( FieldSkill, FieldOffset, CommSkill, CommOffset, TeamNumber, IsComm )
	return {
		GetPlayerSkill = function() return FieldSkill end,
		GetPlayerSkillOffset = function() return FieldOffset end,
		GetCommanderSkill = function() return CommSkill end,
		GetCommanderSkillOffset = function() return CommOffset end,
		GetTeamNumber = function() return TeamNumber end,
		isa = function( self, Name ) return IsComm and Name == "Commander" end
	}
end

local function Skill( Ply, TeamNumber, MarineBlend, AlienBlend, CommEnabled )
	Plugin.Config = {
		MarineCommanderSkillBlend = MarineBlend,
		AlienCommanderSkillBlend = AlienBlend
	}
	if CommEnabled == nil then CommEnabled = true end
	return Plugin:GetHiveSkill( Ply, TeamNumber, true, CommEnabled )
end

-- Alien commander: field 1000-500=500, commander 500-100=400 (field > comm).
-- The AVERAGE case matches Shine's own unit test expectation of 450, confirming the legacy
-- behaviour is preserved.
local AlienComm = MakePlayer( 1000, 500, 500, 100, 2, true )

print( "\nAlien commander (resolved field 500, resolved commander 400 -- field is higher):" )
Check( "COMMANDER_ONLY uses commander skill",
	400, Skill( AlienComm, 2, Blend.COMMANDER_ONLY, Blend.COMMANDER_ONLY ) )
Check( "AVERAGE blends 50/50",
	450, Skill( AlienComm, 2, Blend.COMMANDER_ONLY, Blend.AVERAGE ) )
Check( "AVERAGE_IF_FIELD_SKILL_HIGHER blends when field is higher",
	450, Skill( AlienComm, 2, Blend.COMMANDER_ONLY, Blend.AVERAGE_IF_FIELD_SKILL_HIGHER ) )

-- The case the new mode exists for: a strong commander who rarely leaves the chair.
-- field 500+0=500, commander 2000+0=2000 (comm > field)
local StrongMarineComm = MakePlayer( 500, 0, 2000, 0, 1, true )

print( "\nMarine commander (resolved field 500, resolved commander 2000 -- commander is higher):" )
Check( "COMMANDER_ONLY uses commander skill",
	2000, Skill( StrongMarineComm, 1, Blend.COMMANDER_ONLY, Blend.COMMANDER_ONLY ) )
Check( "AVERAGE drags the rating down",
	1250, Skill( StrongMarineComm, 1, Blend.AVERAGE, Blend.COMMANDER_ONLY ) )
Check( "AVERAGE_IF_FIELD_SKILL_HIGHER does NOT drag it down",
	2000, Skill( StrongMarineComm, 1, Blend.AVERAGE_IF_FIELD_SKILL_HIGHER, Blend.COMMANDER_ONLY ) )

-- Marine blending must be reachable at all -- stock Shine has no way to enable it.
local MarineComm = MakePlayer( 1000, 500, 500, 100, 1, true )
print( "\nMarine commander (resolved field 1500, resolved commander 600) -- marine blending works:" )
Check( "AVERAGE applies to marines",
	1050, Skill( MarineComm, 1, Blend.AVERAGE, Blend.COMMANDER_ONLY ) )

-- Per-team isolation: the other team's setting must be ignored.
print( "\nPer-team isolation:" )
Check( "alien commander ignores the marine setting",
	400, Skill( AlienComm, 2, Blend.AVERAGE, Blend.COMMANDER_ONLY ) )
Check( "marine commander ignores the alien setting",
	600, Skill( MarineComm, 1, Blend.COMMANDER_ONLY, Blend.AVERAGE ) )

-- Non-commander and disabled paths fall through to field skill.
local FieldPlayer = MakePlayer( 1000, 500, 500, 100, 2, false )
print( "\nFall-through cases:" )
Check( "field player uses field skill",
	500, Skill( FieldPlayer, 2, Blend.AVERAGE, Blend.AVERAGE ) )
Check( "commander skill disabled uses field skill",
	500, Skill( AlienComm, 2, Blend.AVERAGE, Blend.AVERAGE, false ) )
Check( "commander evaluated against the opposite team uses field skill",
	1500, Skill( AlienComm, 1, Blend.AVERAGE, Blend.AVERAGE ) )

print( string.format( "\n%d passed, %d failed\n", Passed, Failed ) )
os.exit( Failed == 0 and 0 or 1 )
