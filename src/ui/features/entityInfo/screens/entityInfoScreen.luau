--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local DropsInfo = require(ReplicatedStorage.UI.core.components.DropsInfo)
local entityInfoSlice = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoSlice)
local entityInfoThunks = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoThunks)

type EntityInfoState = entityInfoSlice.EntityInfoState
type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

type EntityInfoScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local LOW_HEALTH_COLOR = Color3.fromRGB(234, 63, 63)
local MID_HEALTH_COLOR = Color3.fromRGB(255, 223, 45)
local HIGH_HEALTH_COLOR = Color3.fromRGB(84, 214, 92)
local HEALTH_BAR_SPRING: SpringOptions = {
	frequency = 1.5,
	damping = 1,
}

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

	local hpPercent = if entityState.maxHp > 0 then math.clamp(entityState.hp / entityState.maxHp, 0, 1) else 0
	local smoothedHpPercent, setSmoothedHpPercent = React.useBinding(hpPercent)
	local targetHpPercentRef = React.useRef(hpPercent)
	local motionRef = React.useRef(nil :: NumberMotion?)
	local previousRuntimeIdRef = React.useRef(entityState.runtimeId)

	React.useEffect(function()
		local runtimeId = entityState.runtimeId
		local previousRuntimeId = previousRuntimeIdRef.current
		local motion = motionRef.current

		if runtimeId ~= previousRuntimeId then
			previousRuntimeIdRef.current = runtimeId
			targetHpPercentRef.current = hpPercent
			if motion ~= nil then
				motion:immediate(hpPercent)
			end
			setSmoothedHpPercent(hpPercent)
			return
		end

		targetHpPercentRef.current = hpPercent
	end, { entityState.runtimeId, hpPercent })

	React.useEffect(function()
		local motion: NumberMotion = Ripple.createMotion(hpPercent)
		motionRef.current = motion
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			motion:spring(targetHpPercentRef.current, HEALTH_BAR_SPRING)
			setSmoothedHpPercent(math.clamp(motion:step(deltaTime), 0, 1))
		end)

		return function()
			connection:Disconnect()
			if motionRef.current == motion then
				motionRef.current = nil
			end
			motion:destroy()
		end
	end, {})

	local healthColor = smoothedHpPercent:map(function(value: number)
		return resolveHealthColor(value)
	end)

	if props.visible == false or entityState.visible ~= true or entityState.runtimeId == nil or entityState.adornee == nil then
		return nil
	end

	local zIndex = props.zIndex or 160
	local displayName = if entityState.displayName ~= "" then entityState.displayName else "Entity"

	return e(DropsInfo, {
		name = "EntityInfoScreen",
		adornee = entityState.adornee,
		visible = true,
		enabled = true,
		alwaysOnTop = true,
		animationEnabled = false,
		gradientEnabled = false,
		showIcon = false,
		showAmount = false,
		showRarityPill = false,
		title = displayName,
		subtitle = "",
		description = "",
		maxDistance = 150,
		billboardSize = UDim2.fromOffset(260, 96),
		cardSize = UDim2.fromOffset(220, 36),
		cardPadding = UDim.new(0, 0),
		contentPadding = UDim.new(0, 0),
		strokeThickness = 1,
		studsOffset = Vector3.new(0, -2.9, 0),
		titleTextSize = 15,
		zIndex = zIndex,
		theme = {
			backgroundColor = Color3.fromRGB(17, 21, 29),
			backgroundTransparency = 1,
			strokeColor = Color3.fromRGB(96, 118, 146),
			strokeTransparency = 1,
			titleColor = Color3.fromRGB(248, 250, 255),
			titleTransparency = 0,
		},
		nativeCard = {
			BackgroundTransparency = 1,
		},
		nativeTitle = {
			Visible = false,
		},
		children = {
			Shadow = e("Frame", {
				Name = "Shadow",
				Visible = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}),
			Stack = e("Frame", {
				Name = "Stack",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 4,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 2),
					PaddingBottom = UDim.new(0, 0),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				HealthBarTrack = e("Frame", {
					Name = "HealthBarTrack",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 8),
					BackgroundColor3 = Color3.fromRGB(35, 41, 55),
					BackgroundTransparency = 0.06,
					BorderSizePixel = 0,
					ZIndex = zIndex + 4,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Fill = e("Frame", {
						Name = "Fill",
						Size = smoothedHpPercent:map(function(value: number)
							return UDim2.fromScale(value, 1)
						end),
						BackgroundColor3 = healthColor,
						BorderSizePixel = 0,
						ZIndex = zIndex + 5,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						Glow = e("UIGradient", {
							Color = healthColor:map(function(color: Color3)
								return ColorSequence.new({
									ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
									ColorSequenceKeypoint.new(1, color),
								})
							end),
						}),
					}),
				}),
				Name = e("TextLabel", {
					Name = "Name",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = Enum.Font.GothamBold,
					Text = displayName,
					TextColor3 = Color3.fromRGB(248, 250, 255),
					TextSize = 15,
					TextTransparency = 0,
					TextWrapped = false,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = zIndex + 5,
				}),
			}),
		},
	})
end
