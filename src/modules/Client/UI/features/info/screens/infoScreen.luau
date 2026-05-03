local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PortalTargets = require(script:FindFirstAncestor("game").Client.UI.core.utils.PortalTargets)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local TextLabel = require(script:FindFirstAncestor("game").Client.UI.core.primitives.TextLabel)
local infoState = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoState)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type HoverInfoState = infoState.HoverInfoState

type InfoScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	cursorOffset: Vector2?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_CURSOR_OFFSET = Vector2.new(16, 20)

return function(props: InfoScreenProps): React.ReactNode
	local hoverState = (useStore(infoState.infoStateAtom) :: HoverInfoState?) or infoState.infoStateAtom()

	React.useEffect(function()
		local stop = infoThunks.start()

		return function()
			stop()
		end
	end, {})

	if props.visible == false or hoverState.visible ~= true or hoverState.text == "" then
		return nil
	end

	local zIndex = props.zIndex or 140
	local offset = props.cursorOffset or DEFAULT_CURSOR_OFFSET
	local targetPosition = hoverState.mousePosition + offset

	local rootElement = e("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = props.layoutOrder or 999,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = zIndex,
	}, {
		HoverTooltip = e(TextLabel, {
			text = hoverState.text,
			size = UDim2.fromOffset(0, 0),
			position = UDim2.fromOffset(math.floor(targetPosition.X), math.floor(targetPosition.Y)),
			automaticSize = Enum.AutomaticSize.XY,
			backgroundColor3 = Color3.fromRGB(22, 28, 36),
			backgroundTransparency = 0.18,
			borderSizePixel = 0,
			textColor3 = Color3.fromRGB(245, 249, 255),
			textSize = 14,
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Center,
			zIndex = zIndex + 1,
			effects = {
				shadow = {
					enabled = true,
					color = Color3.fromRGB(0, 0, 0),
					transparency = 0.65,
					offset = Vector2.new(1, 1),
					layers = 1,
				},
			},
			children = {
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 6),
					PaddingBottom = UDim.new(0, 6),
				}),
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Color3.fromRGB(120, 144, 170),
					Transparency = 0.4,
					Thickness = 1,
				}),
			},
		}),
	})

	local portalTarget = PortalTargets.resolveUiScreenGui()
	if portalTarget ~= nil then
		return ReactRoblox.createPortal(rootElement, portalTarget)
	end

	return rootElement
end
