
local require = require(script.Parent.loader).load(script)

local Default = require("Default")

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
	return Default.New(config)
end
return Eye
