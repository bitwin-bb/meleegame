local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local React: any = require(ReplicatedStorage.Packages.React)
local Ripple: any = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type TweenOptions = Ripple.TweenOptions

export type ItemAppearOptions = {
	enabled: boolean?,
	trigger: any?,
	fromScale: number?,
	toScale: number?,
	tween: TweenOptions?,
	onComplete: (() -> ())?,
}

local DEFAULT_TWEEN: TweenOptions = {
	time = 0.22,
	style = Enum.EasingStyle.Back,
	direction = Enum.EasingDirection.Out,
}

local DEFAULT_FROM_SCALE = 0
local DEFAULT_TO_SCALE = 1

local function CoerceScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw < 0 then
		return fallback
	end

	return valueRaw
end

local function useItemAppear(options: ItemAppearOptions?): number
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local fromScale = CoerceScale(if options then options.fromScale else nil, DEFAULT_FROM_SCALE)
	local toScale = CoerceScale(if options then options.toScale else nil, DEFAULT_TO_SCALE)
	local tween = if options and options.tween ~= nil then options.tween else DEFAULT_TWEEN
	local onComplete = if options then options.onComplete else nil
	local trigger = if options then options.trigger else nil
	local scale, setScale = React.useState(if enabled then fromScale else 0)

	;(React.useEffect :: any)(function()
		if not enabled then
			setScale(0)
			return function() end
		end

		local motion: NumberMotion = Ripple.createMotion(fromScale)
		motion:tween(toScale, tween)

		local connection: RBXScriptConnection?
		connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local nextScale = motion:step(deltaTime)
			setScale(if nextScale == nextScale then math.max(nextScale, 0) else toScale)

			if motion:isComplete() and connection ~= nil then
				if onComplete ~= nil then
					onComplete()
				end

				connection:Disconnect()
				connection = nil
			end
		end)

		return function()
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
			motion:destroy()
		end
	end, { enabled, trigger, fromScale, toScale, tween, onComplete })

	return scale
end

return useItemAppear
