--[[
	Shuffle Mk II shared code.

	Everything this plugin does is server-side, but it ships a shared.lua so Shine treats it as a
	shared plugin: loaded and known about on both the server and clients. This matches the author's
	other Shine plugins. v1.0 was a single file, which works fine too - the client disconnects that
	prompted the move turned out to have an unrelated cause, see CLAUDE.md.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.13"
Plugin.PrintName = "Shuffle Mk II"

-- Disabled until a server operator enables it. Without a default state, Shine never records the
-- plugin in ActiveExtensions and re-loads it on every map change just to check.
Plugin.DefaultState = false

return Plugin
