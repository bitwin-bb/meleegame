--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

export type BubbleDepleteOptions = {
	fillAlphas: { number }?,
	speed: number?,
	epsilon: number?,
}

local DEFAULT_SPEED = 4
local DEFAULT_EPSILON = 0.001

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function cloneFillAlphas(fillAlphasRaw: any): { number }
	if typeof(fillAlphasRaw) ~= "table" then
		return { 1 }
	end

	local fillAlphas = Sift.Array.create(#fillAlphasRaw)
	for index, fillAlphaRaw in ipairs(fillAlphasRaw) do
		fillAlphas[index] = sanitizeNumber(fillAlphaRaw, 1, 0, 1)
	end

	if #fillAlphas == 0 then
		fillAlphas[1] = 1
	end

	return fillAlphas
end

local function joinStrings(values: { string }, delimiter: string): string
	local output = ""
	for index, value in values do
		if index > 1 then
			output ..= delimiter
		end
		output ..= value
	end
	return output
end

local function getFillAlphaKey(fillAlphas: { number }): string
	local keyParts = Sift.Array.create(#fillAlphas)
	for index, fillAlpha in ipairs(fillAlphas) do
		keyParts[index] = string.format("%.4f", fillAlpha)
	end
	return joinStrings(keyParts, "|")
end

local function synchronizeFillAlphas(currentFillAlphas: { number }, targetFillAlphas: { number }): ({ number }, boolean)
	local hasChanges = #currentFillAlphas ~= #targetFillAlphas
	local synchronizedFillAlphas = Sift.Array.create(#targetFillAlphas)

	for index, targetFillAlpha in ipairs(targetFillAlphas) do
		local synchronizedFillAlpha = sanitizeNumber(currentFillAlphas[index], targetFillAlpha, 0, 1)
		synchronizedFillAlphas[index] = synchronizedFillAlpha

		if synchronizedFillAlpha ~= currentFillAlphas[index] then
			hasChanges = true
		end
	end

	if not hasChanges then
		return currentFillAlphas, false
	end

	return synchronizedFillAlphas, true
end

local function findActiveBubbleIndex(
	currentFillAlphas: { number },
	targetFillAlphas: { number },
	epsilon: number
): number?
	for index, targetFillAlpha in ipairs(targetFillAlphas) do
		if math.abs(currentFillAlphas[index] - targetFillAlpha) > epsilon then
			return index
		end
	end

	return nil
end

local function stepFillAlpha(currentFillAlpha: number, targetFillAlpha: number, maxDelta: number): number
	if maxDelta <= 0 then
		return currentFillAlpha
	end

	local delta = targetFillAlpha - currentFillAlpha
	if math.abs(delta) <= maxDelta then
		return targetFillAlpha
	end

	if delta > 0 then
		return currentFillAlpha + maxDelta
	end

	return currentFillAlpha - maxDelta
end

local function useBubbleDeplete(options: BubbleDepleteOptions?): { number }
	local targetFillAlphas = cloneFillAlphas(if options then options.fillAlphas else nil)
	local targetKey = getFillAlphaKey(targetFillAlphas)
	local speed = sanitizeNumber(if options then options.speed else nil, DEFAULT_SPEED, 0.05, 60)
	local epsilon = sanitizeNumber(if options then options.epsilon else nil, DEFAULT_EPSILON, 0.0001, 0.1)
	local animatedFillAlphas, setAnimatedFillAlphas = React.useState(function(): { number }
		return Sift.Array.copy(targetFillAlphas)
	end)
	local targetFillAlphasRef = React.useRef(targetFillAlphas)

	targetFillAlphasRef.current = targetFillAlphas

	React.useEffect(function()
		setAnimatedFillAlphas(function(currentFillAlphas: { number }): { number }
			local synchronizedFillAlphas = synchronizeFillAlphas(currentFillAlphas, targetFillAlphas)
			return synchronizedFillAlphas
		end)
	end, { targetKey })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			setAnimatedFillAlphas(function(currentFillAlphas: { number }): { number }
				local currentTargetFillAlphas = targetFillAlphasRef.current
				local synchronizedFillAlphas = synchronizeFillAlphas(currentFillAlphas, currentTargetFillAlphas)
				local activeBubbleIndex =
					findActiveBubbleIndex(synchronizedFillAlphas, currentTargetFillAlphas, epsilon)

				if activeBubbleIndex == nil then
					return synchronizedFillAlphas
				end

				local nextFillAlpha = stepFillAlpha(
					synchronizedFillAlphas[activeBubbleIndex],
					currentTargetFillAlphas[activeBubbleIndex],
					math.max(deltaTime, 0) * speed
				)
				if math.abs(nextFillAlpha - currentTargetFillAlphas[activeBubbleIndex]) <= epsilon then
					nextFillAlpha = currentTargetFillAlphas[activeBubbleIndex]
				end

				if nextFillAlpha == synchronizedFillAlphas[activeBubbleIndex] then
					return synchronizedFillAlphas
				end

				return Sift.Array.set(synchronizedFillAlphas, activeBubbleIndex, nextFillAlpha)
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, { speed, epsilon })

	return animatedFillAlphas
end

return useBubbleDeplete
