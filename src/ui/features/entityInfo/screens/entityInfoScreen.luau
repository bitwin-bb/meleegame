--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local TextLabel = require(ReplicatedStorage.UI.core.primitives.TextLabel)
local entityInfoSlice = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoSlice)
local entityInfoThunks = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoThunks)

type EntityInfoState = entityInfoSlice.EntityInfoState

type EntityInfoScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	cursorOffset: Vector2?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_CURSOR_OFFSET = Vector2.new(24, 28)
local DEFAULT_PANEL_SIZE = Vector2.new(220, 74)
local POSITION_LERP_ALPHA = 0.28

local LOW_HEALTH_COLOR = Color3.fromRGB(234, 63, 63)
local MID_HEALTH_COLOR = Color3.fromRGB(255, 223, 45)
local HIGH_HEALTH_COLOR = Color3.fromRGB(84, 214, 92)

local function resolveHealthColor(hpPercent: number): Color3
	local clamped = math.clamp(hpPercent, 0, 1)
	if clamped <= 0.5 then
		return LOW_HEALTH_COLOR:Lerp(MID_HEALTH_COLOR, clamped / 0.5)
	end
	return MID_HEALTH_COLOR:Lerp(HIGH_HEALTH_COLOR, (clamped - 0.5) / 0.5)
end

return function(props: EntityInfoScreenProps): React.ReactNode
	local entityState, setEntityState = React.useState(function(): EntityInfoState
		return entityInfoSlice.entityInfoStateAtom()
	end)
	local cursorOffset = props.cursorOffset or DEFAULT_CURSOR_OFFSET

	local initialPosition = entityState.mousePosition + cursorOffset
	local smoothPosition, setSmoothPosition = React.useBinding(initialPosition)
	local targetPositionRef = React.useRef(initialPosition)
	local currentPositionRef = React.useRef(initialPosition)

	React.useEffect(function()
		local stop = entityInfoThunks.start()
		local unsubscribe = Charm.subscribe(entityInfoSlice.entityInfoStateAtom, function(nextState: EntityInfoState)
			setEntityState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			stop()
		end
	end, {})

	React.useEffect(function()
		targetPositionRef.current = entityState.mousePosition + cursorOffset
	end, { entityState.mousePosition, cursorOffset })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function()
			local current = currentPositionRef.current
			local target = targetPositionRef.current
			local nextPosition = current:Lerp(target, POSITION_LERP_ALPHA)
			currentPositionRef.current = nextPosition
			setSmoothPosition(nextPosition)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	if props.visible == false or entityState.visible ~= true or entityState.runtimeId == nil then
		return nil
	end

	local zIndex = props.zIndex or 160
	local hpText = entityInfoSlice.formatHpText(entityState)
	local displayName = if entityState.displayName ~= "" then entityState.displayName else "Entity"
	local hpPercent = if entityState.maxHp > 0 then math.clamp(entityState.hp / entityState.maxHp, 0, 1) else 0
	local healthColor = resolveHealthColor(hpPercent)

	return e("Frame", {
		Name = "EntityInfoScreen",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = props.layoutOrder or 998,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Active = false,
	}, {
		Card = e("Frame", {
			Name = "EntityInfoCard",
			Size = UDim2.fromOffset(DEFAULT_PANEL_SIZE.X, DEFAULT_PANEL_SIZE.Y),
			Position = smoothPosition:map(function(position: Vector2)
				return UDim2.fromOffset(math.floor(position.X), math.floor(position.Y))
			end),
			BackgroundColor3 = Color3.fromRGB(18, 22, 31),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(245, 214, 44),
				Transparency = 1,
				Thickness = 1.2,
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			Title = e(TextLabel, {
				name = "EntityName",
				text = displayName,
				size = UDim2.new(1, 0, 0, 20),
				position = UDim2.fromOffset(0, 0),
				backgroundTransparency = 1,
				textSize = 15,
				font = Enum.Font.GothamBold,
				textXAlignment = Enum.TextXAlignment.Left,
				textYAlignment = Enum.TextYAlignment.Center,
				textColor3 = Color3.fromRGB(255, 255, 255),
				zIndex = zIndex + 2,
				effects = {
					shadow = {
						enabled = false,
					},
				},
			}),
			HpValue = e(TextLabel, {
				name = "EntityHpValue",
				text = hpText,
				size = UDim2.new(1, 0, 0, 18),
				position = UDim2.fromOffset(0, 24),
				backgroundTransparency = 1,
				textSize = 14,
				font = Enum.Font.GothamBold,
				textXAlignment = Enum.TextXAlignment.Left,
				textYAlignment = Enum.TextYAlignment.Center,
				textColor3 = Color3.fromRGB(255, 255, 255),
				zIndex = zIndex + 2,
				effects = nil,
			}),
			HealthBarTrack = e("Frame", {
				Name = "HealthBarTrack",
				Size = UDim2.new(1, 0, 0, 11),
				Position = UDim2.new(0, 0, 1, -11),
				BackgroundColor3 = Color3.fromRGB(36, 42, 55),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 2,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Fill = e("Frame", {
					Name = "Fill",
					Size = UDim2.fromScale(hpPercent, 1),
					BackgroundColor3 = healthColor,
					BorderSizePixel = 0,
					ZIndex = zIndex + 3,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Glow = e("UIGradient", {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, healthColor:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
							ColorSequenceKeypoint.new(1, healthColor),
						}),
						Rotation = 0,
					}),
				}),
			}),
		}),
	})
end
