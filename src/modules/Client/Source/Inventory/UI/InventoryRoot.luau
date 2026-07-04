local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinScreen = require("CoinScreen")
local React: any = require(ReplicatedStorage.Packages.React)
local TrashScreen = require("TrashScreen")

type InventoryRootProps = {
	coinScreenProps: { [string]: any }?,
	trashScreenProps: { [string]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: InventoryRootProps?): React.ReactNode
	local GotProps = if props ~= nil then props else {} :: InventoryRootProps
	local children: { React.ReactNode } = {}

	if GotProps.trashScreenProps ~= nil then
		children[#children + 1] = e(TrashScreen, GotProps.trashScreenProps)
	end

	if GotProps.coinScreenProps ~= nil then
		children[#children + 1] = e(CoinScreen, GotProps.coinScreenProps)
	end

	if #children <= 0 then
		return nil
	end

	return e(React.Fragment, nil, children)
end
