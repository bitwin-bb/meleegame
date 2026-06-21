local require = require(script.Parent.loader).load(script)

local Npc = require("Npc")

local Default = {}

export type DefaultNpc = Npc.Npc
export type DefaultNpcConfig = Npc.NpcConfig

function Default.New(configRaw: DefaultNpcConfig?): DefaultNpc
	return (Npc.new :: any)(configRaw)
end

Default.new = Default.New

return Default
