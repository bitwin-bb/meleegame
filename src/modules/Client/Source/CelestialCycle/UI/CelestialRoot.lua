local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")

local CelestialBodyScreen = require("CelestialBodyScreen")

local e: typeof(React.createElement) = React.createElement

local CelestialRoot = {}

function CelestialRoot.Render(): React.ReactNode
	return e(CelestialBodyScreen)
end

local readonlyRoot = Table.readonly(CelestialRoot)

return function(): React.ReactNode
	return readonlyRoot.Render()
end
