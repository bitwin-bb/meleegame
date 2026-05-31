--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinScreen = require(script.Parent.screens.coinScreen)
local React = require(ReplicatedStorage.Packages.React)
local TrashScreen = require(script.Parent.screens.trashScreen)

type InventoryRootProps = {
	coinScreenProps: { [string]: any }?,
	trashScreenProps: { [string]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: InventoryRootProps?): React.ReactNode
	local resolvedProps = if props ~= nil then props else {} :: InventoryRootProps
	local children: { React.ReactNode } = {}

	if resolvedProps.trashScreenProps ~= nil then
		children[#children + 1] = e(TrashScreen, resolvedProps.trashScreenProps)
	end

	if resolvedProps.coinScreenProps ~= nil then
		children[#children + 1] = e(CoinScreen, resolvedProps.coinScreenProps)
	end

	if #children <= 0 then
		return nil
	end

	return e(React.Fragment, nil, children)
end
