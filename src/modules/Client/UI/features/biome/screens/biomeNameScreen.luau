--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
local biomeSlice = require(script:FindFirstAncestor("game").Client.UI.features.biome.state.biomeSlice)
local biomeThunks = require(script:FindFirstAncestor("game").Client.UI.features.biome.state.biomeThunks)
local useBiomeNameAppearance =
	require(script:FindFirstAncestor("game").Client.UI.features.biome.hooks.useBiomeNameAppearance)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)
local useTextUnderline = require(script:FindFirstAncestor("game").Client.UI.features.biome.hooks.useTextUnderline)

type BiomeState = biomeSlice.BiomeState

type BiomeNameScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local UNDERLINE_IMAGE = if typeof(ImageIds.glareUnderline) == "string" then ImageIds.glareUnderline else ""
local BANNER_PROGRESS_EPSILON = 0.001
local BANNER_POSITION = UDim2.new(0.5, 0, 0.16, 0)
local TEXT_SIZE = Vector2.new(520, 60)
local UNDERLINE_BASE_SIZE = Vector2.new(236, 14)

return function(props: BiomeNameScreenProps?): React.ReactNode
	local resolvedProps: BiomeNameScreenProps = if props ~= nil then props else {}
	local biomeState = (useStore(biomeSlice.biomeStateAtom) :: BiomeState?) or biomeSlice.biomeStateAtom()

	React.useEffect(function()
		local stop = biomeThunks.start()

		return function()
			stop()
		end
	end, {})

	local canRender = resolvedProps.visible ~= false
	local appearance = useBiomeNameAppearance({
		enabled = canRender and biomeState.visible,
		fromOffset = Vector2.new(0, -26),
		toOffset = Vector2.zero,
		minScale = 0.82,
		maxScale = 1,
	})
	local underline = useTextUnderline({
		enabled = canRender and biomeState.visible,
		fromOffset = Vector2.new(0, 8),
		toOffset = Vector2.zero,
		minWidthScale = 0.04,
		maxWidthScale = 1,
	})

	local showBanner = canRender
		and (
			biomeState.visible
			or appearance.progress > BANNER_PROGRESS_EPSILON
			or underline.progress > BANNER_PROGRESS_EPSILON
		)
	if not showBanner or biomeState.biomeName == "" then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 150
	local bannerXOffset = math.floor(appearance.offset.X + 0.5)
	local bannerYOffset = math.floor(appearance.offset.Y + 0.5)
	local underlineXOffset = math.floor(underline.offset.X + 0.5)
	local underlineYOffset = math.floor(underline.offset.Y + 0.5)
	local underlineWidth = math.max(1, math.floor(UNDERLINE_BASE_SIZE.X * underline.widthScale + 0.5))
	local underlineHeight = math.max(1, math.floor(UNDERLINE_BASE_SIZE.Y + 0.5))

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = resolvedProps.layoutOrder or 997,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Active = false,
	}, {
		Banner = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				BANNER_POSITION.X.Scale,
				BANNER_POSITION.X.Offset + bannerXOffset,
				BANNER_POSITION.Y.Scale,
				BANNER_POSITION.Y.Offset + bannerYOffset
			),
			Size = UDim2.fromOffset(TEXT_SIZE.X, TEXT_SIZE.Y + 24),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Scale = e("UIScale", {
				Scale = appearance.scale,
			}),
			NameText = e("TextLabel", {
				Size = UDim2.fromOffset(TEXT_SIZE.X, TEXT_SIZE.Y),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = biomeState.biomeName,
				Font = Enum.Font.GothamBlack,
				TextSize = 46,
				TextColor3 = Color3.fromRGB(247, 246, 234),
				TextStrokeColor3 = Color3.fromRGB(18, 15, 10),
				TextStrokeTransparency = appearance.strokeTransparency,
				TextTransparency = appearance.transparency,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex + 3,
			}, {
				Gradient = e("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 214, 151)),
					}),
					Rotation = 90,
				}),
			}),
			Underline = if UNDERLINE_IMAGE ~= ""
				then e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, underlineXOffset, 1, -8 + underlineYOffset),
					Size = UDim2.fromOffset(underlineWidth, underlineHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = UNDERLINE_IMAGE,
					ImageColor3 = Color3.fromRGB(255, 234, 154),
					ImageTransparency = underline.transparency,
					ScaleType = Enum.ScaleType.Stretch,
					ZIndex = zIndex + 2,
				})
				else e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, underlineXOffset, 1, -8 + underlineYOffset),
					Size = UDim2.fromOffset(underlineWidth, 4),
					BackgroundColor3 = Color3.fromRGB(255, 234, 154),
					BackgroundTransparency = underline.transparency,
					BorderSizePixel = 0,
					ZIndex = zIndex + 2,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				}),
		}),
	})
end
