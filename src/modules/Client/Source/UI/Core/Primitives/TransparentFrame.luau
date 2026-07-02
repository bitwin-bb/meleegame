local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type TransparentFrameProps = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	active: boolean?,
	selectable: boolean?,
	automaticSize: Enum.AutomaticSize?,
	clipsDescendants: boolean?,
	children: { React.ReactNode }?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: TransparentFrameProps): React.ReactNode
	local frameProps: { [any]: any } = {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		ZIndex = props.zIndex,
		Active = props.active,
		Selectable = props.selectable,
		AutomaticSize = props.automaticSize,
		ClipsDescendants = props.clipsDescendants,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}

	if props.native ~= nil then
		for key, value in props.native do
			frameProps[key] = value
		end
	end

	return e("Frame", frameProps, props.children)
end
