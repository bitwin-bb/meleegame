local camera = game.Workspace.CurrentCamera

local FirstPerson = {}
FirstPerson.__index = FirstPerson

export type FirstPerson = typeof(setmetatable({} :: {}, FirstPerson))

function FirstPerson.new()
	local self = setmetatable({}, FirstPerson)

	return self
end

function FirstPerson.init(self: FirstPerson) end

return FirstPerson
