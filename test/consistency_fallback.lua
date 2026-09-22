--[[
	Tests for Shuffle Mk II's consistency fallback.

	Loads the real source/lua/ShuffleMkII/ConsistencyFallback.lua against a stubbed Server, and checks
	that it only builds the consistency table when the game skipped it, and leaves the operator's own
	settings alone.

	Run from anywhere with a standalone Lua interpreter:

		lua test/consistency_fallback.lua
]]

local ScriptDir = debug.getinfo( 1, "S" ).source:match( "^@(.*[/\\])" ) or "./"
local Path = ScriptDir.."../source/lua/ShuffleMkII/ConsistencyFallback.lua"

local Passed, Failed = 0, 0
local function Check( Name, Condition )
	if Condition then
		Passed = Passed + 1
		print( "  PASS  "..Name )
	else
		Failed = Failed + 1
		print( "  FAIL  "..Name )
	end
end

-- Runs the file with a stubbed Server, returning what it did.
local function Run( Options )
	Options = Options or {}
	local Calls = { Added = {}, Restricted = {}, Removed = {}, Messages = {}, Order = {} }

	local Settings = Options.Settings or {}
	if Settings.consistency_enabled == nil then Settings.consistency_enabled = true end

	local ServerStub
	if not Options.NoServer then
		ServerStub = {
			-- NOTE: don't write this as "Options.NoGetConfigSetting and nil or f"; in Lua that yields f.
			GetConfigSetting = nil,
			AddFileHashes = function( Pattern )
				Calls.Added[ #Calls.Added + 1 ] = Pattern
				Calls.Order[ #Calls.Order + 1 ] = "check"
			end,
			AddRestrictedFileHashes = function( Pattern )
				Calls.Restricted[ #Calls.Restricted + 1 ] = Pattern
				Calls.Order[ #Calls.Order + 1 ] = "restrict"
			end,
			RemoveFileHashes = function( Pattern )
				Calls.Removed[ #Calls.Removed + 1 ] = Pattern
				Calls.Order[ #Calls.Order + 1 ] = "ignore"
			end
		}
		if not Options.NoGetConfigSetting then
			ServerStub.GetConfigSetting = function( Name ) return Settings[ Name ] end
		end
		if not Options.NoRankingFunction then
			ServerStub.GetIsRankingActive = function() return Options.RankingActive == true end
		end
	end

	local Env = setmetatable( {
		Server = ServerStub,
		Shared = { Message = function( Text ) Calls.Messages[ #Calls.Messages + 1 ] = Text end }
	}, { __index = _G } )

	assert( loadfile( Path, "t", Env ) )()

	Calls.DidNothing = #Calls.Added == 0 and #Calls.Restricted == 0 and #Calls.Removed == 0
	return Calls
end

local function Contains( List, Value )
	for i = 1, #List do
		if List[ i ] == Value then return true end
	end
	return false
end

print( "\nCases where the game has already handled consistency:" )
Check( "ranking active: does nothing", Run( { RankingActive = true } ).DidNothing )
Check( "hive ranking already off in the server config: does nothing",
	Run( { Settings = { hiveranking = false } } ).DidNothing )
Check( "custom consistency config in use: does nothing",
	Run( { Settings = { use_own_consistency_config = true } } ).DidNothing )

print( "\nCases where it must keep out of the way:" )
Check( "operator disabled consistency checking: does nothing",
	Run( { Settings = { consistency_enabled = false } } ).DidNothing )
Check( "no ranking function available: does nothing", Run( { NoRankingFunction = true } ).DidNothing )
Check( "no Server (client or predict VM): does nothing and doesn't error", Run( { NoServer = true } ).DidNothing )
Check( "no GetConfigSetting available: does nothing", Run( { NoGetConfigSetting = true } ).DidNothing )

print( "\nRanking request failed (a non-whitelisted mod is mounted):" )
do
	local Calls = Run()
	Check( "hashes the standard checked file types", #Calls.Added == 20
		and Contains( Calls.Added, "*.lua" ) and Contains( Calls.Added, "game_setup.xml" )
		and Contains( Calls.Added, "ui/*.dds" ) )
	Check( "restricts entry files, which is what blocks players' own mods",
		#Calls.Restricted == 1 and Calls.Restricted[ 1 ] == "lua/entry/*.entry" )
	-- 36, not 35: the game's own list contains ui/alien_hud_health.dds twice, and this copies it verbatim.
	Check( "skips the file types the game exempts", #Calls.Removed == 36
		and Contains( Calls.Removed, "ui/crosshairs.dds" ) and Contains( Calls.Removed, "shaders/DarkVision.shader" )
		and Contains( Calls.Removed, "*/hitsounds_client.fev" ) )
	Check( "ignores are applied after the checks, as the game does",
		Calls.Order[ 1 ] == "check" and Calls.Order[ #Calls.Order ] == "ignore" )
	Check( "says what it did in the server log", #Calls.Messages == 2
		and Calls.Messages[ 1 ]:find( "Shuffle Mk II", 1, true ) ~= nil
		and Calls.Messages[ 1 ]:find( "consistency", 1, true ) ~= nil )
end

print( string.format( "\n%d passed, %d failed\n", Passed, Failed ) )
os.exit( Failed == 0 and 0 or 1 )
