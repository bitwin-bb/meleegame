local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityPillProps = {
	rarity: Rarity?,
	text: string?,
	color: Color3?,
	textColor: Color3?,
	backgroundTransparency: number?,
	textTransparency: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	automaticSize: Enum.AutomaticSize?,
	layoutOrder: number?,
	zIndex: number?,
	paddingX: number?,
	paddingY: number?,
	textSize: number?,
	font: Enum.Font?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(171, 177, 186),
	Uncommon = Color3.fromRGB(104, 223, 117),
	Rare = Color3.fromRGB(74, 163, 255),
	Epic = Color3.fromRGB(191, 105, 255),
	Legendary = Color3.fromRGB(255, 193, 79),
	Mythic = Color3.fromRGB(255, 94, 143),
}

local RarityPill = {}

function RarityPill.ResolveColor(rarityRaw: any, fallback: Color3?): Color3
	if typeof(rarityRaw) == "string" then
		local color = (RARITY_COLORS :: { [string]: Color3? })[rarityRaw]
		if color ~= nil then
			return color
		end
	end
	return fallback or RARITY_COLORS.Common
end

function RarityPill.GetColors(): { [Rarity]: Color3 }
	return table.clone(RARITY_COLORS) :: any
end

function RarityPill.Component(props: RarityPillProps): React.ReactNode
	local rarityText = props.text or props.rarity or "Common"
	local backgroundColor = props.color or RarityPill.ResolveColor(props.rarity, nil)
	local labelProps: { [any]: any } = {
		AutomaticSize = props.automaticSize or Enum.AutomaticSize.XY,
		Size = props.size or UDim2.fromOffset(0, 0),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = backgroundColor,
		BackgroundTransparency = props.backgroundTransparency or 0.2,
		BorderSizePixel = 0,
		Font = props.font or Enum.Font.GothamMedium,
		Text = rarityText,
		TextColor3 = props.textColor or Color3.fromRGB(255, 255, 255),
		TextSize = props.textSize or 12,
		TextTransparency = props.textTransparency or 0.02,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = props.zIndex,
	}

	if props.native ~= nil then
		for key, value in props.native do
			labelProps[key] = value
		end
	end

	return e("TextLabel", labelProps, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, props.paddingY or 2),
			PaddingBottom = UDim.new(0, props.paddingY or 2),
			PaddingLeft = UDim.new(0, props.paddingX or 7),
			PaddingRight = UDim.new(0, props.paddingX or 7),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
	})
end

RarityPill.resolveColor = RarityPill.ResolveColor
RarityPill.getColors = RarityPill.GetColors

return RarityPill
