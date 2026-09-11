--[[
	Shuffle Mk II shared code.

	Everything this plugin does is server-side, but it ships a shared.lua so Shine treats it as a
	shared plugin: loaded and known about on both the server and clients. A single-file extension is
	loaded by the server only, and in that form mounting this mod disconnected every client with
	"Invalid data" (different number of network messages). This is the same layout as other Shine
	plugins running on the same server without problems.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.1"
Plugin.PrintName = "Shuffle Mk II"

-- Disabled until a server operator enables it. Without a default state, Shine never records the
-- plugin in ActiveExtensions and re-loads it on every map change just to check.
Plugin.DefaultState = false

return Plugin
