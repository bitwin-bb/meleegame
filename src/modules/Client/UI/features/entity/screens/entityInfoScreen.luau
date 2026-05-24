--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropsInfo = require(script:FindFirstAncestor("game").Client.UI.core.components.DropsInfo)
local EntityHealthBar = require(script:FindFirstAncestor("game").Client.UI.features.entity.components.EntityHealthBar)
local React = require(ReplicatedStorage.Packages.React)
local entityInfoSlice = require(script:FindFirstAncestor("game").Client.UI.features.entity.state.entityInfoSlice)
local entityInfoThunks = require(script:FindFirstAncestor("game").Client.UI.features.entity.state.entityInfoThunks)
local useLast = require(script:FindFirstAncestor("game").Client.UI.shared.useLast)
local useSpring = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useSpring)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type EntityInfoState = entityInfoSlice.EntityInfoState

type EntityInfoScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local LOW_HEALTH_COLOR = Color3.fromRGB(234, 63, 63)
local MID_HEALTH_COLOR = Color3.fromRGB(255, 223, 45)
local HIGH_HEALTH_COLOR = Color3.fromRGB(84, 214, 92)
local HEALTH_BAR_SPRING = {
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
	local entityState = (useStore(entityInfoSlice.entityInfoStateAtom) :: EntityInfoState?)
		or entityInfoSlice.entityInfoStateAtom()

	React.useEffect(function()
		local stop = entityInfoThunks.start()

		return function()
			stop()
		end
	end, {})

	local hpPercent = if entityState.maxHp > 0 then math.clamp(entityState.hp / entityState.maxHp, 0, 1) else 0
	local previousRuntimeId = useLast(entityState.runtimeId)
	local healthSpring = useSpring(hpPercent, {
		initialValue = hpPercent,
		spring = HEALTH_BAR_SPRING,
		clamp = function(value: number): number
			return math.clamp(value, 0, 1)
		end,
	})

	React.useEffect(function()
		if entityState.runtimeId ~= previousRuntimeId then
			healthSpring.jumpTo(hpPercent)
			return
		end

		healthSpring.setTarget(hpPercent)
	end, ({ entityState.runtimeId, previousRuntimeId, hpPercent, healthSpring.setTarget, healthSpring.jumpTo } :: { any }))

	local healthColor = healthSpring.binding:map(function(value: number)
		return resolveHealthColor(value)
	end)

	if
		props.visible == false
		or entityState.visible ~= true
		or entityState.runtimeId == nil
		or entityState.adornee == nil
	then
		return nil
	end

	local zIndex = props.zIndex or 160
	local displayName = if entityState.displayName ~= "" then entityState.displayName else "Entity"

	return e(DropsInfo, {
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
			shadowTransparency = 1,
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
			e("Frame", {
				Visible = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}),
			e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 4,
			}, {
				e("UIPadding", {
					PaddingTop = UDim.new(0, 2),
					PaddingBottom = UDim.new(0, 0),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				e(EntityHealthBar, {
					healthSize = healthSpring.binding:map(function(value: number)
						return UDim2.fromScale(value, 1)
					end),
					healthColor = healthColor,
					trackTransparency = 1,
					zIndex = zIndex + 4,
				}),
				e("TextLabel", {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = Enum.Font.GothamBold,
					Text = displayName,
					TextColor3 = Color3.fromRGB(248, 250, 255),
					TextSize = 15,
					TextTransparency = 0,
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					TextStrokeTransparency = 0.35,
					TextWrapped = false,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = zIndex + 5,
				}),
			}),
		},
	})
end
