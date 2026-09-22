--[[
	Shuffle Mk II file hooks.

	Runs before the game's own scripts, in every VM. The only hook is server-side: it queues
	ConsistencyFallback.lua to run straight after the game's consistency setup. See that file for why.
]]

if Server then
	ModLoader.SetupFileHook( "lua/ConsistencyConfig.lua", "lua/ShuffleMkII/ConsistencyFallback.lua", "post" )
end
