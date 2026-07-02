
local require = require(script.Parent.loader).load(script)

local Default = require("Default")

local Zombie = {}

export type Zombie = Default.DefaultNpc
export type ZombieConfig = Default.DefaultNpcConfig & {
	aggroOnPlayer: boolean?,
}

function Zombie.New(configRaw: ZombieConfig?): Zombie
	local config = if typeof(configRaw) == "table" then table.clone(configRaw :: any) else {} :: any
	if config.archetype == nil then
		config.archetype = "Zombie"
	end
	return Default.New(config)
end
return Zombie
