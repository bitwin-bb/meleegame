local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Layer = require("Layer")
local React = require(ReplicatedStorage.Packages.React)
local Scale = require("Scale")
local deathSlice = require("deathSlice")
local deathThunks = require("deathThunks")
local useCountDown = require("useCountDown")
local useDeathScreen = require("useDeathScreen")
local useStore = require("useCoreStore")

type DeathState = deathSlice.DeathState

type DeathScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local TEXT_PROGRESS_EPSILON = 0.001
local MAIN_TEXT_POSITION = UDim2.fromScale(0.5, 0.42)
local COUNTDOWN_BASE_POSITION = UDim2.fromScale(0.5, 0.42)
local MAIN_TEXT_SIZE = Vector2.new(880, 92)
local COUNTDOWN_TEXT_SIZE = Vector2.new(520, 44)
local DEFAULT_MAIN_TEXT = "You were slain..."
local COUNTDOWN_APPEAR_DELAY_SECONDS = 2

return function(props: DeathScreenProps?): React.ReactNode
	local GotProps: DeathScreenProps = if props ~= nil then props else {} :: any
	local deathState = (useStore(deathSlice.deathStateAtom) :: DeathState?) or deathSlice.deathStateAtom()

	React.useEffect(function()
		local stop = deathThunks.Start()

		return function()
			stop()
		end
	end, {})

	local canRender = GotProps.visible ~= false
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
	local showCountDown = canRender
		and (countDownAppearance.revealed or countDownAppearance.progress > TEXT_PROGRESS_EPSILON)
	if not showMainText and not showCountDown then
		return nil
	end

	local zIndex = GotProps.zIndex or 230
	local deathText = if deathState.message ~= "" then deathState.message else DEFAULT_MAIN_TEXT
	local countDownText = if countDownAppearance.canRespawn
		then "Respawn ready..."
		else string.format("Respawning in %d...", countDownAppearance.secondsLeft)
	local countdownXOffset = math.floor(countDownAppearance.offset.X + 0.5)
	local countdownYOffset = math.floor(countDownAppearance.offset.Y + 0.5)

	return e(Layer, {
		layoutOrder = GotProps.layoutOrder or 990,
		zIndex = zIndex,
		active = false,
		children = {
			e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = MAIN_TEXT_POSITION,
				Size = UDim2.fromOffset(MAIN_TEXT_SIZE.X, MAIN_TEXT_SIZE.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = deathText,
				Font = Enum.Font.PatrickHand,
				TextSize = 62,
				TextColor3 = Color3.fromRGB(255, 236, 236),
				TextStrokeColor3 = Color3.fromRGB(48, 9, 9),
				TextStrokeTransparency = deathAppearance.strokeTransparency,
				TextTransparency = deathAppearance.transparency,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex + 2,
			}, {
				e(Scale, {
					scale = deathAppearance.scale,
				}),
				e("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 197, 197)),
					}),
					Rotation = 90,
				}),
			}),
			if showCountDown
				then e("TextLabel", {
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
					Font = Enum.Font.PatrickHand,
					TextSize = 34,
					TextColor3 = Color3.fromRGB(255, 223, 223),
					TextStrokeColor3 = Color3.fromRGB(33, 6, 6),
					TextStrokeTransparency = countDownAppearance.strokeTransparency,
					TextTransparency = countDownAppearance.transparency,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = zIndex + 3,
				}, {
					e(Scale, {
						scale = countDownAppearance.scale,
					}),
				})
				else nil,
		},
	})
end
