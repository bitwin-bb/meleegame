local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local TransparentFrame = require("TransparentFrame")

export type ScreenLayerProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	active: boolean?,
	children: { React.ReactNode }?,
	native: { [any]: any }?,
}

return function(props: ScreenLayerProps): React.ReactNode
	return React.createElement(TransparentFrame, {
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		zIndex = props.zIndex,
		active = props.active,
		native = props.native,
		children = props.children,
	})
end
