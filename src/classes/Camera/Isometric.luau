local camera = game.Workspace.CurrentCamera

local Isometric = {}
Isometric.__index = Isometric

export type Isometric = typeof(setmetatable({} :: {}, Isometric))

function Isometric.new()
	local self = setmetatable({}, Isometric)

	return self
end

function Isometric.init(self: Isometric) end

return Isometric
