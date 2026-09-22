--[[
	Shuffle Mk II: restore consistency checking when the server can't be ranked.

	The problem this solves
	-----------------------
	A server running any mod that isn't on UWE's whitelist (such as this one) cannot enable ranking.
	In core/lua/ConsistencyConfig.lua the game asks for ranking and then returns whether or not the
	request succeeded:

		if shouldBeRanked then
			local ok = Server.EnableServerRanking()
			Print( "Requesting server ranking be enabled, request success: %s", ok )
			return
		end

	When that request fails, the code below it that builds the consistency hash table never runs, so
	the server checks nothing at all. Players' own client-side mods are then no longer disabled on
	connect, and any of them that registers a network message leaves the client with more network
	messages than the server, which disconnects that player with "Invalid data".

	What this does
	--------------
	Runs straight after that file. If ranking is active, it does nothing. If the ranking request
	failed, it builds the consistency table the game would have built on an unranked server, using the
	game's own default lists. The result matches setting "hiveranking" to false in ServerConfig.json,
	except that it only applies when ranking was unavailable anyway, so it never costs ranking on a
	server that could have had it.

	It leaves the operator's own choices alone: if consistency checking is switched off, or a custom
	consistency config is in use, or hive ranking is already disabled, the game has handled it and
	this does nothing.
]]

if not Server then return end

local function GetSetting( Name )
	if not Server.GetConfigSetting then return nil end
	return Server.GetConfigSetting( Name )
end

do
	-- Ranking worked, so the game has consistency covered.
	if not Server.GetIsRankingActive or Server.GetIsRankingActive() then return end

	-- The operator turned consistency checking off. Respect that.
	if not GetSetting( "consistency_enabled" ) then return end

	-- In these cases the game already built its own table, so there is nothing missing.
	if GetSetting( "use_own_consistency_config" ) or GetSetting( "hiveranking" ) == false then return end

	-- Copied verbatim from the game's core/lua/ConsistencyConfig.lua defaults. Keep in step with it.
	local Check = { "game_setup.xml", "*.lua", "*.hlsl", "*.shader", "*.screenfx", "*.surface_shader", "*.fxh",
		"*.render_setup", "*.shader_template", "*.level", "*.dds", "*.cinematic", "*.material", "*.model",
		"*.animation_graph", "*.polygons", "*.fev", "*.fsb", "*.hmp", "ui/*.dds" }
	local Restrict = { "lua/entry/*.entry" }
	local Ignore = { "*_view*.dds", "*_view*.material", "*_view*.model", "models/marine/hands/*",
		"*/hitsounds_client.fev", "*/hitsounds_client.fsb", "shaders/DarkVision.hlsl",
		"shaders/DarkVision.screenfx", "shaders/DarkVision.shader", "models/marine/male/flashlight.dds",
		"ui/crosshairs.dds", "ui/crosshairs-hit.dds", "ui/alien_hud_health.dds", "ui/alien_hud_health_noise.dds",
		"ui/alien_hud_health.dds", "ui/alien_hud_health_old.dds", "ui/alien_hud_health_smoke.dds",
		"ui/bottomhudbar1bg.dds", "ui/bottomhudbar1main.dds", "ui/bottomhudbar1sec.dds", "ui/bottomhudbar2ap.dds",
		"ui/bottomhudbar2bg-l.dds", "ui/bottomhudbar2bg-r.dds", "ui/bottomhudbar2hp.dds",
		"ui/bottomhudbar2right.dds", "ui/centerhudbar.dds", "ui/exo_crosshair.dds", "ui/exosuit_HUD1.dds",
		"ui/exosuit_HUD2.dds", "ui/exosuit_HUD3.dds", "ui/exosuit_HUD4.dds", "ui/blip.dds",
		"ui/alien_outline_lookup.dds", "ui/marine_outline_lookup.dds", "ui/drop_icons.dds",
		"ui/hud_damage_arrow.dds" }

	Shared.Message( "[Shuffle Mk II] Server ranking is not active, so the game skipped its consistency "..
		"check setup. Building the standard consistency table so players' client-side mods are still "..
		"checked. Set \"hiveranking\" to false in ServerConfig.json to have the game do this itself." )

	for i = 1, #Check do
		Server.AddFileHashes( Check[ i ] )
	end

	for i = 1, #Restrict do
		Server.AddRestrictedFileHashes( Restrict[ i ] )
	end

	for i = 1, #Ignore do
		Server.RemoveFileHashes( Ignore[ i ] )
	end

	Shared.Message( "[Shuffle Mk II] Consistency table built." )
end
