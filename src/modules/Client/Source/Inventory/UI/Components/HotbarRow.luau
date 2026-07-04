local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

export type HotbarRowProps = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	zIndex: number,
	gap: number,
	children: { React.ReactNode },
}

return function(props: HotbarRowProps): React.ReactNode
	local children: { React.ReactNode } = {
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.gap),
		}),
	}

	for _, child in props.children do
		children[#children + 1] = child
	end

	return e("Frame", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
	}, children)
end
