local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type RecipeGridProps = {
	children: { React.ReactNode },
	image: string,
	panelTransparency: number,
	slotSize: number,
	slotPadding: number,
	zIndex: number,
	size: UDim2?,
	position: UDim2?,
	maxCells: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: RecipeGridProps): React.ReactNode
	return e("ImageLabel", {
		Size = props.size or UDim2.new(1, -20, 0, 240),
		Position = props.position or UDim2.fromOffset(10, 104),
		BackgroundColor3 = Color3.fromRGB(19, 27, 36),
		BackgroundTransparency = if props.image ~= "" then 1 else props.panelTransparency * 0.2,
		BorderSizePixel = 0,
		Image = props.image,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = props.panelTransparency * 0.2,
		ZIndex = props.zIndex,
	}, {
		e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		e("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 10,
			ScrollBarImageColor3 = Color3.fromRGB(152, 158, 168),
			ScrollBarImageTransparency = 0.05,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ZIndex = props.zIndex + 1,
		}, {
			e("UIGridLayout", {
				CellSize = UDim2.fromOffset(props.slotSize, props.slotSize),
				CellPadding = UDim2.fromOffset(props.slotPadding, props.slotPadding),
				SortOrder = Enum.SortOrder.LayoutOrder,
				FillDirectionMaxCells = props.maxCells or 4,
			}),
			e("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
			}),
			e(React.Fragment, nil, props.children),
		}),
	})
end
