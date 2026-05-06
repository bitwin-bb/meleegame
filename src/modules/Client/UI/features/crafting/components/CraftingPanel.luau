--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type CraftingPanelProps = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	scale: number,
	panelImage: string,
	panelTransparency: number,
	zIndex: number,
	onDragInputBegan: (GuiObject, InputObject) -> (),
	onDragInputEnded: (GuiObject, InputObject) -> (),
	children: { React.ReactNode },
}

local e: typeof(React.createElement) = React.createElement

return function(props: CraftingPanelProps): React.ReactNode
	local children: { React.ReactNode } = {
		e("UIScale", {
			Scale = props.scale,
		}),
	}

	if props.panelImage ~= "" then
		children[#children + 1] = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.panelImage,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ImageTransparency = props.panelTransparency,
			ZIndex = props.zIndex,
		})
	end

	children[#children + 1] = e("TextLabel", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Text = "Crafting",
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(246, 251, 255),
		TextStrokeTransparency = 0.45,
		ZIndex = props.zIndex + 1,
	})

	children[#children + 1] = e("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = props.zIndex + 5,
		[React.Event.InputBegan] = props.onDragInputBegan,
		[React.Event.InputEnded] = props.onDragInputEnded,
	})

	for _, child in props.children do
		children[#children + 1] = child
	end

	return e("CanvasGroup", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = Color3.fromRGB(24, 33, 43),
		BackgroundTransparency = if props.panelImage ~= "" then 1 else props.panelTransparency * 0.15,
		BorderSizePixel = 0,
		GroupTransparency = props.panelTransparency,
		ZIndex = props.zIndex,
	}, children)
end
