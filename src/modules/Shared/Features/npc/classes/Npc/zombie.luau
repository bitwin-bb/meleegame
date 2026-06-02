--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Default = require(gameRoot.Shared.Features.npc.classes.Npc.Default)

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
	return Default.new(config)
end

Zombie.new = Zombie.New

return Zombie
