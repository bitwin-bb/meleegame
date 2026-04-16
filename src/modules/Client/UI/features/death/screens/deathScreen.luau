--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local deathSlice = require(script:FindFirstAncestor("game").Client.UI.features.death.state.deathSlice)
local deathThunks = require(script:FindFirstAncestor("game").Client.UI.features.death.state.deathThunks)
local useDeathScreen = require(script:FindFirstAncestor("game").Client.UI.features.death.hooks.useDeathScreen)
local useCountDown = require(script:FindFirstAncestor("game").Client.UI.features.death.hooks.useCountDown)

type DeathState = deathSlice.DeathState

type DeathScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local TEXT_PROGRESS_EPSILON = 0.001
local MAIN_TEXT_POSITION = UDim2.new(0.5, 0, 0.42, 0)
local COUNTDOWN_BASE_POSITION = UDim2.new(0.5, 0, 0.42, 0)
local MAIN_TEXT_SIZE = Vector2.new(880, 92)
local COUNTDOWN_TEXT_SIZE = Vector2.new(520, 44)
local DEFAULT_MAIN_TEXT = "You were slain..."
local COUNTDOWN_APPEAR_DELAY_SECONDS = 2

return function(props: DeathScreenProps?): React.ReactNode
	local resolvedProps: DeathScreenProps = if props ~= nil then props else {}
	local deathState, setDeathState = React.useState(function(): DeathState
		return deathSlice.deathStateAtom()
	end)

	React.useEffect(function()
		local stop = deathThunks.start()
		local unsubscribe = Charm.subscribe(deathSlice.deathStateAtom, function(nextState: DeathState)
			setDeathState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			stop()
		end
	end, {})

	local canRender = resolvedProps.visible ~= false
	local deathAppearance = useDeathScreen({
		enabled = canRender and deathState.visible,
		minScale = 0.72,
		maxScale = 1,
	})
	local countDownAppearance = useCountDown({
		enabled = canRender and deathState.visible,
		respawnAt = deathState.respawnAt,
		diedAt = deathState.diedAt,
		appearDelay = COUNTDOWN_APPEAR_DELAY_SECONDS,
		fromOffset = Vector2.new(0, 4),
		toOffset = Vector2.new(0, 62),
		minScale = 0.72,
		maxScale = 1,
	})

	React.useEffect(function()
		if deathState.visible and countDownAppearance.canRespawn then
			deathSlice.hideDeath()
		end
	end, { deathState.visible, countDownAppearance.canRespawn })

	local showMainText = canRender and (deathState.visible or deathAppearance.progress > TEXT_PROGRESS_EPSILON)
	local showCountDown = canRender and (countDownAppearance.revealed or countDownAppearance.progress > TEXT_PROGRESS_EPSILON)
	if not showMainText and not showCountDown then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 230
	local deathText = if deathState.message ~= "" then deathState.message else DEFAULT_MAIN_TEXT
	local countDownText = if countDownAppearance.canRespawn
		then "Respawn ready..."
		else string.format("Respawning in %d...", countDownAppearance.secondsLeft)
	local countdownXOffset = math.floor(countDownAppearance.offset.X + 0.5)
	local countdownYOffset = math.floor(countDownAppearance.offset.Y + 0.5)

	return e("Frame", {
		Name = "DeathScreen",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = resolvedProps.layoutOrder or 990,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Active = false,
	}, {
		MainText = e("TextLabel", {
			Name = "MainText",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = MAIN_TEXT_POSITION,
			Size = UDim2.fromOffset(MAIN_TEXT_SIZE.X, MAIN_TEXT_SIZE.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = deathText,
			Font = Enum.Font.GothamBlack,
			TextSize = 62,
			TextColor3 = Color3.fromRGB(255, 236, 236),
			TextStrokeColor3 = Color3.fromRGB(48, 9, 9),
			TextStrokeTransparency = deathAppearance.strokeTransparency,
			TextTransparency = deathAppearance.transparency,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 2,
		}, {
			Scale = e("UIScale", {
				Scale = deathAppearance.scale,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 197, 197)),
				}),
				Rotation = 90,
			}),
		}),
		CountDownText = if showCountDown
			then e("TextLabel", {
				Name = "CountDownText",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(
					COUNTDOWN_BASE_POSITION.X.Scale,
					COUNTDOWN_BASE_POSITION.X.Offset + countdownXOffset,
					COUNTDOWN_BASE_POSITION.Y.Scale,
					COUNTDOWN_BASE_POSITION.Y.Offset + countdownYOffset
				),
				Size = UDim2.fromOffset(COUNTDOWN_TEXT_SIZE.X, COUNTDOWN_TEXT_SIZE.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = countDownText,
				Font = Enum.Font.GothamBold,
				TextSize = 34,
				TextColor3 = Color3.fromRGB(255, 223, 223),
				TextStrokeColor3 = Color3.fromRGB(33, 6, 6),
				TextStrokeTransparency = countDownAppearance.strokeTransparency,
				TextTransparency = countDownAppearance.transparency,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex + 3,
			}, {
				Scale = e("UIScale", {
					Scale = countDownAppearance.scale,
				}),
			})
			else nil,
	})
end
