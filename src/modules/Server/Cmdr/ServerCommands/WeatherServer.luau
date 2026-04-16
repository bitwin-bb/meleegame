--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for WeatherServer.")

local WeatherServiceServer = require(gameRoot.Server.Services.WeatherService.WeatherServiceServer)

return function(_context, weatherKind: string, transitionSecondsRaw: number?)
	local appliedWeather = WeatherServiceServer:setWeather(weatherKind, transitionSecondsRaw, true)
	if transitionSecondsRaw == nil then
		return (`Set weather to {appliedWeather}.`)
	end

	return (`Set weather to {appliedWeather} with a {math.max(0, transitionSecondsRaw)} second transition.`)
end
