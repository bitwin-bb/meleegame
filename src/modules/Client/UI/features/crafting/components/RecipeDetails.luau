--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type RecipeDetailsProps = {
	children: { React.ReactNode },
	image: string,
	panelTransparency: number,
	slotSize: number,
	slotPadding: number,
	zIndex: number,
	size: UDim2?,
	position: UDim2?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: RecipeDetailsProps): React.ReactNode
	return e("ImageLabel", {
		Size = props.size or UDim2.new(1, -20, 0, 64),
		Position = props.position or UDim2.fromOffset(10, 348),
		BackgroundColor3 = Color3.fromRGB(19, 27, 36),
		BackgroundTransparency = if props.image ~= "" then 1 else props.panelTransparency * 0.2,
		BorderSizePixel = 0,
		Image = props.image,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = props.panelTransparency * 0.2,
		ZIndex = props.zIndex,
	}, {
		e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
		e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = props.zIndex + 1,
		}, {
			e("UIGridLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				CellSize = UDim2.fromOffset(props.slotSize, props.slotSize),
				CellPadding = UDim2.fromOffset(props.slotPadding, props.slotPadding),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			e(React.Fragment, nil, props.children),
		}),
	})
end
