local camera = game.Workspace.CurrentCamera

local SideView = {}
SideView.__index = SideView

export type SideView = typeof(setmetatable(
	{} :: {
		inView: boolean,
	},
	SideView
))

function SideView.new(): ()
	local self = setmetatable({}, SideView)

	return self
end

function SideView.init(self: SideView) 

end

return SideView
