--!strict

local Npc = require(script.Parent)

local Default = {}

export type DefaultNpc = Npc.Npc
export type DefaultNpcConfig = Npc.NpcConfig

function Default.New(configRaw: DefaultNpcConfig?): DefaultNpc
	return (Npc.new :: any)(configRaw)
end

Default.new = Default.New

return Default
