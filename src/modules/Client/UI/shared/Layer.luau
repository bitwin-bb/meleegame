--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ScreenLayer = require(script.Parent.Parent.core.primitives.ScreenLayer)

export type LayerProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	active: boolean?,
	name: string?,
	children: { React.ReactNode }?,
	native: { [any]: any }?,
}

local DEFAULT_Z_INDEX = 1

return function(props: LayerProps): React.ReactNode
	local native = if props.native ~= nil then table.clone(props.native) else {}
	if props.name ~= nil then
		native.Name = props.name
	end

	return React.createElement(ScreenLayer, {
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		zIndex = props.zIndex or DEFAULT_Z_INDEX,
		active = props.active,
		native = native,
		children = props.children,
	})
end
