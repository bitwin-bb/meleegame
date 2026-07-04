local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakScreen = require("Break")
local React: any = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

return function(): React.ReactNode
	return e(React.Fragment, nil, {
		e(BreakScreen),
	})
end
