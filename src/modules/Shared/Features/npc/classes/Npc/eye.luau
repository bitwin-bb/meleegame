--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Default = require(gameRoot.Shared.Features.npc.classes.Npc.Default)

local Eye = {}

export type Eye = Default.DefaultNpc
export type EyeConfig = Default.DefaultNpcConfig & {
	hoverHeight: number?,
	aggroOnPlayer: boolean?,
}

function Eye.New(configRaw: EyeConfig?): Eye
	local config = if typeof(configRaw) == "table" then table.clone(configRaw :: any) else {} :: any
	if config.archetype == nil then
		config.archetype = "DemonEye"
	end
	return Default.new(config)
end

Eye.new = Eye.New

return Eye
