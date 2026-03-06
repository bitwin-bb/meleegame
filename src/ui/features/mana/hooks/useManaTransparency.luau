--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

export type ManaTransparencyOptions = {
	enabled: boolean?,
	spring: SpringOptions?,
}

local DEFAULT_SPRING: SpringOptions = {
	frequency = 2.8,
	damping = 0.84,
}

local function useManaTransparency(options: ManaTransparencyOptions?): number
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local spring = if options and options.spring ~= nil then options.spring else DEFAULT_SPRING
	local targetRef = React.useRef(if enabled then 1 else 0)
	local progress, setProgress = React.useState(targetRef.current)

	React.useEffect(function()
		targetRef.current = if enabled then 1 else 0
	end, { enabled })

	React.useEffect(function()
		local motion: NumberMotion = Ripple.createMotion(progress)
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			motion:spring(targetRef.current, spring)
			local nextProgress = math.clamp(motion:step(deltaTime), 0, 1)
			setProgress(nextProgress)
		end)

		return function()
			connection:Disconnect()
			motion:destroy()
		end
	end, { spring })

	return progress
end

return useManaTransparency
