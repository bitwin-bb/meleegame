--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type SearchBoxProps = {
	text: string,
	image: string,
	panelTransparency: number,
	zIndex: number,
	size: UDim2?,
	position: UDim2?,
	textSize: number?,
	onTextChanged: (string) -> (),
	onFocusLost: () -> (),
}

local e: typeof(React.createElement) = React.createElement

return function(props: SearchBoxProps): React.ReactNode
	return e("ImageLabel", {
		Size = props.size or UDim2.new(1, -20, 0, 28),
		Position = props.position or UDim2.fromOffset(10, 38),
		BackgroundColor3 = Color3.fromRGB(16, 23, 32),
		BackgroundTransparency = if props.image ~= "" then 1 else props.panelTransparency * 0.2,
		BorderSizePixel = 0,
		Image = props.image,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = props.panelTransparency * 0.2,
		ZIndex = props.zIndex,
	}, {
		e("TextBox", {
			Size = UDim2.new(1, -14, 1, -6),
			Position = UDim2.fromOffset(7, 3),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = props.text,
			PlaceholderText = "Search recipes...",
			Font = Enum.Font.Gotham,
			TextSize = props.textSize or 13,
			TextColor3 = Color3.fromRGB(235, 242, 250),
			PlaceholderColor3 = Color3.fromRGB(134, 152, 171),
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex + 1,
			[React.Change.Text] = function(rbx: TextBox)
				props.onTextChanged(rbx.Text)
			end,
			[React.Event.FocusLost] = props.onFocusLost,
		}),
	})
end
