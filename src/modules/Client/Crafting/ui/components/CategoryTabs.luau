local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type CategoryTabsProps = {
	categories: { string },
	activeCategory: string,
	categoryImage: string,
	panelTransparency: number,
	zIndex: number,
	size: UDim2?,
	position: UDim2?,
	tabSize: UDim2?,
	tabPadding: UDim?,
	textSize: number?,
	onActivated: (string) -> (),
}

local e: typeof(React.createElement) = React.createElement

return function(props: CategoryTabsProps): React.ReactNode
	local categoryChildren: { React.ReactNode } = {
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = props.tabPadding or UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, category in props.categories do
		local isAll = category == "All"
		local categoryValue = if isAll then "" else category
		local isSelected = props.activeCategory == categoryValue
		local hasCategoryAsset = props.categoryImage ~= ""
		categoryChildren[#categoryChildren + 1] = e("ImageButton", {
			Size = props.tabSize or UDim2.fromOffset(74, 26),
			LayoutOrder = index,
			AutoButtonColor = false,
			BackgroundColor3 = if isSelected then Color3.fromRGB(76, 142, 185) else Color3.fromRGB(38, 47, 60),
			BackgroundTransparency = if hasCategoryAsset then 1 else props.panelTransparency * 0.35,
			BorderSizePixel = 0,
			Image = props.categoryImage,
			ImageColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(229, 240, 252),
			ImageTransparency = props.panelTransparency * 0.25,
			ZIndex = props.zIndex,
			[React.Event.Activated] = function()
				props.onActivated(categoryValue)
			end,
		}, {
			e("TextLabel", {
				Size = UDim2.new(1, -8, 1, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = category,
				Font = Enum.Font.PatrickHand,
				TextSize = props.textSize or 12,
				TextColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(212, 223, 236),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextStrokeTransparency = 0.55,
				ZIndex = props.zIndex + 1,
			}),
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.new(1, -20, 0, 26),
		Position = props.position or UDim2.fromOffset(10, 72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
	}, {
		e("UIPadding", {
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 2),
		}),
		e(React.Fragment, nil, categoryChildren),
	})
end
